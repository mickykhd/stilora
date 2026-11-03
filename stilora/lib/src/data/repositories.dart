import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api_mappers.dart';
import 'mock_data.dart';

/// Simulated-latency repository interfaces.
///
/// Phase 3 ships these in-memory implementations so every screen is
/// navigable end-to-end before the Phase-4 API exists. Swapping in the
/// HTTP implementation is a provider override — screens never change.
///
/// Failure injection: construct with `failNext: n` to exercise error
/// states deterministically in tests.
class RepositoryException implements Exception {
  RepositoryException(this.message, {this.isOffline = false});
  final String message;
  final bool isOffline;
  @override
  String toString() => 'RepositoryException: $message';
}

abstract class WorkspaceRepository {
  // ── Auth (email + password against our own API) ───────────────
  /// Returns null on success, or a friendly error message.
  Future<String?> signIn(String email, String password);
  Future<String?> signUp(String email, String password, String name);
  /// Restores a persisted session (false → show sign-in).
  Future<bool> restoreSession();
  Future<UserProfile> myProfile();
  Future<void> signOut();

  // ── Data ──────────────────────────────────────────────────────
  Future<Workspace> currentWorkspace();
  Future<Workspace> createWorkspace(String name);
  Future<List<Channel>> channels();
  Future<Channel> createChannel(String name, {String topic});
  Future<List<DmConversation>> conversations();
  Future<List<UserProfile>> members();
  Future<List<Message>> messages(String channelId);
  Future<Message> sendMessage(String channelId, String text);
  Future<List<Message>> thread(String messageId);
  Future<List<ActivityItem>> activity();
  Future<void> markActivityRead();
  Future<List<(String, String, String)>> search(String query);
}

class MockWorkspaceRepository implements WorkspaceRepository {
  MockWorkspaceRepository({this.latency = const Duration(milliseconds: 250), this.failNext = 0, Random? random})
      : _random = random ?? Random(7);

  final Duration latency;

  /// Number of upcoming calls that should throw (error-state testing).
  int failNext;
  final Random _random;

  final List<Message> _extraMessages = [];

  Future<T> _gate<T>(T Function() body) async {
    await Future<void>.delayed(latency);
    if (failNext > 0) {
      failNext--;
      throw RepositoryException('Network request failed');
    }
    return body();
  }

  Future<File> _mockSessionFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/stilora_mock_session');
  }

  Future<void> _mockPersist() async {
    try {
      await (await _mockSessionFile()).writeAsString('signed-in', flush: true);
    } catch (_) {/* best effort */}
  }

  @override
  Future<String?> signIn(String email, String password) async {
    await Future<void>.delayed(latency);
    if (!email.contains('@')) return 'Enter a valid email address.';
    if (password.length < 8) return 'Password must be at least 8 characters.';
    await _mockPersist();
    return null;
  }

  @override
  Future<UserProfile> myProfile() => _gate(() => MockData.you);

  @override
  Future<String?> signUp(String email, String password, String name) async =>
      signIn(email, password);

  @override
  Future<bool> restoreSession() async {
    try {
      // Local IO only — must never stall the boot splash.
      final f = await _mockSessionFile()
          .timeout(const Duration(seconds: 2));
      return await f.exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      final f = await _mockSessionFile();
      if (await f.exists()) await f.delete();
    } catch (_) {/* best effort */}
  }

  @override
  Future<Workspace> currentWorkspace() => _gate(() => MockData.workspace);

  @override
  Future<Workspace> createWorkspace(String name) => _gate(() => Workspace(
        id: 'w_local',
        name: name,
        initials: ApiMappers.initials(name),
        onlineCount: 1,
      ));

  @override
  Future<List<Channel>> channels() => _gate(() => MockData.channels);

  @override
  Future<Channel> createChannel(String name, {String topic = ''}) =>
      _gate(() => Channel(
          id: 'c_${name.hashCode}', name: name, topic: topic));

  @override
  Future<List<DmConversation>> conversations() => _gate(() => MockData.dms);

  @override
  Future<List<UserProfile>> members() => _gate(() => MockData.members);

  @override
  Future<List<Message>> messages(String channelId) => _gate(() {
        if (channelId == 'c_design') {
          return [...MockData.designSyncMessages, ..._extraMessages];
        }
        return const [];
      });

  @override
  Future<Message> sendMessage(String channelId, String text) async {
    final draft = Message(
      id: 'm_local_${_random.nextInt(1 << 30)}',
      author: MockData.you,
      timeLabel: timeNow(),
      text: text,
      isMine: true,
      status: MessageStatus.sending,
    );
    await _gate(() {});
    final sent = draft.copyWith(status: MessageStatus.sent);
    if (channelId == 'c_design') _extraMessages.add(sent);
    return sent;
  }

  @override
  Future<List<Message>> thread(String messageId) =>
      _gate(() => MockData.designSyncThread);

  @override
  Future<List<ActivityItem>> activity() => _gate(() => MockData.activity);

  @override
  Future<void> markActivityRead() => _gate(() {});

  @override
  Future<List<(String, String, String)>> search(String query) => _gate(() {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return const [];
        return MockData.searchIndex
            .where((e) =>
                e.$2.toLowerCase().contains(q) || e.$3.toLowerCase().contains(q))
            .toList();
      });
}

/// Local clock label — "10:54 AM" style, matching mockup format.
String timeNow() {
  final now = DateTime.now();
  final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final m = now.minute.toString().padLeft(2, '0');
  final suffix = now.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $suffix';
}
