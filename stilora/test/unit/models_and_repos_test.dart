import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/src/data/repositories.dart';
import 'package:stilora/src/models/models.dart';

void main() {
  group('Models', () {
    test('Reaction.toggled adds and removes own reaction', () {
      const r = Reaction(emoji: '✦', count: 3);
      final mine = r.toggled();
      expect(mine.count, 4);
      expect(mine.mine, isTrue);
      final back = mine.toggled();
      expect(back.count, 3);
      expect(back.mine, isFalse);
    });

    test('Message.copyWith preserves identity fields, changes status', () {
      final m = MockMessageFixtures.simple.copyWith(
          status: MessageStatus.failed);
      expect(m.id, 'm1');
      expect(m.author.name, 'You');
      expect(m.status, MessageStatus.failed);
    });

    test('Channel.copyWith only touches provided fields', () {
      final c = Channel(id: 'c1', name: 'general', unreadCount: 5);
      final read = c.copyWith(unreadCount: 0);
      expect(read.unreadCount, 0);
      expect(read.name, 'general');
      expect(read.kind, ChannelKind.publicChannel);
    });

    test('VoiceRoom.copyWith toggles mute and keeps participants', () {
      final room = VoiceRoom(
        roomName: 'Room',
        stateLabel: 'Connected',
        participants: const [],
      );
      final muted = room.copyWith(muted: true);
      expect(muted.muted, isTrue);
      expect(muted.roomName, 'Room');
    });

    test('UserProfile.roleLabel maps roles', () {
      expect(
        const UserProfile(id: 'x', name: 'X', handle: 'x', role: MemberRole.owner)
            .roleLabel,
        'Owner',
      );
      expect(
        const UserProfile(id: 'y', name: 'Y', handle: 'y').roleLabel,
        '',
      );
    });
  });

  group('MockWorkspaceRepository', () {
    late MockWorkspaceRepository repo;

    setUp(() {
      repo = MockWorkspaceRepository(
        latency: Duration.zero,
        random: null,
      );
    });

    test('returns seeded channels and workspace', () async {
      final ws = await repo.currentWorkspace();
      expect(ws.name, 'Studio Flow');
      final channels = await repo.channels();
      expect(channels.length, 4);
      expect(channels.map((c) => c.name),
          containsAll(['general', 'design-sync', 'product', 'eng-architecture']));
    });

    test('design-sync returns messages, other channels empty', () async {
      final design = await repo.messages('c_design');
      expect(design.length, 3);
      final general = await repo.messages('c_general');
      expect(general, isEmpty);
    });

    test('sendMessage appends to the channel and marks sent', () async {
      final before = await repo.messages('c_design');
      final sent = await repo.sendMessage('c_design', 'Hello quiet world');
      expect(sent.status, MessageStatus.sent);
      expect(sent.isMine, isTrue);
      final after = await repo.messages('c_design');
      expect(after.length, before.length + 1);
      expect(after.last.text, 'Hello quiet world');
    });

    test('failNext triggers repository exception then recovers', () async {
      repo.failNext = 1;
      await expectLater(repo.channels(), throwsA(isA<RepositoryException>()));
      final channels = await repo.channels();
      expect(channels, isNotEmpty);
    });

    test('thread returns replies', () async {
      final replies = await repo.thread('m_1');
      expect(replies.length, 4);
      expect(replies.where((m) => m.attachment != null), isNotEmpty);
    });

    test('search matches channels, messages and people', () async {
      final hits = await repo.search('design');
      expect(hits, isNotEmpty);
      expect(hits.any((h) => h.$1 == 'message' || h.$1 == 'channel'), isTrue);

      final empty = await repo.search('   ');
      expect(empty, isEmpty);
    });

    test('search is case-insensitive', () async {
      final upper = await repo.search('SARAH');
      final lower = await repo.search('sarah');
      expect(upper.length, lower.length);
      expect(upper, isNotEmpty);
    });

    test('activity feed seeded and markRead completes', () async {
      final items = await repo.activity();
      expect(items.length, 5);
      expect(items.where((a) => a.unread).length, 2);
      await repo.markActivityRead();
    });
  });

  group('timeNow', () {
    test('produces h:mm AM/PM format', () {
      final label = timeNow();
      expect(label, matches(RegExp(r'^(1[0-2]|[1-9]):[0-5][0-9] (AM|PM)$')));
    });
  });
}

/// Local fixture helper (kept out of lib — test-only).
class MockMessageFixtures {
  static final simple = Message(
    id: 'm1',
    author: const UserProfile(id: 'u', name: 'You', handle: 'you'),
    timeLabel: '10:00 AM',
    text: 'hi',
  );
}
