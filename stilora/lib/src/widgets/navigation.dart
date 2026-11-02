import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_data.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// ── Top navigation bar (desktop) ────────────────────────────────
class AuraTopBar extends ConsumerWidget {
  const AuraTopBar({super.key, this.onSearch, this.onToggleSettings});

  final VoidCallback? onSearch;
  final VoidCallback? onToggleSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final workspace = ref.watch(workspaceProvider).valueOrNull;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.surfaceContainerHighest)),
        ),
        child: Row(children: [
          // Brand
          AuraPressable(
            onTap: () {},
            child: Row(children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: Aura.primary,
                  borderRadius: BorderRadius.circular(Aura.radiusSm),
                ),
                child: const Icon(Icons.grain, size: 14, color: Aura.onPrimary),
              ),
              const SizedBox(width: 10),
              Text('Stilora',
                  style: Aura.headlineSm.copyWith(
                      fontWeight: FontWeight.w500, fontSize: 17)),
            ]),
          ),
          const SizedBox(width: Aura.spaceLg),
          // Nav tabs with animated pill indicator
          const _TopTabs(),
          const Spacer(),
          // Search
          if (onSearch != null)
            _AnimatedSearchField(onTap: onSearch!),
          const SizedBox(width: Aura.spaceSm),
          // Utilities
          _HoverIconButton(icon: Icons.call, tooltip: 'Audio Call', onTap: () {}),
          _HoverIconButton(
              icon: Icons.notifications_off, tooltip: 'Notifications', onTap: () {}),
          _HoverIconButton(
            icon: Icons.tune,
            tooltip: 'Settings',
            active: true,
            onTap: onToggleSettings ?? () {},
          ),
          const SizedBox(width: Aura.spaceSm),
          Container(width: 1, height: 24, color: scheme.surfaceContainerHighest),
          const SizedBox(width: Aura.spaceSm),
          AuraAvatar(
            initials: workspace?.initials ?? 'YO',
            size: 28,
            presence: 0,
          ),
        ]),
      ),
    );
  }
}

class _TopTabs extends StatefulWidget {
  const _TopTabs();

  @override
  State<_TopTabs> createState() => _TopTabsState();
}

class _TopTabsState extends State<_TopTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    const labels = ['Threads', 'Catch-up'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.surfaceContainerHighest)),
      ),
      child: Row(children: [
        const SizedBox(width: Aura.spaceMd),
        for (var i = 0; i < labels.length; i++) ...[
          InkWell(
            onTap: () => setState(() => _index = i),
            borderRadius: BorderRadius.circular(Aura.radiusLg),
            child: AnimatedContainer(
              duration: Aura.durationNormal,
              curve: Aura.easingStandard,
              padding: const EdgeInsets.symmetric(
                  horizontal: Aura.spaceMd, vertical: 6),
              decoration: BoxDecoration(
                color: _index == i ? scheme.surfaceContainerLow : Colors.transparent,
                borderRadius: BorderRadius.circular(Aura.radiusLg),
              ),
              child: AnimatedDefaultTextStyle(
                duration: Aura.durationNormal,
                style: Aura.labelMd.copyWith(
                  color: _index == i ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: _index == i ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(labels[i]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _AnimatedSearchField extends StatelessWidget {
  const _AnimatedSearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraHoverable(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Aura.spaceSm, vertical: 7),
      child: SizedBox(
        width: 224,
        child: Row(children: [
          Icon(Icons.search, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Search or run a command…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Aura.bodySm.copyWith(color: scheme.outline)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('⌘K',
                style: Aura.labelSm
                    .copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),
          ),
        ]),
      ),
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final lit = _hover || widget.active;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hover = h),
        borderRadius: BorderRadius.circular(Aura.radiusLg),
        child: AnimatedContainer(
          duration: Aura.durationFast,
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: lit ? scheme.surfaceContainerLow : Colors.transparent,
            borderRadius: BorderRadius.circular(Aura.radiusLg),
          ),
          child: Icon(widget.icon,
              size: 18,
              color: widget.active ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// ── Left navigation pane (desktop) ──────────────────────────────
class AuraSideNav extends ConsumerWidget {
  const AuraSideNav({
    super.key,
    required this.activeChannelId,
    required this.onChannelSelected,
    required this.onDmSelected,
    required this.onNewThread,
    required this.onOpenVoice,
    required this.onOpenSettings,
    this.onOpenActivity,
  });

  final String? activeChannelId;
  final ValueChanged<Channel> onChannelSelected;
  final ValueChanged<DmConversation> onDmSelected;
  final VoidCallback onNewThread;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final workspace =
        ref.watch(workspaceProvider).valueOrNull ?? MockData.workspace;
    final channels = ref.watch(channelsProvider);
    final dms = ref.watch(conversationsProvider);
    final voice = ref.watch(voiceRoomProvider);

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: 256,
        child: Column(children: [
          // Workspace switcher
          Padding(
            padding: const EdgeInsets.all(Aura.spaceXs),
            child: AuraHoverable(
              onTap: () {},
              padding: const EdgeInsets.all(Aura.spaceSm),
              child: Row(children: [
                AuraAvatar(initials: workspace.initials, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workspace.name,
                          style: Aura.labelMd
                              .copyWith(fontWeight: FontWeight.w600)),
                      Row(children: [
                        const PresenceDot(0, size: 6),
                        const SizedBox(width: 5),
                        Text('${workspace.onlineCount} online',
                            style: Aura.bodySm
                                .copyWith(color: scheme.onSurfaceVariant)),
                      ]),
                    ],
                  ),
                ),
                Icon(Icons.unfold_more, size: 16, color: scheme.outline),
              ]),
            ),
          ),
          const SizedBox(height: Aura.spaceXs),
          // New thread CTA (animated press)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Aura.spaceXs),
            child: AuraPressable(
              onTap: onNewThread,
              child: AnimatedContainer(
                duration: Aura.durationFast,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Aura.primary,
                  borderRadius: BorderRadius.circular(Aura.radiusLg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 16, color: Aura.onPrimary),
                    const SizedBox(width: 6),
                    Text('New Thread',
                        style: Aura.labelMd.copyWith(color: Aura.onPrimary)),
                  ],
                ),
              ),
            ),
          ),
          // Sections
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: Aura.spaceSm),
              child: AuraEntrance.staggered(
                step: const Duration(milliseconds: 35),
                children: [
                  SectionLabel('Workspace'),
                  _NavRow(
                      icon: Icons.forum, label: 'Threads', onTap: () {}),
                  _NavRow(
                    icon: Icons.drafts,
                    label: 'Catch-up',
                    trailing: const UnreadDot(),
                    onTap: onOpenActivity ?? () {},
                  ),
                  SectionLabel('Channels',
                      trailing: InkWell(
                          onTap: () {},
                          child: Icon(Icons.add, size: 15,
                              color: scheme.outline))),
                  channels.when(
                    data: (list) => Column(children: [
                      for (final c in list)
                        _ChannelRow(
                          channel: c,
                          active: c.id == activeChannelId,
                          onTap: () => onChannelSelected(c),
                        ),
                    ]),
                    loading: () => const _NavSkeleton(count: 4),
                    error: (_, __) => _NavError(onRetry: () =>
                        ref.invalidate(channelsProvider)),
                  ),
                  SectionLabel('Direct',
                      trailing: InkWell(
                          onTap: () {},
                          child: Icon(Icons.add, size: 15,
                              color: scheme.outline))),
                  dms.when(
                    data: (list) => AuraEntrance.staggered(
                      step: const Duration(milliseconds: 30),
                      children: [
                        for (final dm in list) _DmRow(dm: dm, onTap: () => onDmSelected(dm)),
                      ],
                    ),
                    loading: () => const _NavSkeleton(count: 2),
                    error: (_, __) => _NavError(onRetry: () =>
                        ref.invalidate(conversationsProvider)),
                  ),
                ],
              ),
            ),
          ),
          // Voice status + settings drawer
          Container(
            padding: const EdgeInsets.all(Aura.spaceXs),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.surfaceContainerHighest)),
            ),
            child: Column(children: [
              AuraPressable(
                onTap: onOpenVoice,
                child: AnimatedContainer(
                  duration: Aura.durationNormal,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(Aura.radiusLg),
                  ),
                  child: Row(children: [
                    const AuraPulseDot(color: Aura.secondary, size: 7),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Audio Space Active',
                              style: Aura.bodySm
                                  .copyWith(fontWeight: FontWeight.w600)),
                          Text(voice.stateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Aura.labelSm
                                  .copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    AuraAudioBars(
                        color: scheme.primary,
                        active: true,
                        height: 12,
                        barCount: 3),
                  ]),
                ),
              ),
              _NavRow(
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: onOpenSettings),
            ]),
          ),
        ]),
      ),
    );
  }
}


class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      onTap: widget.onTap,
      onHover: (h) => setState(() => _hover = h),
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceSm, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: Aura.spaceXs),
        decoration: BoxDecoration(
          color: _hover ? scheme.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          Icon(widget.icon, size: 16, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.label,
                style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant)),
          ),
          if (widget.trailing != null) widget.trailing!,
        ]),
      ),
    );
  }
}

class _ChannelRow extends StatefulWidget {
  const _ChannelRow(
      {required this.channel, required this.active, required this.onTap});

  final Channel channel;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final c = widget.channel;
    final lit = _hover || widget.active;

    return InkWell(
      onTap: widget.onTap,
      onHover: (h) => setState(() => _hover = h),
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        curve: Aura.easingStandard,
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceSm, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: Aura.spaceXs, vertical: 1),
        decoration: BoxDecoration(
          color: widget.active
              ? scheme.surfaceContainerHighest
              : lit
                  ? scheme.surfaceContainer
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          Text('#',
              style: Aura.bodySm.copyWith(
                  color: widget.active ? scheme.primary : scheme.outline,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(c.name,
                overflow: TextOverflow.ellipsis,
                style: Aura.bodySm.copyWith(
                  color: widget.active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                )),
          ),
          if (c.unreadCount > 0) ...[
            AuraPop(
              child: AuraChip('${c.unreadCount} unread', active: true),
            ),
          ] else if (c.lastActivityLabel.isNotEmpty)
            Text(c.lastActivityLabel,
                style: Aura.bodySm.copyWith(color: scheme.outline)),
        ]),
      ),
    );
  }
}

class _DmRow extends StatefulWidget {
  const _DmRow({required this.dm, required this.onTap});
  final DmConversation dm;
  final VoidCallback onTap;

  @override
  State<_DmRow> createState() => _DmRowState();
}

class _DmRowState extends State<_DmRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final dm = widget.dm;
    return InkWell(
      onTap: widget.onTap,
      onHover: (h) => setState(() => _hover = h),
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceSm, vertical: 7),
        margin: const EdgeInsets.symmetric(horizontal: Aura.spaceXs, vertical: 1),
        decoration: BoxDecoration(
          color: _hover ? scheme.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          AuraAvatar(
              initials: dm.peer.initials,
              imageUrl: dm.peer.avatarUrl,
              size: 22,
              presence: dm.peer.presence.index),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dm.peer.name,
                    overflow: TextOverflow.ellipsis,
                    style: Aura.bodySm
                        .copyWith(fontWeight: FontWeight.w500)),
                Text(dm.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Aura.bodySm
                        .copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Column(children: [
            Text(dm.timeLabel,
                style: Aura.labelSm.copyWith(color: scheme.outline)),
            if (dm.unread)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: UnreadDot(),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _NavSkeleton extends StatelessWidget {
  const _NavSkeleton({this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < count; i++) ...[
              const SizedBox(height: 10),
              SkeletonBlock(width: 140 - (i % 2) * 40, height: 12),
            ],
          ],
        ),
      );
}

class _NavError extends StatelessWidget {
  const _NavError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Aura.spaceSm),
      child: Row(children: [
        Icon(Icons.cloud_off, size: 14, color: scheme.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Couldn’t load',
              style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant)),
        ),
        InkWell(
            onTap: onRetry,
            child: Text('Retry',
                style: Aura.labelSm.copyWith(color: scheme.primary))),
      ]),
    );
  }
}

/// ── Bottom navigation (mobile) ──────────────────────────────────
class AuraBottomNav extends StatelessWidget {
  const AuraBottomNav({
    super.key,
    required this.index,
    required this.onChanged,
    this.unreadBadge = 0,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final int unreadBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final items = [
      (Icons.chat_bubble_outline, 'Threads'),
      (Icons.space_dashboard_outlined, 'Channels'),
      (Icons.graphic_eq, 'Voice'),
      (Icons.settings_outlined, 'Settings'),
    ];

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.surfaceContainerHighest)),
          ),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: Aura.durationNormal,
                    curve: Aura.easingStandard,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: i == index
                          ? Aura.primaryFixed.withValues(alpha: 0.55)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Aura.radiusLg),
                    ),
                    child: Column(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        AnimatedSwitcher(
                          duration: Aura.durationFast,
                          transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim, child: FadeTransition(
                                  opacity: anim, child: child)),
                          child: Icon(items[i].$1,
                              key: ValueKey(i == index),
                              size: 20,
                              color: i == index
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                        ),
                        if (i == 1 && unreadBadge > 0)
                          Positioned(
                            right: -6, top: -3,
                            child: AuraPop(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Aura.primary,
                                  borderRadius:
                                      BorderRadius.circular(Aura.radiusFull),
                                ),
                                child: Text('$unreadBadge',
                                    style: Aura.labelSm.copyWith(
                                        color: Aura.onPrimary,
                                        fontSize: 9)),
                              ),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: Aura.durationFast,
                        style: Aura.labelSm.copyWith(
                          color: i == index
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: i == index
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        child: Text(items[i].$2),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// ── Floating voice capsule (above the thread) ───────────────────
class VoiceCapsule extends ConsumerWidget {
  const VoiceCapsule({
    super.key,
    required this.onOpenStage,
    this.heroTag = 'voice-capsule',
  });

  final VoidCallback onOpenStage;
  final String heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final room = ref.watch(voiceRoomProvider);
    final members = room.participants.take(3).toList();

    return AuraEntrance(
      offset: const Offset(0, -0.15),
      duration: Aura.durationSlow,
      child: AuraPressable(
        onTap: onOpenStage,
        child: Hero(
          tag: heroTag,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Aura.radiusFull),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Aura.spaceMd, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const AuraPulseDot(color: Aura.secondary, size: 7),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(room.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Aura.bodySm
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1, height: 14, color: scheme.outlineVariant,
                ),
                const SizedBox(width: 10),
                // Participant pills — sized to content, never overlapping
                for (var i = 0; i < members.length; i++)
                  _ParticipantPill(
                      user: members[i], speaking: room.speakingIds
                          .contains(members[i].id)),
                const SizedBox(width: 6),
                Text('${room.participants.length} people',
                    style: Aura.labelSm
                        .copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: Aura.spaceSm),
                Container(
                    width: 1, height: 14, color: scheme.outlineVariant),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: room.muted ? 'Unmute' : 'Mute',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => ref.read(voiceRoomProvider.notifier)
                      .update((r) => r.copyWith(muted: !r.muted)),
                  icon: AnimatedSwitcher(
                    duration: Aura.durationFast,
                    transitionBuilder: (c, a) =>
                        RotationTransition(turns: a, child: c),
                    child: Icon(
                      room.muted ? Icons.mic_off : Icons.mic,
                      key: ValueKey(room.muted),
                      size: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Disconnect voice',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () {},
                  icon: const Icon(Icons.call_end,
                      size: 16, color: Aura.error),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantPill extends StatefulWidget {
  const _ParticipantPill({required this.user, required this.speaking});
  final UserProfile user;
  final bool speaking;

  @override
  State<_ParticipantPill> createState() => _ParticipantPillState();
}

class _ParticipantPillState extends State<_ParticipantPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final u = widget.user;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: widget.speaking
              ? Aura.primaryFixed
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Aura.radiusFull),
          border: widget.speaking
              ? Border.all(color: Aura.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          u.name == 'You' ? 'You' : u.initials,
          style: Aura.labelSm.copyWith(
            color: widget.speaking
                ? Aura.onPrimaryFixed
                : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// ── Command palette (⌘K) ────────────────────────────────────────
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.onClose});

  final VoidCallback onClose;

  static bool isOpen = false;

  static void show(BuildContext context) {
    isOpen = true;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
        alignment: const Alignment(0, -0.85),
        elevation: 0,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.only(top: 96),
        child: CommandPalette(
          onClose: () {
            isOpen = false;
            Navigator.of(ctx).maybePop();
          },
        ),
      ),
    ).whenComplete(() => isOpen = false);
  }

  static void hide(BuildContext context) {
    isOpen = false;
    Navigator.of(context).maybePop();
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<(String, String, String)> get _results {
    final all = PaletteData.results;
    if (_query.trim().isEmpty) return all.take(5).toList();
    final q = _query.toLowerCase();
    return all
        .where((e) =>
            e.$2.toLowerCase().contains(q) || e.$3.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final results = _results;

    return Container(
      width: 560,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Aura.radiusXl),
        boxShadow: Aura.haloDialog,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: AuraEntrance(
        offset: const Offset(0, -0.03),
        duration: Aura.durationNormal,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Input row
          Padding(
            padding: const EdgeInsets.all(Aura.spaceMd),
            child: Row(children: [
              Icon(Icons.search, color: scheme.outline, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        setState(() => _selected =
                            (_selected + 1).clamp(0, results.length - 1));
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() => _selected =
                      (_selected - 1).clamp(0, results.isEmpty ? 0 : results.length - 1));
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        widget.onClose();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: Aura.bodyMd.copyWith(color: scheme.onSurface),
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: 'Search messages, channels, people…',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _query = v;
                      _selected = 0;
                    }),
                    onSubmitted: (_) {
                      if (results.isNotEmpty) widget.onClose();
                    },
                  ),
                ),
              ),
              _Keycap('ESC'),
            ]),
          ),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          // Results
          Flexible(
            child: AnimatedSize(
              duration: Aura.durationNormal,
              curve: Aura.easingStandard,
              alignment: Alignment.topCenter,
              child: results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Aura.spaceLg),
                      child: Text('No results for “$_query”',
                          style: Aura.bodyMd
                              .copyWith(color: scheme.onSurfaceVariant)),
                    )
                  : AuraEntrance.staggered(
                      step: const Duration(milliseconds: 28),
                      children: [
                        for (var i = 0; i < results.length; i++)
                          _ResultRow(
                            kind: results[i].$1,
                            title: results[i].$2,
                            subtitle: results[i].$3,
                            selected: i == _selected,
                            onTap: widget.onClose,
                          ),
                      ],
                    ),
            ),
          ),
          // Footer hints
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Aura.spaceMd, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(Aura.radiusXl)),
            ),
            child: Row(children: [
              _Keycap('↑'), const SizedBox(width: 4), _Keycap('↓'),
              const SizedBox(width: 6),
              Text('navigate', style: Aura.labelSm
                  .copyWith(color: scheme.outline)),
              const SizedBox(width: Aura.spaceMd),
              _Keycap('↵'), const SizedBox(width: 6),
              Text('open', style: Aura.labelSm
                  .copyWith(color: scheme.outline)),
              const Spacer(),
              Text('⌘K', style: Aura.labelSm
                  .copyWith(color: scheme.outline)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Keycap extends StatelessWidget {
  const _Keycap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: Aura.labelSm
              .copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String kind;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final lit = _hover || widget.selected;
    final icon = switch (widget.kind) {
      'channel' => Icons.tag,
      'person' => Icons.person_outline,
      _ => Icons.chat_bubble_outline,
    };

    return InkWell(
      onTap: widget.onTap,
      onHover: (h) => setState(() => _hover = h),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceMd, vertical: 10),
        color: lit ? scheme.surfaceContainerLow : Colors.transparent,
        child: Row(children: [
          Icon(icon, size: 16, color: scheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Aura.labelMd.copyWith(color: scheme.onSurface)),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Aura.bodySm
                        .copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          AnimatedOpacity(
            opacity: lit ? 1 : 0,
            duration: Aura.durationFast,
            child: Icon(Icons.arrow_forward_ios,
                size: 12, color: scheme.outline),
          ),
        ]),
      ),
    );
  }
}

abstract final class PaletteData {
  static const results = <(String, String, String)>[
    ('message', 'design-sync', 'I’ve uploaded the revised spatial system…'),
    ('message', 'product', 'Launch checklist for v1.0 — stores, policy…'),
    ('channel', 'design-sync', 'Iterating on spatial hierarchy'),
    ('channel', 'eng-architecture', 'Systems, APIs, and structural decisions'),
    ('person', 'Sarah Chen', 'Owner • online'),
    ('person', 'Marcus Vance', 'Member • idle'),
  ];
}
