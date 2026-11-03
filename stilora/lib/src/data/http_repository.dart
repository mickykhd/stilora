import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api_mappers.dart';
import 'repositories.dart';

/// Live backend client — talks to the deployed Bun/Hono API
/// (`--dart-define=API_BASE_URL=…`, e.g. https://stilora-api.vercel.app).
///
/// Design notes:
/// - **Session**: Better Auth issues an httpOnly cookie; we persist the
///   raw `better-auth.session_token=…` pair to app-support storage and
///   replay it as a `Cookie` header on every request (no WebView needed).
/// - **Envelope**: API answers `{data: …}` or `{error: …}` — non-2xx
///   becomes a [RepositoryException] (connection failures flagged
///   offline so the UI can show the offline banner path).
/// - **Authors**: message views carry only `authorId`, so a workspace
///   members fetch seeds a users map used by message/activity mappers.
class HttpWorkspaceRepository implements WorkspaceRepository {
  HttpWorkspaceRepository(this.baseUrl) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'content-type': 'application/json'},
      // The API uses HTTP status codes we handle uniformly below.
      validateStatus: (_) => true,
    ));
  }

  final String baseUrl;
  late final Dio _dio;

  String? _cookie;
  String? _userId;
  UserProfile? _me;
  Workspace? _workspace;
  Map<String, UserProfile> _users = {};

  // ── session persistence ───────────────────────────────────────
  Future<File> _cookieFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/stilora_session.cookie');
  }

  Future<String?> _loadCookie() async {
    if (_cookie != null) return _cookie;
    try {
      // Guard: a stalled platform channel must never hang boot/requests.
      final f = await _cookieFile().timeout(const Duration(seconds: 2));
      if (await f.exists()) _cookie = (await f.readAsString()).trim();
    } catch (_) {/* no stored session */}
    return _cookie;
  }

  Future<void> _persistCookie(Response r) async {
    final setCookies = r.headers['set-cookie'] ?? const [];
    for (final raw in setCookies) {
      final pair = raw.split(';').first.trim();
      // Production (https) uses the __Secure- cookie-name prefix.
      if (pair.contains('better-auth.session_token=')) {
        _cookie = pair;
        try {
          final f = await _cookieFile();
          await f.writeAsString(pair, flush: true);
        } catch (_) {/* best effort */}
        return;
      }
    }
  }

  Future<void> _clearCookie() async {
    _cookie = null;
    _userId = null;
    try {
      final f = await _cookieFile();
      if (await f.exists()) await f.delete();
    } catch (_) {/* best effort */}
  }

  Map<String, String> _headers() =>
      _cookie == null ? const {} : {'cookie': _cookie!};

  Never _throw(Response r) {
    final data = r.data;
    final message = data is Map
        ? '${data['message'] ?? data['error'] ?? 'Request failed'}'
        : 'Request failed (${r.statusCode})';
    throw RepositoryException(message);
  }

  /// With validateStatus:true Dio returns error statuses as Responses;
  /// only genuine network failures throw DioException — map those to an
  /// offline-flagged RepositoryException.
  Future<Response<Map<String, dynamic>>> _send(
      Future<Response<Map<String, dynamic>>> call) async {
    try {
      return await call;
    } on DioException catch (e) {
      final net = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown;
      throw RepositoryException(
          net ? 'Cannot reach the server' : 'Network error: ${e.message}',
          isOffline: net);
    }
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? query}) async {
    await _loadCookie();
    final r = await _send(_dio.get<Map<String, dynamic>>(path,
        queryParameters: query, options: Options(headers: _headers())));
    if (r.statusCode == 401) await _clearCookie();
    if (r.statusCode == null || r.statusCode! >= 400) _throw(r);
    return r.data ?? const {};
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    await _loadCookie();
    final r = await _send(_dio.post<Map<String, dynamic>>(path,
        data: body, options: Options(headers: _headers())));
    await _persistCookie(r); // captures sign-in/sign-up session cookies
    if (r.statusCode == null || r.statusCode! >= 400) _throw(r);
    return r.data ?? const {};
  }

  Map<String, dynamic> _data(Map<String, dynamic> body) {
    final d = body['data'];
    if (d is Map<String, dynamic>) return d;
    if (d == null) return const {};
    return {'value': d};
  }

  // ── users / workspace caches (author resolution) ──────────────
  Future<void> _loadUsers() async {
    final ws = await _workspaceId();
    final body = await _get('/api/workspaces/$ws/members');
    final list = (body['data'] is Map
            ? (body['data'] as Map)['members']
            : null) as List? ??
        const [];
    _users = {
      for (final m in list.whereType<Map<String, dynamic>>())
        '${m['userId']}': ApiMappers.member(m),
    };
  }

  Future<String> _workspaceId() async {
    final ws = _workspace ?? await currentWorkspace();
    return ws.id;
  }

  // ── Auth ──────────────────────────────────────────────────────
  @override
  Future<String?> signIn(String email, String password) async {
    final body = await _post(
        '/api/auth/sign-in/email', {'email': email, 'password': password});
    await _whoAmI(body);
    return null;
  }

  @override
  Future<String?> signUp(String email, String password, String name) async {
    final body = await _post('/api/auth/sign-up/email',
        {'email': email, 'password': password, 'name': name});
    await _whoAmI(body);
    return null;
  }

  Future<void> _whoAmI(Map<String, dynamic> authBody) async {
    try {
      var user = authBody['user'];
      if (user is! Map) {
        final session = await _get('/api/auth/get-session');
        user = session['user'];
      }
      if (user is Map) {
        _userId = '${user['id']}';
        final email = '${user['email'] ?? ''}';
        _me = UserProfile(
          id: _userId!,
          name: '${user['name'] ?? (email.isNotEmpty ? email.split('@').first : 'You')}',
          handle: ApiMappers.handle(email.isNotEmpty ? email : '${user['name'] ?? 'you'}'),
          avatarUrl: user['image'] as String?,
          initials: ApiMappers.initials('${user['name'] ?? email}'),
        );
      }
    } catch (_) {/* session id is an optimization only */}
  }

  @override
  Future<UserProfile> myProfile() async {
    if (_me != null) return _me!;
    await restoreSession();
    return _me ??
        const UserProfile(id: 'self', name: 'You', handle: 'you');
  }

  @override
  Future<bool> restoreSession() async {
    try {
      final session = await _get('/api/auth/get-session');
      final u = session['user'];
      if (u is Map) {
        _userId = '${u['id']}';
        return true;
      }
      await _clearCookie();
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _post('/api/auth/sign-out', const {});
    } catch (_) {/* local clear matters most */}
    await _clearCookie();
    _workspace = null;
    _users = {};
  }

  // ── Data ──────────────────────────────────────────────────────
  @override
  Future<Workspace> currentWorkspace() async {
    final body = await _get('/api/workspaces');
    final list = _data(body)['workspaces'] as List? ?? const [];
    if (list.isEmpty) {
      throw RepositoryException('No workspace yet — create one to begin.');
    }
    _workspace =
        ApiMappers.workspace(Map<String, dynamic>.from(list.first as Map));
    return _workspace!;
  }

  @override
  Future<Workspace> createWorkspace(String name) async {
    final body = await _post('/api/workspaces', {'name': name});
    final ws = _data(body)['workspace'];
    _workspace =
        ws is Map ? ApiMappers.workspace(Map<String, dynamic>.from(ws)) : null;
    return _workspace!;
  }

  @override
  Future<List<Channel>> channels() async {
    final ws = await _workspaceId();
    final body = await _get('/api/workspaces/$ws/channels');
    final list = _data(body)['channels'] as List? ?? const [];
    return [
      for (final c in list.whereType<Map<String, dynamic>>())
        ApiMappers.channel(c),
    ];
  }

  @override
  Future<Channel> createChannel(String name, {String topic = ''}) async {
    final ws = await _workspaceId();
    final body = await _post('/api/workspaces/$ws/channels',
        {'name': name, if (topic.isNotEmpty) 'topic': topic});
    final data = _data(body);
    final ch = data['channel'] ?? data;
    return ApiMappers.channel(Map<String, dynamic>.from(ch as Map));
  }

  @override
  Future<List<DmConversation>> conversations() async {
    final body = await _get('/api/dm/conversations');
    final list = _data(body)['conversations'] as List? ?? const [];
    var myId = _userId;
    if (myId == null) {
      await _whoAmI(const {});
      myId = _userId ?? '';
    }
    return [
      for (final c in list.whereType<Map<String, dynamic>>())
        ApiMappers.dm(c, myId),
    ];
  }

  @override
  Future<List<UserProfile>> members() async {
    await _loadUsers();
    return _users.values.toList();
  }

  @override
  Future<List<Message>> messages(String channelId) async {
    if (_users.isEmpty) await _loadUsers();
    final myId = _userId ?? '';
    final body =
        await _get('/api/channels/$channelId/messages', query: {'limit': 50});
    final list = _data(body)['messages'] as List? ?? const [];
    return [
      for (final m in list.whereType<Map<String, dynamic>>())
        ApiMappers.message(m, _users, myId),
    ];
  }

  @override
  Future<Message> sendMessage(String channelId, String text) async {
    if (_users.isEmpty) await _loadUsers();
    final body = await _post('/api/channels/$channelId/messages',
        {'content': text, 'attachments': <dynamic>[]});
    final view = _data(body)['message'];
    if (view is Map) {
      return ApiMappers.message(
          Map<String, dynamic>.from(view), _users, _userId ?? '');
    }
    // Fallback: refetch the latest page.
    final list = await messages(channelId);
    return list.last;
  }

  @override
  Future<List<Message>> thread(String messageId) async {
    if (_users.isEmpty) await _loadUsers();
    final myId = _userId ?? '';
    final body = await _get('/api/messages/$messageId/replies');
    final list = _data(body)['replies'] as List? ?? const [];
    return [
      for (final m in list.whereType<Map<String, dynamic>>())
        ApiMappers.message(m, _users, myId),
    ];
  }

  @override
  Future<List<ActivityItem>> activity() async {
    if (_users.isEmpty) await _loadUsers();
    final body = await _get('/api/notifications', query: {'limit': 20});
    final list = _data(body)['notifications'] as List? ?? const [];
    return [
      for (final n in list.whereType<Map<String, dynamic>>())
        ApiMappers.activity(n, _users),
    ];
  }

  @override
  Future<void> markActivityRead() async {
    final body = await _get('/api/notifications',
        query: {'unreadOnly': 'true', 'limit': 50});
    final list = _data(body)['notifications'] as List? ?? const [];
    final ids = [
      for (final n in list.whereType<Map<String, dynamic>>())
        if (n['readAt'] == null) '${n['id']}',
    ];
    if (ids.isNotEmpty) await _post('/api/notifications/read', {'ids': ids});
  }

  @override
  Future<List<(String, String, String)>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final body = await _get('/api/search',
        query: {'q': query.trim(), 'scope': 'all'});
    return ApiMappers.searchTuples(_data(body));
  }
}
