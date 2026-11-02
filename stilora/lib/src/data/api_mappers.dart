import '../models/models.dart';

/// Pure mappers: live API JSON → app domain models.
///
/// Kept side-effect free so the mapping rules are unit-testable in
/// isolation (test/unit/api_mappers_test.dart). Field names mirror
/// `api/src` projections exactly (MessageView, publicChannelView, etc.).
abstract final class ApiMappers {
  /// "Sarah Chen" → "SC"; "you" → "YO"; single word → first two letters.
  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final w = parts.first;
      return w.length <= 2
          ? w.toUpperCase()
          : w.substring(0, 2).toUpperCase();
    }
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  /// Handle for profiles: email local-part ("live@stilora.app" → "live").
  static String handle(String emailOrName) {
    final at = emailOrName.indexOf('@');
    return (at > 0 ? emailOrName.substring(0, at) : emailOrName)
        .toLowerCase();
  }

  /// Clock label for message rows — "10:42 AM" (mockup format).
  static String clockLabel(DateTime t) {
    final now = DateTime.now();
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return '$h:$m $suffix';
    return '${local.day}/${local.month}/${local.year.toString().substring(2)}';
  }

  /// Relative label for channel/DM/activity rows: "just now" · "14m" ·
  /// "3h" · "Yesterday" · "2d" · else clock.
  static String relTime(DateTime t) {
    final diff = DateTime.now().toUtc().difference(t.toUtc());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return clockLabel(t);
  }

  static DateTime parseTime(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() ?? DateTime.now() : DateTime.now();

  // ── Workspaces ────────────────────────────────────────────────
  static Workspace workspace(Map<String, dynamic> m) => Workspace(
        id: '${m['id']}',
        name: '${m['name']}',
        initials: initials('${m['name']}'),
        onlineCount: 0, // presence is realtime-layer; API has no presence yet
      );

  // ── Channels ──────────────────────────────────────────────────
  static Channel channel(Map<String, dynamic> m) => Channel(
        id: '${m['id']}',
        name: '${m['name']}',
        topic: '${m['topic'] ?? ''}',
        kind: m['kind'] == 'private' ? ChannelKind.privateChannel : ChannelKind.publicChannel,
        unreadCount: 0, // needs realtime/read cursors — honest zero for now
        lastActivityLabel: '',
      );

  // ── Members / people ──────────────────────────────────────────
  static UserProfile member(Map<String, dynamic> m) {
    final email = '${m['email'] ?? ''}';
    return UserProfile(
      id: '${m['userId'] ?? m['id']}',
      name: '${m['name'] ?? email}',
      handle: handle(email.isNotEmpty ? email : '${m['name'] ?? ''}'),
      avatarUrl: m['image'] as String?,
      initials: initials('${m['name'] ?? email}'),
      presence: UserPresence.offline,
      role: switch (m['role']) {
        'owner' => MemberRole.owner,
        'admin' => MemberRole.admin,
        _ => null,
      },
    );
  }

  // ── Messages (MessageView) ────────────────────────────────────
  static Message message(
    Map<String, dynamic> v,
    Map<String, UserProfile> users,
    String myId,
  ) {
    final authorId = v['authorId'] as String?;
    final author = (authorId != null ? users[authorId] : null) ??
        UserProfile(
            id: authorId ?? 'unknown', name: 'Unknown', handle: 'unknown');
    final created = parseTime(v['createdAt']);
    final reactions = <Reaction>[
      for (final r in (v['reactions'] as List? ?? const []))
        if (r is Map)
          Reaction(
            emoji: '${r['emoji']}',
            count: (r['count'] as num?)?.toInt() ?? 0,
            mine: ((r['userIds'] as List?) ?? const [])
                .any((u) => '$u' == myId),
          ),
    ];
    final attachments = <Attachment>[
      for (final a in (v['attachments'] as List? ?? const []))
        if (a is Map) attachment(Map<String, dynamic>.from(a)),
    ];
    return Message(
      id: '${v['id']}',
      author: author,
      timeLabel: clockLabel(created),
      text: '${v['content'] ?? ''}',
      attachment: attachments.isEmpty ? null : attachments.first,
      reactions: reactions,
      replyCount: (v['replyCount'] as num?)?.toInt() ?? 0,
      status: MessageStatus.sent,
      isMine: authorId == myId,
    );
  }

  static Attachment attachment(Map<String, dynamic> a) {
    final bytes = (a['sizeBytes'] as num?)?.toInt() ?? 0;
    return Attachment(
      fileName: '${a['originalName'] ?? a['storageKey'] ?? 'file'}',
      sizeLabel: bytes >= 1048576
          ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
          : '${(bytes / 1024).toStringAsFixed(0)} KB',
      icon: 'grid_view',
    );
  }

  // ── DM conversations ──────────────────────────────────────────
  static DmConversation dm(Map<String, dynamic> m, String myId) {
    final members = (m['members'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(member)
        .where((u) => u.id != myId) // never pick myself as the peer
        .toList();
    final peer = members.isNotEmpty
        ? members.first
        : const UserProfile(id: '?', name: 'Unknown', handle: 'unknown');
    return DmConversation(
      id: '${m['id']}',
      peer: peer,
      preview: '${m['lastMessagePreview'] ?? 'No messages yet'}',
      timeLabel: m['lastMessageAt'] == null
          ? ''
          : relTime(parseTime(m['lastMessageAt'])),
      unread: m['lastReadMessageId'] != null ? false : false,
    );
  }

  // ── Activity feed ─────────────────────────────────────────────
  static ActivityItem activity(
    Map<String, dynamic> n,
    Map<String, UserProfile> users,
  ) {
    final payload = (n['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final actorId = '${payload['actorId'] ?? ''}';
    final actor = users[actorId];
    final kind = switch ('${n['type']}') {
      'mention' => ActivityKind.mention,
      'reply' => ActivityKind.reply,
      'reaction' => ActivityKind.reaction,
      'pin' => ActivityKind.pin,
      'invite' => ActivityKind.invite,
      'voice' => ActivityKind.voice,
      _ => ActivityKind.reply,
    };
    // The API stores structured payloads; the UI needs one calm sentence.
    final summary = switch (kind) {
      ActivityKind.mention => 'mentioned you',
      ActivityKind.reply => 'replied to your thread',
      ActivityKind.reaction => 'reacted ${payload['emoji'] ?? ''} to your message',
      ActivityKind.pin => 'pinned your message',
      ActivityKind.invite => 'joined the workspace',
      ActivityKind.voice => 'started a voice room',
    };
    return ActivityItem(
      id: '${n['id']}',
      kind: kind,
      actorName: actor?.name ?? 'Someone',
      summary: summary,
      timeLabel: relTime(parseTime(n['createdAt'])),
      unread: n['readAt'] == null,
      channelName: payload['channelId'] as String?,
    );
  }

  // ── Search (query, scope rows → UI tuples) ────────────────────
  static List<(String, String, String)> searchTuples(
    Map<String, dynamic> json,
  ) {
    final out = <(String, String, String)>[];
    for (final m in (json['messages'] as List? ?? const [])) {
      if (m is Map) {
        out.add((
          'message',
          '${m['channelName'] ?? 'message'}',
          '${m['content'] ?? ''}',
        ));
      }
    }
    for (final c in (json['channels'] as List? ?? const [])) {
      if (c is Map) out.add(('channel', '${c['name']}', '${c['topic'] ?? ''}'));
    }
    for (final p in (json['people'] as List? ?? const [])) {
      if (p is Map) out.add(('person', '${p['name']}', '${p['email'] ?? ''}'));
    }
    return out;
  }
}
