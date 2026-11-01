import 'package:equatable/equatable.dart';

/// Domain models for Hush. Immutable value objects shared by the mock
/// repositories (Phase 3) and the real API (Phase 4 wire format mirrors
/// these fields 1:1 — see api/src/routes).

enum UserPresence { online, idle, offline }

enum ChannelKind { publicChannel, privateChannel, dm }

enum MemberRole { owner, admin, member }

enum MessageStatus { sending, sent, failed }

class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.initials = '',
    this.presence = UserPresence.offline,
    this.role,
  });

  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final String initials;
  final UserPresence presence;
  final MemberRole? role;

  String get roleLabel => switch (role) {
        MemberRole.owner => 'Owner',
        MemberRole.admin => 'Admin',
        MemberRole.member => 'Member',
        null => '',
      };

  @override
  List<Object?> get props => [id, name, handle, avatarUrl, presence, role];
}

class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    required this.initials,
    required this.onlineCount,
  });

  final String id;
  final String name;
  final String initials;
  final int onlineCount;

  @override
  List<Object?> get props => [id, name, onlineCount];
}

class Channel extends Equatable {
  const Channel({
    required this.id,
    required this.name,
    this.topic = '',
    this.kind = ChannelKind.publicChannel,
    this.unreadCount = 0,
    this.lastActivityLabel = '',
    this.isTyping = false,
    this.isMuted = false,
    this.memberCount = 0,
    this.pinCount = 0,
  });

  final String id;
  final String name;
  final String topic;
  final ChannelKind kind;
  final int unreadCount;
  final String lastActivityLabel;
  final bool isTyping;
  final bool isMuted;
  final int memberCount;
  final int pinCount;

  Channel copyWith({
    int? unreadCount,
    String? topic,
    bool? isTyping,
    int? pinCount,
  }) =>
      Channel(
        id: id,
        name: name,
        topic: topic ?? this.topic,
        kind: kind,
        unreadCount: unreadCount ?? this.unreadCount,
        lastActivityLabel: lastActivityLabel,
        isTyping: isTyping ?? this.isTyping,
        isMuted: isMuted,
        memberCount: memberCount,
        pinCount: pinCount ?? this.pinCount,
      );

  @override
  List<Object?> get props =>
      [id, name, topic, kind, unreadCount, isTyping, pinCount];
}

class Attachment extends Equatable {
  const Attachment({
    required this.fileName,
    required this.sizeLabel,
    this.description = '',
    this.icon = 'grid_view',
  });

  final String fileName;
  final String sizeLabel;
  final String description;
  final String icon;

  @override
  List<Object?> get props => [fileName, sizeLabel];
}

class Reaction extends Equatable {
  const Reaction({required this.emoji, required this.count, this.mine = false});

  final String emoji;
  final int count;
  final bool mine;

  Reaction toggled() => Reaction(
        emoji: emoji,
        count: mine ? count - 1 : count + 1,
        mine: !mine,
      );

  @override
  List<Object?> get props => [emoji, count, mine];
}

class Message extends Equatable {
  const Message({
    required this.id,
    required this.author,
    required this.timeLabel,
    required this.text,
    this.attachment,
    this.reactions = const [],
    this.replyCount = 0,
    this.status = MessageStatus.sent,
    this.isMine = false,
    this.label,
    this.deleted = false,
  });

  final String id;
  final UserProfile author;
  final String timeLabel;
  final String text;
  final Attachment? attachment;
  final List<Reaction> reactions;
  final int replyCount;
  final MessageStatus status;
  final bool isMine;

  /// Optional channel-role chip (e.g. "Core Design").
  final String? label;
  final bool deleted;

  Message copyWith({MessageStatus? status, List<Reaction>? reactions}) =>
      Message(
        id: id,
        author: author,
        timeLabel: timeLabel,
        text: text,
        attachment: attachment,
        reactions: reactions ?? this.reactions,
        replyCount: replyCount,
        status: status ?? this.status,
        isMine: isMine,
        label: label,
        deleted: deleted,
      );

  @override
  List<Object?> get props =>
      [id, author, text, attachment, reactions, replyCount, status, deleted];
}

class DmConversation extends Equatable {
  const DmConversation({
    required this.id,
    required this.peer,
    required this.preview,
    required this.timeLabel,
    this.unread = false,
  });

  final String id;
  final UserProfile peer;
  final String preview;
  final String timeLabel;
  final bool unread;

  @override
  List<Object?> get props => [id, peer, preview, unread];
}

enum ActivityKind { mention, reply, reaction, invite, voice }

class ActivityItem extends Equatable {
  const ActivityItem({
    required this.id,
    required this.kind,
    required this.actorName,
    required this.summary,
    required this.timeLabel,
    this.unread = true,
    this.channelName,
  });

  final String id;
  final ActivityKind kind;
  final String actorName;
  final String summary;
  final String timeLabel;
  final bool unread;
  final String? channelName;

  @override
  List<Object?> get props => [id, kind, summary, unread];
}

/// Ephemeral voice-room state — lives in Ably/LiveKit, never persisted.
class VoiceRoom extends Equatable {
  const VoiceRoom({
    required this.roomName,
    required this.participants,
    required this.stateLabel,
    this.connected = true,
    this.muted = false,
    this.cameraOn = false,
    this.speakingIds = const {},
  });

  final String roomName;
  final List<UserProfile> participants;
  final String stateLabel;
  final bool connected;
  final bool muted;
  final bool cameraOn;
  final Set<String> speakingIds;

  VoiceRoom copyWith({
    bool? connected,
    bool? muted,
    bool? cameraOn,
    String? stateLabel,
    List<UserProfile>? participants,
    Set<String>? speakingIds,
  }) =>
      VoiceRoom(
        roomName: roomName,
        participants: participants ?? this.participants,
        stateLabel: stateLabel ?? this.stateLabel,
        connected: connected ?? this.connected,
        muted: muted ?? this.muted,
        cameraOn: cameraOn ?? this.cameraOn,
        speakingIds: speakingIds ?? this.speakingIds,
      );

  @override
  List<Object?> get props =>
      [roomName, participants, connected, muted, cameraOn, speakingIds];
}

/// Global app status used by the offline / error banners.
enum AppConnection { online, offline, reconnecting }
