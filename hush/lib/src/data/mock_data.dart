import '../models/models.dart';

/// Seed data mirroring the Hush mockups (sample workspace "Studio Flow").
/// This stands in for the Phase-4 API until it is wired in.
abstract final class MockData {
  static final you = UserProfile(
    id: 'u_you',
    name: 'You',
    handle: 'you',
    initials: 'YO',
    avatarUrl: 'https://i.pravatar.cc/96?img=47',
    presence: UserPresence.online,
    role: MemberRole.admin,
  );

  static final sarah = UserProfile(
    id: 'u_sarah',
    name: 'Sarah Chen',
    handle: 'sarah',
    initials: 'SC',
    avatarUrl: 'https://i.pravatar.cc/96?img=44',
    presence: UserPresence.online,
    role: MemberRole.owner,
  );

  static final marcus = UserProfile(
    id: 'u_marcus',
    name: 'Marcus Vance',
    handle: 'marcus',
    initials: 'MV',
    avatarUrl: 'https://i.pravatar.cc/96?img=12',
    presence: UserPresence.idle,
    role: MemberRole.member,
  );

  static final priya = UserProfile(
    id: 'u_priya',
    name: 'Priya Raman',
    handle: 'priya',
    initials: 'PR',
    presence: UserPresence.online,
    role: MemberRole.member,
  );

  static final tomas = UserProfile(
    id: 'u_tomas',
    name: 'Tomás Herrera',
    handle: 'tomas',
    initials: 'TH',
    presence: UserPresence.offline,
    role: MemberRole.member,
  );

  static final workspace =
      Workspace(id: 'w_1', name: 'Studio Flow', initials: 'SF', onlineCount: 6);

  static final members = [sarah, marcus, priya, you, tomas];

  static final channels = [
    Channel(
      id: 'c_general',
      name: 'general',
      topic: 'Announcements and quiet coordination',
      lastActivityLabel: 'Quiet',
      memberCount: 14,
    ),
    Channel(
      id: 'c_design',
      name: 'design-sync',
      topic: 'Iterating on spatial hierarchy, typography scales & light-mode tranquility.',
      unreadCount: 3,
      lastActivityLabel: '14m ago',
      memberCount: 14,
      pinCount: 2,
    ),
    Channel(
      id: 'c_product',
      name: 'product',
      topic: 'Roadmap, releases, and quiet launches',
      lastActivityLabel: '1h ago',
      memberCount: 9,
    ),
    Channel(
      id: 'c_eng',
      name: 'eng-architecture',
      topic: 'Systems, APIs, and structural decisions',
      lastActivityLabel: '3h ago',
      memberCount: 7,
      isTyping: false,
    ),
  ];

  static final dms = [
    DmConversation(
      id: 'dm_sarah',
      peer: sarah,
      preview: 'Reviewed the Figma variab…',
      timeLabel: '12m',
      unread: true,
    ),
    DmConversation(
      id: 'dm_marcus',
      peer: marcus,
      preview: 'Flow state sync at 4pm',
      timeLabel: '2h',
    ),
  ];

  /// Messages for #design-sync (the mockup thread).
  static final designSyncMessages = [
    Message(
      id: 'm_1',
      author: sarah,
      timeLabel: '10:42 AM',
      label: 'Core Design',
      text:
          'I’ve uploaded the revised spatial system for the desktop canvas. Notice how the channel list collapses to a single level instead of deep Discord-like subtrees. Visual breathing room makes hours of continuous work feel effortless.',
      attachment: const Attachment(
        fileName: 'Hush-Token-Architecture-v3.sketch',
        sizeLabel: '4.2 MB',
        description: 'Updated layout margins, 12-column gutters, and tonal layers.',
      ),
    ),
    Message(
      id: 'm_2',
      author: marcus,
      timeLabel: '10:48 AM',
      text:
          'Agree entirely. Stripping out the decorative role badges and neon status icons instantly reduces cognitive stress. Let’s jump into the voice room to quickly tune the elevation tokens.',
      reactions: [const Reaction(emoji: '✦', count: 3)],
    ),
    Message(
      id: 'm_3',
      author: you,
      timeLabel: '10:51 AM',
      isMine: true,
      text:
          'I’m already in #Voice: Design Room. The audio capsule floating at the top feels totally unobtrusive. Feel free to join whenever ready.',
    ),
  ];

  /// Replies for the thread view (18 replies promised by the mockup).
  static final designSyncThread = [
    Message(
      id: 't_1',
      author: sarah,
      timeLabel: '11:02 AM',
      text: 'Pushed the token table — gutter is now a single 1.25rem value everywhere.',
      reactions: [const Reaction(emoji: '💜', count: 3)],
    ),
    Message(
      id: 't_2',
      author: priya,
      timeLabel: '11:05 AM',
      text: 'Verified the CSS export. Everything conforms to 8pt geometry cleanly. Pushing the design artifact package below:',
      attachment: const Attachment(
        fileName: 'Hush-Token-Architecture-v3.sketch',
        sizeLabel: '4.2 MB',
        description: 'Updated just now',
        icon: 'description',
      ),
      reactions: [const Reaction(emoji: '✨', count: 2)],
    ),
    Message(
      id: 't_3',
      author: you,
      timeLabel: '11:07 AM',
      isMine: true,
      text: 'Inspected the spacing tokens. The rhythm feels balanced and uncluttered. I’ll stage this in the preview container before merging.',
    ),
    Message(
      id: 't_4',
      author: marcus,
      timeLabel: '11:12 AM',
      text: 'Elevation pass done: halo-dropdown and halo-dialog are the only shadows in the system. Everything else is tonal.',
      reactions: [const Reaction(emoji: '👏', count: 1)],
    ),
  ];

  static final activity = [
    ActivityItem(
      id: 'a_1',
      kind: ActivityKind.mention,
      actorName: 'Sarah Chen',
      summary: 'mentioned you in #design-sync',
      channelName: 'design-sync',
      timeLabel: '4m',
    ),
    ActivityItem(
      id: 'a_2',
      kind: ActivityKind.reply,
      actorName: 'Marcus Vance',
      summary: 'replied to your thread “Scandinavian Spacing Tokens”',
      channelName: 'design-sync',
      timeLabel: '18m',
    ),
    ActivityItem(
      id: 'a_3',
      kind: ActivityKind.reaction,
      actorName: 'Priya Raman',
      summary: 'reacted ✦ to your message',
      timeLabel: '1h',
      unread: false,
    ),
    ActivityItem(
      id: 'a_4',
      kind: ActivityKind.voice,
      actorName: 'Voice: Design Room',
      summary: 'started — 3 people joined',
      timeLabel: '2h',
      unread: false,
    ),
    ActivityItem(
      id: 'a_5',
      kind: ActivityKind.invite,
      actorName: 'Tomás Herrera',
      summary: 'joined Studio Flow',
      timeLabel: 'Yesterday',
      unread: false,
    ),
  ];

  static final voiceRoom = VoiceRoom(
    roomName: 'Voice: Design Room',
    stateLabel: 'Connected • 3 in room',
    participants: [sarah, marcus, you],
    speakingIds: {'u_sarah'},
  );

  /// ⌘K search fixtures.
  static final searchIndex = <(String, String, String)>[
    ('message', 'design-sync', 'I’ve uploaded the revised spatial system for the desktop canvas…'),
    ('message', 'design-sync', 'Elevation pass done: halo-dropdown and halo-dialog are the only shadows…'),
    ('message', 'product', 'Launch checklist for v1.0 — stores, privacy policy, release notes'),
    ('message', 'general', 'Welcome to Hush. Deep work, held until you return.'),
    ('channel', 'design-sync', 'Iterating on spatial hierarchy, typography scales'),
    ('channel', 'eng-architecture', 'Systems, APIs, and structural decisions'),
    ('person', 'Sarah Chen', 'Owner • online'),
    ('person', 'Marcus Vance', 'Member • idle'),
    ('person', 'Priya Raman', 'Member • online'),
  ];
}
