import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/messages.dart';
import '../widgets/navigation.dart';
import '../widgets/primitives.dart';
import 'secondary_screens.dart';
import 'settings_screens.dart';

/// The signed-in shell: responsive 1/2/3-pane architecture.
///
/// - mobile (<768): single pane + bottom nav
/// - tablet (768–1024): 2 panes (nav + thread)
/// - desktop (>1024): 3 panes (nav + thread + context/members)
class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({super.key});

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  int _mobileTab = 1; // Threads | Channels | Voice | Settings
  bool _mobileInChannel = false;

  void _openChannel(Channel channel) {
    ref.read(activeChannelProvider.notifier).state = channel;
    ref.read(activeDmProvider.notifier).state = null;
    // Mark read optimistically.
    ref.read(channelsProvider.notifier).markRead(channel.id);
    if (Aura.isMobile(context)) setState(() => _mobileInChannel = true);
  }

  void _openDm(DmConversation dm) {
    ref.read(activeDmProvider.notifier).state = dm;
    ref.read(activeChannelProvider.notifier).state = null;
    if (Aura.isMobile(context)) setState(() => _mobileInChannel = true);
  }

  @override
  Widget build(BuildContext context) {
    final wide = Aura.isDesktop(context);
    final medium =
        !wide && MediaQuery.sizeOf(context).width > Aura.breakpointMobile;
    final connection = ref.watch(connectionProvider);
    final unread = ref.watch(unreadTotalProvider);

    // Global ⌘K / Ctrl+K
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            CommandPalette.show(context),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            CommandPalette.show(context),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (CommandPalette.isOpen) CommandPalette.hide(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(children: [
            if (connection != AppConnection.online)
              const OfflineBanner(),
            if (wide || medium)
              Expanded(
                child: Column(children: [
                  AuraTopBar(
                    onSearch: () => CommandPalette.show(context),
                    onToggleSettings: () => SettingsScreen.push(context),
                  ),
                  Expanded(
                    child: Row(children: [
                      AuraSideNav(
                        activeChannelId:
                            ref.watch(activeChannelProvider)?.id,
                        onChannelSelected: _openChannel,
                        onDmSelected: _openDm,
                        onNewThread: () => NewThreadSheet.show(context),
                        onOpenVoice: () => VoiceStageScreen.push(context),
                        onOpenSettings: () => SettingsScreen.push(context),
                        onOpenActivity: () =>
                            ActivityScreen.push(context),
                      ),
                      // Center pane with animated channel switch
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: Aura.durationNormal,
                          switchInCurve: Aura.easingEmphasized,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                      begin: const Offset(0.015, 0),
                                      end: Offset.zero)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: _CenterPane(
                            key: ValueKey(ref
                                .watch(activeChannelProvider)
                                ?.id),
                            onOpenThread: (m) =>
                                ThreadScreen.push(context, m),
                            onOpenMembers: wide
                                ? null
                                : () => MembersSheet.show(context),
                          ),
                        ),
                      ),
                      // Third pane: members/context (>1024px)
                      if (wide)
                        const _ContextPane(),
                    ]),
                  ),
                ]),
              )
            else
              // ── Mobile single pane ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: Aura.durationNormal,
                  switchInCurve: Aura.easingEmphasized,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0.04, 0), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: _mobileTab == 3
                      ? const MobileSettingsTab(key: ValueKey('settings'))
                      : _mobileTab == 2
                          ? const MobileVoiceTab(key: ValueKey('voice'))
                          : _mobileInChannel
                              ? _CenterPane(
                                  key: const ValueKey('channel'),
                                  mobile: true,
                                  onBack: () => setState(
                                      () => _mobileInChannel = false),
                                  onOpenThread: (m) =>
                                      ThreadScreen.push(context, m),
                                  onOpenMembers: () =>
                                      MembersSheet.show(context),
                                )
                              : MobileListTab(
                                  key: ValueKey('list$_mobileTab'),
                                  dmMode: _mobileTab == 0,
                                  onChannelSelected: _openChannel,
                                  onDmSelected: _openDm,
                                  onSearch: () =>
                                      SearchScreen.push(context),
                                  onCompose: () =>
                                      NewThreadSheet.show(context),
                                  onActivity: () =>
                                      ActivityScreen.push(context),
                                ),
                ),
              ),
            if (!(wide || medium))
              AuraBottomNav(
                index: _mobileTab,
                unreadBadge: unread,
                onChanged: (i) => setState(() {
                  _mobileTab = i;
                  _mobileInChannel = false;
                }),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Center pane: channel header + capsule + feed + composer.
class _CenterPane extends ConsumerWidget {
  const _CenterPane({
    super.key,
    this.onOpenThread,
    this.onOpenMembers,
    this.onBack,
    this.mobile = false,
  });

  final ValueChanged<Message>? onOpenThread;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onBack;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final dm = ref.watch(activeDmProvider);
    final channel = ref.watch(activeChannelProvider);

    if (channel == null && dm == null) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        message: 'Pick a channel to pick up the thread.',
      );
    }

    final title = channel?.name ?? dm!.peer.name;
    final topic = channel?.topic ?? 'Direct message';
    final messages = ref.watch(messagesProvider);

    return Container(
      key: const ValueKey('center'),
      color: Aura.surfaceBright,
      child: Column(children: [
        // Mobile top bar
        if (mobile)
          Material(
            color: scheme.surfaceContainerLowest,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Aura.spaceSm, vertical: 6),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (channel != null)
                            Text('# ',
                                style: Aura.headlineSm.copyWith(
                                    color: scheme.outline, fontSize: 17)),
                          Flexible(
                            child: Text(title,
                                overflow: TextOverflow.ellipsis,
                                style: Aura.headlineSm.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (channel?.unreadCount != null &&
                              channel!.unreadCount > 0) ...[
                            const SizedBox(width: 6),
                            const UnreadDot(),
                          ],
                        ]),
                        Text(
                          topic,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Aura.bodySm
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  AuraAvatar(
                    initials: 'SC',
                    size: 26,
                    presence: 0,
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: onOpenMembers,
                  ),
                ]),
              ),
            ),
          ),
        // Voice capsule (floating, only when in a room)
        if (ref.watch(voiceRoomProvider).connected)
          Padding(
            padding: EdgeInsets.only(
              top: mobile ? 0 : Aura.spaceMd,
              left: Aura.spaceMd,
              right: Aura.spaceMd,
            ),
            child: VoiceCapsule(
                onOpenStage: () => VoiceStageScreen.push(context)),
          ),
        // Desktop channel banner
        if (!mobile)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Aura.spaceXl, vertical: Aura.spaceMd),
            child: Row(children: [
              Flexible(
                child: Row(children: [
                  Text('# ', style: Aura.headlineSm.copyWith(color: scheme.outline)),
                  Flexible(
                    child: Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: Aura.headlineSm),
                  ),
                  const SizedBox(width: Aura.spaceMd),
                  Flexible(
                    child: Text(topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Aura.bodySm
                            .copyWith(color: scheme.outline)),
                  ),
                ]),
              ),
              if (channel != null) ...[
                AuraChip('${channel.pinCount} Pins', icon: Icons.push_pin),
                const SizedBox(width: Aura.spaceSm),
                InkWell(
                  onTap: onOpenMembers,
                  child: AuraChip('${channel.memberCount}',
                      icon: Icons.group_outlined),
                ),
              ],
            ]),
          ),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        // Feed
        Expanded(
          child: messages.when(
            loading: () => const _FeedSkeleton(),
            error: (e, _) => ErrorState(
              message: 'Couldn’t load messages.',
              offline: e is RepositoryException && e.isOffline,
              onRetry: () => ref.invalidate(messagesProvider),
            ),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.waving_hand_outlined,
                    message: 'No messages yet — say the first quiet hello.',
                    actionLabel: 'Send a message',
                  )
                : ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: mobile ? Aura.gutterMobile : Aura.spaceXl,
                      vertical: Aura.spaceLg,
                    ),
                    children: [
                      const DayDivider('Today'),
                      const SizedBox(height: Aura.spaceLg),
                      AuraEntrance.staggered(
                        step: const Duration(milliseconds: 55),
                        children: [
                          for (final m in list)
                            MessageRow(
                              message: m,
                              onOpenThread: () =>
                                  onOpenThread?.call(m),
                              onReact: (r) => ref
                                  .read(messagesProvider.notifier)
                                  .toggleReaction(m.id, r.emoji),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        // Composer
        Padding(
          padding: EdgeInsets.all(mobile ? Aura.spaceSm : Aura.spaceLg),
          child: MessageComposer(
            hint: 'Reply to ${channel != null ? '#${channel.name}' : title}…',
            onSend: (text) async {
              final repo = ref.read(workspaceRepositoryProvider);
              final id =
                  ref.read(activeChannelProvider)?.id ?? 'c_design';
              try {
                final sent = await repo.sendMessage(id, text);
                await ref.read(messagesProvider.notifier).append(sent);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message failed to send')),
                  );
                }
              }
            },
          ),
        ),
        if (!mobile)
          Padding(
            padding: const EdgeInsets.only(bottom: Aura.spaceSm),
            child: Text('Hush • Focus Mode Enabled',
                style: Aura.labelSm.copyWith(color: scheme.outline)),
          ),
      ]),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(Aura.spaceXl),
        child: AuraEntrance.staggered(
          step: const Duration(milliseconds: 70),
          children: [
            for (final w in [0.3, 0.8, 0.65, 0.9, 0.5])
              Padding(
                padding: const EdgeInsets.only(bottom: Aura.spaceLg),
                child: Row(children: [
                  const SkeletonBlock(width: 40, height: 40, radius: 999),
                  const SizedBox(width: Aura.spaceMd),
                  Expanded(
                    child: Column(children: [
                      SkeletonBlock(width: 120, height: 12),
                      const SizedBox(height: 8),
                      SkeletonBlock(width: double.infinity, height: 14),
                      const SizedBox(height: 6),
                      SkeletonBlock(
                          width: MediaQuery.sizeOf(context).width * w,
                          height: 14),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      );
}

/// Desktop third pane: voice participants + members.
class _ContextPane extends ConsumerWidget {
  const _ContextPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final room = ref.watch(voiceRoomProvider);
    final members = ref.watch(membersProvider);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
            left: BorderSide(color: scheme.surfaceContainerHighest)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(Aura.spaceMd),
          child: Row(children: [
            const AuraPulseDot(color: Aura.secondary, size: 7),
            const SizedBox(width: 8),
            Text('Voice Room',
                style: Aura.labelMd.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ),
        AuraEntrance.staggered(
          step: const Duration(milliseconds: 45),
          children: [
            for (final p in room.participants)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Aura.spaceSm, vertical: 3),
                child: AuraHoverable(
                  onTap: () {},
                  padding: const EdgeInsets.all(Aura.spaceSm),
                  child: Row(children: [
                    AuraAvatar(
                      initials: p.initials,
                      imageUrl: p.avatarUrl,
                      size: 28,
                      presence: p.presence.index,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.name,
                          overflow: TextOverflow.ellipsis,
                          style: Aura.bodySm),
                    ),
                    if (room.speakingIds.contains(p.id))
                      AuraAudioBars(
                          color: scheme.primary, height: 12, barCount: 3)
                    else
                      Icon(
                        p.id == 'u_you' && room.muted
                            ? Icons.mic_off
                            : Icons.mic_none,
                        size: 14,
                        color: scheme.outline,
                      ),
                  ]),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Aura.spaceMd, Aura.spaceLg, Aura.spaceMd, Aura.spaceXs),
          child: Text('MEMBERS',
              style: Aura.labelSm.copyWith(color: scheme.outline)),
        ),
        Expanded(
          child: members.when(
            loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, __) => ErrorState(
                message: 'Couldn’t load members.',
                onRetry: () => ref.invalidate(membersProvider)),
            data: (list) => ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => AuraRevealOnScroll(
                index: i,
                child: _MemberTile(user: list[i]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraHoverable(
      onTap: () => ProfileScreen.push(context, user),
      padding: const EdgeInsets.symmetric(
          horizontal: Aura.spaceMd, vertical: 6),
      child: Row(children: [
        AuraAvatar(
          initials: user.initials,
          imageUrl: user.avatarUrl,
          size: 30,
          presence: user.presence.index,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  overflow: TextOverflow.ellipsis,
                  style: Aura.bodySm.copyWith(fontWeight: FontWeight.w500)),
              if (user.role != null)
                Text(user.roleLabel,
                    style: Aura.labelSm.copyWith(color: scheme.outline)),
            ],
          ),
        ),
      ]),
    );
  }
}
