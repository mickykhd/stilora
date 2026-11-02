import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/src/data/api_mappers.dart';
import 'package:stilora/src/models/models.dart';

/// Mapping contract between the live API (api/src projections) and the
/// app's domain models. If the API shape changes, these tests fail first.
void main() {
  group('ApiMappers primitives', () {
    test('initials: multi, single, short, empty', () {
      expect(ApiMappers.initials('Sarah Chen'), 'SC');
      expect(ApiMappers.initials('you'), 'YO');
      expect(ApiMappers.initials('Tomás Herrera'), 'TH');
      expect(ApiMappers.initials('  Marcus   Vance '), 'MV');
      expect(ApiMappers.initials(''), '?');
    });

    test('handle: email local-part, else lowercase name', () {
      expect(ApiMappers.handle('live@stilora.app'), 'live');
      expect(ApiMappers.handle('Sarah Chen'), 'sarah chen'.replaceAll(' ', ' '));
      expect(ApiMappers.handle('plainhandle'), 'plainhandle');
    });

    test('clockLabel: today shows 12h clock, older shows date', () {
      final now = DateTime.now();
      expect(ApiMappers.clockLabel(now), matches(RegExp(r'^(1[0-2]|[1-9]):[0-5][0-9] (AM|PM)$')));
      final old = DateTime(now.year - 1, 3, 4, 13, 5);
      expect(ApiMappers.clockLabel(old), '4/3/25'); // compact d/M/yy
    });

    test('relTime: now → minutes → hours → yesterday → days', () {
      final now = DateTime.now().toUtc();
      expect(ApiMappers.relTime(now.subtract(const Duration(seconds: 5))), 'just now');
      expect(ApiMappers.relTime(now.subtract(const Duration(minutes: 14))), '14m');
      expect(ApiMappers.relTime(now.subtract(const Duration(hours: 3))), '3h');
      expect(ApiMappers.relTime(now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(ApiMappers.relTime(now.subtract(const Duration(days: 3))), '3d');
    });
  });

  group('ApiMappers models', () {
    test('workspace derives initials, presence is honest zero', () {
      final ws = ApiMappers.workspace({'id': 'w1', 'name': 'Live Workspace'});
      expect(ws.name, 'Live Workspace');
      expect(ws.initials, 'LW');
      expect(ws.onlineCount, 0); // no realtime presence yet — never fabricate
    });

    test('channel maps kind and never fabricates unread', () {
      final pub = ApiMappers.channel({
        'id': 'c1', 'name': 'general', 'topic': 't',
        'kind': 'public', 'archived': false,
      });
      expect(pub.kind, ChannelKind.publicChannel);
      expect(pub.unreadCount, 0);
      final priv = ApiMappers.channel({
        'id': 'c2', 'name': 'secret', 'topic': '', 'kind': 'private',
      });
      expect(priv.kind, ChannelKind.privateChannel);
    });

    test('member maps role + handle from email', () {
      final m = ApiMappers.member({
        'userId': 'u1', 'name': 'Live User', 'email': 'live@stilora.app',
        'image': null, 'role': 'owner',
      });
      expect(m.id, 'u1');
      expect(m.handle, 'live');
      expect(m.role, MemberRole.owner);
      expect(m.presence, UserPresence.offline);
    });

    test('message resolves author, mine flag, reactions with mine detection', () {
      const me = 'me-id';
      final users = {
        'u1': const UserProfile(id: 'u1', name: 'Sarah Chen', handle: 'sarah'),
      };
      final msg = ApiMappers.message({
        'id': 'm1',
        'authorId': 'u1',
        'content': 'hello #design-sync',
        'createdAt': DateTime.now().toIso8601String(),
        'replyCount': 3,
        'reactions': [
          {'emoji': '✦', 'count': 2, 'userIds': ['me-id', 'other']},
          {'emoji': '💜', 'count': 1, 'userIds': ['other']},
        ],
        'attachments': [
          {'storageKey': 'uploads/u1/x', 'originalName': 'file.sketch',
           'sizeBytes': 4200000, 'mimeType': 'image/png'},
        ],
      }, users, me);
      expect(msg.author.name, 'Sarah Chen');
      expect(msg.replyCount, 3);
      expect(msg.reactions.first.mine, isTrue);
      expect(msg.reactions.last.mine, isFalse);
      expect(msg.attachment!.sizeLabel, '4.0 MB');
      expect(msg.isMine, isFalse);

      final mine = ApiMappers.message(
          {'id': 'm2', 'authorId': 'me-id', 'content': 'x',
           'createdAt': DateTime.now().toIso8601String()},
          users, me);
      expect(mine.isMine, isTrue);
      // Unknown author degrades gracefully — never crashes.
      final unknown = ApiMappers.message(
          {'id': 'm3', 'authorId': 'ghost', 'content': 'x',
           'createdAt': DateTime.now().toIso8601String()},
          users, me);
      expect(unknown.author.name, 'Unknown');
    });

    test('dm picks peer outside me, previews safely', () {
      final dm = ApiMappers.dm({
        'id': 'ch1',
        'members': [
          {'userId': 'me', 'name': 'Me', 'email': 'me@x.dev'},
          {'userId': 's1', 'name': 'Sarah Chen', 'email': 'sarah@x.dev'},
        ],
        'lastMessageAt': DateTime.now()
            .subtract(const Duration(minutes: 12))
            .toIso8601String(),
        'lastMessagePreview': 'See you soon',
        'lastReadMessageId': null,
      }, 'me');
      expect(dm.peer.name, 'Sarah Chen');
      expect(dm.preview, 'See you soon');
      expect(dm.timeLabel, '12m');
    });

    test('activity builds a calm sentence per kind + unread from readAt', () {
      const users = {
        'u1': UserProfile(id: 'u1', name: 'Sarah Chen', handle: 'sarah'),
      };
      ActivityItem make(String type, Map<String, dynamic> payload, {Object? readAt}) =>
          ApiMappers.activity({
            'id': 'a', 'type': type, 'payload': payload, 'readAt': readAt,
            'createdAt': DateTime.now().toIso8601String(),
          }, users);
      expect(make('mention', {'actorId': 'u1'}).summary, 'mentioned you');
      expect(make('reaction', {'actorId': 'u1', 'emoji': '✦'}).summary,
          'reacted ✦ to your message');
      expect(make('pin', {'actorId': 'u1'}).summary, 'pinned your message');
      final unread = make('reply', {'actorId': 'u1'});
      expect(unread.unread, isTrue);
      expect(unread.actorName, 'Sarah Chen');
      final read = make('reply', {'actorId': 'u1'},
          readAt: DateTime.now().toIso8601String());
      expect(read.unread, isFalse);
      // Unknown actor degrades to "Someone".
      expect(make('invite', {'actorId': 'nobody'}).actorName, 'Someone');
    });

    test('search tuples order messages, channels, people', () {
      final tuples = ApiMappers.searchTuples({
        'messages': [
          {'content': 'revised spatial system', 'channelName': 'design-sync'},
        ],
        'channels': [
          {'name': 'product', 'topic': 'Roadmap'},
        ],
        'people': [
          {'name': 'Priya Raman', 'email': 'priya@x.dev'},
        ],
      });
      expect(tuples.length, 3);
      expect(tuples[0].$1, 'message');
      expect(tuples[0].$2, 'design-sync');
      expect(tuples[1].$1, 'channel');
      expect(tuples[2].$3, 'priya@x.dev');
      expect(ApiMappers.searchTuples(const {}), isEmpty);
    });
  });
}
