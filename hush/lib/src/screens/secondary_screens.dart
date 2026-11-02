import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/messages.dart';
import '../widgets/navigation.dart';
import '../widgets/primitives.dart';

/// ── Thread view ("N replies") ───────────────────────────────────
class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.root});

  final Message root;

  static void push(BuildContext context, Message root) =>
      Navigator.of(context).push(AuraPage<void>(child: ThreadScreen(root: root)).createRoute(context));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final replies = ref.watch(threadProvider(root.id));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thread', style: Aura.headlineSm.copyWith(fontSize: 17)),
            Text('#design-sync',
                style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        centerTitle: false,
      ),
      body: Column(children: [
        // Root message pinned at top
        Container(
          padding: const EdgeInsets.all(Aura.spaceMd),
          color: scheme.surfaceContainerLow,
          child: MessageRow(message: root),
        ),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Aura.spaceSm),
          child: Text('${root.replyCount > 0 ? root.replyCount : replies.valueOrNull?.length ?? 0} replies',
              style: Aura.labelSm.copyWith(color: scheme.outline)),
        ),
        Expanded(
          child: replies.when(
            loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => ErrorState(
                message: 'Couldn’t load replies.',
                onRetry: () =>
                    ref.invalidate(threadProvider(root.id))),
            data: (list) => ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: Aura.gutterMobile, vertical: Aura.spaceSm),
              itemCount: list.length,
              itemBuilder: (context, i) => AuraRevealOnScroll(
                index: i,
                child: MessageRow(message: list[i]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Aura.spaceSm),
          child: MessageComposer(
            hint: 'Reply in thread…',
            onSend: (_) {},
          ),
        ),
      ]),
    );
  }
}

/// ── Voice / video stage (mobile-first, desktop full-screen) ─────
class VoiceStageScreen extends ConsumerStatefulWidget {
  const VoiceStageScreen({super.key});

  static void push(BuildContext context) =>
      Navigator.of(context).push(AuraPage<void>(child: const VoiceStageScreen()).createRoute(context));

  @override
  ConsumerState<VoiceStageScreen> createState() =>
      _VoiceStageScreenState();
}

class _VoiceStageScreenState extends ConsumerState<VoiceStageScreen> {
  /// null = not yet requested, true = granted, false = denied.
  bool? _micGranted;
  bool _connecting = true;
  bool _sharing = true;
  int _seconds = 0;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // On desktop, permission_handler has no mic API — treat as granted.
    try {
      final mic = await Permission.microphone.request();
      await Permission.camera.request();
      if (!mounted) return;
      setState(() => _micGranted = mic.isGranted);
    } catch (_) {
      if (!mounted) return;
      setState(() => _micGranted = true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _connecting = false);
    _callTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final room = ref.watch(voiceRoomProvider);

    // Permission denied state (DESIGN.md state matrix).
    if (_micGranted == false) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Aura.spaceXl),
            child: PermissionDeniedCard(
              reason:
                  'Hush needs your microphone to speak in Voice: Design Room. '
                  'Voice stays off until you allow access.',
              icon: Icons.mic_none,
              openSettings: () => openAppSettings(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Aura.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Aura.spaceMd),
          child: Column(children: [
            // Header
            AuraEntrance.staggered(
              step: const Duration(milliseconds: 50),
              children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.keyboard_arrow_down)),
                  Expanded(
                    child: Column(children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(room.roomName,
                                overflow: TextOverflow.ellipsis,
                                style: Aura.headlineSm.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.lock_outline,
                              size: 14, color: Aura.outline),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: Aura.durationNormal,
                        child: Text(
                          _connecting
                              ? 'Connecting…'
                              : '$_timeLabel • ${room.participants.length} participants',
                          key: ValueKey(_connecting),
                          style: Aura.bodySm
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ]),
                  ),
                  IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.tune)),
                ]),
              ],
            ),
            const SizedBox(height: Aura.spaceMd),
            // Shared canvas card
            AuraEntrance(
              delay: const Duration(milliseconds: 120),
              duration: Aura.durationSlow,
              child: AuraCard(
                padding: const EdgeInsets.all(Aura.spaceMd),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.upload_file,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Wireframe V2.3',
                        style: Aura.labelMd
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    AuraChip('Shared by Sarah', active: true),
                    const Spacer(),
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {},
                        icon: const Icon(Icons.open_in_full, size: 16)),
                  ]),
                  const SizedBox(height: Aura.spaceMd),
                  // Animated canvas placeholder
                  _AnimatedCanvas(),
                  const SizedBox(height: Aura.spaceSm),
                  Row(children: [
                    Text('Canvas zoom: 100%',
                        style: Aura.bodySm
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    Text('Design Specs Synced',
                        style: Aura.bodySm
                            .copyWith(color: scheme.primary)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: Aura.spaceMd),
            // Participant tiles
            Expanded(
              child: _connecting
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : AuraEntrance.staggered(
                      axis: Axis.horizontal,
                      step: const Duration(milliseconds: 70),
                      children: [
                        for (final p in room.participants)
                          _ParticipantTile(
                            user: p,
                            speaking: room.speakingIds.contains(p.id),
                            muted:
                                p.id == 'u_you' ? room.muted : p.presence ==
                                    UserPresence.idle,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Aura.spaceMd),
            // Controls bar
            AuraEntrance(
              offset: const Offset(0, 0.2),
              duration: Aura.durationSlow,
              child: _ControlsBar(
                muted: room.muted,
                cameraOn: room.cameraOn,
                sharing: _sharing,
                micGranted: _micGranted ?? true,
                onToggleMute: () {
                  if (_micGranted == false) return;
                  ref.read(voiceRoomProvider.notifier)
                      .update((r) => r.copyWith(muted: !r.muted));
                },
                onToggleCamera: () {
                  ref.read(voiceRoomProvider.notifier)
                      .update((r) => r.copyWith(cameraOn: !r.cameraOn));
                },
                onToggleShare: () => setState(() => _sharing = !_sharing),
                onLeave: () {
                  ref.read(voiceRoomProvider.notifier).update((r) =>
                      r.copyWith(connected: false, stateLabel: 'Left'));
                  Navigator.of(context).maybePop();
                },
                onRetryMic: _requestPermissions,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatefulWidget {
  const _ParticipantTile({
    required this.user,
    required this.speaking,
    required this.muted,
  });

  final UserProfile user;
  final bool speaking;
  final bool muted;

  @override
  State<_ParticipantTile> createState() => _ParticipantTileState();
}

class _ParticipantTileState extends State<_ParticipantTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final u = widget.user;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: Aura.durationNormal,
          curve: Aura.easingStandard,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          width: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Aura.radiusXl),
            border: Border.all(
              color: widget.speaking
                  ? Aura.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: widget.speaking ? 2 : 1,
            ),
            boxShadow: widget.speaking
                ? [
                    BoxShadow(
                      color: Aura.primary.withValues(alpha: 0.18),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(fit: StackFit.expand, children: [
              // "Video" surface
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surfaceContainerHigh,
                      scheme.surfaceContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: AuraAvatar(
                    initials: u.initials,
                    imageUrl: u.avatarUrl,
                    size: 56,
                  ),
                ),
              ),
              // Speaking rings (animated)
              if (widget.speaking)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Aura.radiusXl),
                      border: Border.all(
                        color: Aura.primary.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              // Name + mic chips
              Positioned(
                left: 8, bottom: 8,
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius:
                          BorderRadius.circular(Aura.radiusFull),
                    ),
                    child: Row(children: [
                      if (widget.speaking) ...[
                        const AuraPulseDot(
                            color: Aura.primary, size: 5, ring: false),
                        const SizedBox(width: 5),
                      ],
                      Text(u.name == 'You' ? 'You' : u.name.split(' ').first,
                          style: Aura.labelSm
                              .copyWith(color: Colors.white)),
                    ]),
                  ),
                ]),
              ),
              Positioned(
                right: 8, bottom: 8,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.muted ? Icons.mic_off : Icons.mic,
                    size: 13,
                    color: widget.muted ? Aura.error : Colors.white,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.muted,
    required this.cameraOn,
    required this.sharing,
    required this.micGranted,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onLeave,
    required this.onRetryMic,
  });

  final bool muted;
  final bool cameraOn;
  final bool sharing;
  final bool micGranted;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final VoidCallback onLeave;
  final VoidCallback onRetryMic;

  @override
  Widget build(BuildContext context) {
    return AuraPressable(
      onTap: null,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceMd, vertical: Aura.spaceSm),
        decoration: BoxDecoration(
          color: Aura.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Aura.radiusFull),
          border: Border.all(color: Aura.outlineVariant),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _CircleControl(
            icon: muted ? Icons.mic_off : Icons.mic,
            active: !muted,
            warning: !micGranted,
            tooltip: !micGranted
                ? 'Microphone blocked'
                : muted
                    ? 'Unmute'
                    : 'Mute',
            onTap: !micGranted ? onRetryMic : onToggleMute,
          ),
          _CircleControl(
            icon: Icons.videocam,
            active: cameraOn,
            tooltip: cameraOn ? 'Camera off' : 'Camera on',
            onTap: onToggleCamera,
          ),
          _CircleControl(
            icon: Icons.volume_up,
            active: true,
            tooltip: 'Speaker',
            onTap: () {},
          ),
          _CircleControl(
            icon: Icons.screen_share,
            active: sharing,
            tooltip: sharing ? 'Stop sharing' : 'Share screen',
            onTap: onToggleShare,
          ),
          // Leave (tertiary/red pill)
          AuraPressable(
            onTap: onLeave,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Aura.spaceMd, vertical: 10),
              decoration: BoxDecoration(
                color: Aura.errorContainer,
                borderRadius: BorderRadius.circular(Aura.radiusFull),
              ),
              child: const Row(children: [
                Icon(Icons.call_end, size: 15, color: Aura.error),
                SizedBox(width: 6),
                Text('Leave',
                    style: TextStyle(
                        color: Aura.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CircleControl extends StatefulWidget {
  const _CircleControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.warning = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool warning;

  @override
  State<_CircleControl> createState() => _CircleControlState();
}

class _CircleControlState extends State<_CircleControl> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: Listener(
          onPointerDown: (_) => setState(() => _down = true),
          onPointerUp: (_) => setState(() => _down = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Aura.durationFast,
              curve: Aura.easingEmphasized,
              width: 46, height: 46,
              transform: Matrix4.diagonal3Values(
                  _down ? 0.92 : 1, _down ? 0.92 : 1, 1),
              decoration: BoxDecoration(
                color: widget.warning
                    ? Aura.errorContainer
                    : widget.active
                        ? Aura.primaryFixed
                        : Aura.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                size: 20,
                color: widget.warning
                    ? Aura.error
                    : widget.active
                        ? Aura.primary
                        : Aura.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
}

/// Animated shared-canvas placeholder (wireframe blocks breathing gently).
class _AnimatedCanvas extends StatefulWidget {
  @override
  State<_AnimatedCanvas> createState() => _AnimatedCanvasState();
}

class _AnimatedCanvasState extends State<_AnimatedCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final breathe = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Aura.easingStandard));

    return AnimatedBuilder(
      animation: breathe,
      builder: (context, _) => Container(
        height: 180,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            style: BorderStyle.solid,
          ),
        ),
        padding: const EdgeInsets.all(Aura.spaceMd),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Column(children: [
              _block(breathe.value * 0.7, 14, scheme.surfaceContainerHighest),
              const SizedBox(height: 8),
              _block(breathe.value * 0.9, 10, scheme.surfaceContainerHigh),
              Expanded(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: breathe.value,
                    duration: Aura.durationSlow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Aura.spaceMd, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: scheme.outlineVariant,
                            style: BorderStyle.solid),
                        borderRadius:
                            BorderRadius.circular(Aura.radiusSm),
                      ),
                      child: Text('Component Stage Canvas',
                          style: Aura.labelSm
                              .copyWith(color: scheme.outline)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _block(0.5, 10, scheme.surfaceContainerHigh),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: Column(children: [
              _block(0.8, 10, scheme.surfaceContainerHigh),
              const SizedBox(height: 6),
              _block(0.6, 10, scheme.surfaceContainerHigh),
              const SizedBox(height: 6),
              _block(0.7, 10, scheme.surfaceContainerHigh),
              const Spacer(),
              _block(1, 28, Aura.primaryFixed),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _block(double w, double h, Color color) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: w.clamp(0.1, 1.0),
        child: Container(
            height: h,
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4))),
      );
}

/// ── Search results (full screen — mobile & fallback) ────────────
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static void push(BuildContext context) =>
      Navigator.of(context).push(AuraPage<void>(child: const SearchScreen()).createRoute(context));

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final results = ref.watch(searchResultsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: Aura.bodyMd,
          decoration: const InputDecoration(
            hintText: 'Search messages, channels, people…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? EmptyState(
              icon: Icons.search,
              message: 'Search across every channel you’re in.\n'
                  'Try “tokens”, “launch”, or a person’s name.',
              actionLabel: null,
              onAction: null,
            )
          : results.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => ErrorState(
                  message: 'Search failed.',
                  onRetry: () =>
                      ref.invalidate(searchResultsProvider(_query))),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      message: 'No results for “$_query”.')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final r = list[i];
                        final icon = switch (r.$1) {
                          'channel' => Icons.tag,
                          'person' => Icons.person_outline,
                          _ => Icons.chat_bubble_outline,
                        };
                        return AuraRevealOnScroll(
                          index: i,
                          child: ListTile(
                            leading: Icon(icon, color: scheme.outline),
                            title: Text(r.$2,
                                style: Aura.labelMd),
                            subtitle: Text(r.$3,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Aura.bodySm.copyWith(
                                    color: scheme.onSurfaceVariant)),
                            onTap: () {},
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// ── Notifications / activity feed ───────────────────────────────
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  static void push(BuildContext context) =>
      Navigator.of(context).push(AuraPage<void>(child: const ActivityScreen()).createRoute(context));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final activity = ref.watch(activityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: Aura.headlineSm.copyWith(fontSize: 18)),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(workspaceRepositoryProvider).markActivityRead();
              ref.invalidate(activityProvider);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: activity.when(
        loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => ErrorState(
            message: 'Couldn’t load notifications.',
            onRetry: () => ref.invalidate(activityProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(activityProvider),
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none,
                  message: 'All quiet. Nothing needs you right now.')
              : AuraEntrance.staggered(
                  step: const Duration(milliseconds: 45),
                  children: [
                    for (final a in list)
                      ListTile(
                        leading: _ActivityIcon(kind: a.kind, unread: a.unread),
                        title: RichText(
                          text: TextSpan(
                            style: Aura.bodyMd
                                .copyWith(color: scheme.onSurface),
                            children: [
                              TextSpan(
                                  text: a.actorName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              TextSpan(text: ' ${a.summary}'),
                            ],
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (a.channelName != null) '#${a.channelName}',
                            a.timeLabel,
                          ].join(' • '),
                          style: Aura.labelSm
                              .copyWith(color: scheme.outline),
                        ),
                        trailing: a.unread ? const UnreadDot() : null,
                        onTap: () {},
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  const _ActivityIcon({required this.kind, required this.unread});
  final ActivityKind kind;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      ActivityKind.mention => Icons.alternate_email,
      ActivityKind.reply => Icons.reply,
      ActivityKind.reaction => Icons.emoji_emotions_outlined,
      ActivityKind.invite => Icons.person_add_alt,
      ActivityKind.voice => Icons.graphic_eq,
    };
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: unread ? Aura.primaryFixed : Aura.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Aura.radiusLg),
      ),
      child: Icon(icon,
          size: 18, color: unread ? Aura.primary : Aura.outline),
    );
  }
}

/// ── Members sheet ───────────────────────────────────────────────
class MembersSheet extends ConsumerWidget {
  const MembersSheet({super.key});

  static void show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const MembersSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final members = ref.watch(membersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(Aura.radiusXl)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(Aura.spaceMd),
            child: Row(children: [
              Text('Members',
                  style: Aura.headlineSm.copyWith(fontSize: 17)),
              const SizedBox(width: Aura.spaceSm),
              members.when(
                data: (l) => AuraChip('${l.length}'),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: members.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => ErrorState(
                  message: 'Couldn’t load members.',
                  onRetry: () => ref.invalidate(membersProvider)),
              data: (list) => AuraEntrance.staggered(
                step: const Duration(milliseconds: 40),
                children: [
                  for (final u in list)
                    ListTile(
                      leading: AuraAvatar(
                        initials: u.initials,
                        imageUrl: u.avatarUrl,
                        size: 36,
                        presence: u.presence.index,
                      ),
                      title: Text(u.name, style: Aura.labelMd),
                      subtitle: Text(
                        [u.roleLabel, u.handle].where((s) => s.isNotEmpty).join(' • '),
                        style: Aura.bodySm
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                      onTap: () {
                        Navigator.of(context).maybePop();
                        ProfileScreen.push(context, u);
                      },
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// ── User profile ────────────────────────────────────────────────
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.user});

  final UserProfile user;

  static void push(BuildContext context, UserProfile user) =>
      Navigator.of(context).push(AuraPage<void>(child: ProfileScreen(user: user)).createRoute(context));

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Scaffold(
      appBar: AppBar(centerTitle: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AuraEntrance.staggered(
            step: const Duration(milliseconds: 60),
            children: [
              const SizedBox(height: Aura.spaceLg),
              Center(
                child: AuraAvatar(
                  initials: user.initials,
                  imageUrl: user.avatarUrl,
                  size: 88,
                  presence: user.presence.index,
                ),
              ),
              const SizedBox(height: Aura.spaceMd),
              Center(
                child: Text(user.name,
                    style: Aura.headlineLg
                        .copyWith(fontWeight: FontWeight.w500)),
              ),
              Center(
                child: Text('@${user.handle}',
                    style: Aura.bodyMd
                        .copyWith(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(height: Aura.spaceLg),
              AuraCard(
                child: Column(children: [
                  _ProfileRow(label: 'Role', value: user.roleLabel.isEmpty ? 'Member' : user.roleLabel),
                  Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  _ProfileRow(
                      label: 'Status',
                      value: switch (user.presence) {
                        UserPresence.online => 'Online',
                        UserPresence.idle => 'Idle',
                        UserPresence.offline => 'Offline',
                      }),
                  Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  _ProfileRow(label: 'Workspace', value: 'Studio Flow'),
                ]),
              ),
              const SizedBox(height: Aura.spaceLg),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                  ),
                ),
                const SizedBox(width: Aura.spaceSm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    style: FilledButton.styleFrom(backgroundColor: Aura.primary),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add to channel'),
                  ),
                ),
              ]),
              const SizedBox(height: Aura.spaceXl),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Aura.spaceSm),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: Aura.labelSm.copyWith(color: Aura.outline)),
          const Spacer(),
          Text(value, style: Aura.labelMd),
        ]),
      );
}

/// ── New thread / create channel sheet ───────────────────────────
class NewThreadSheet extends ConsumerStatefulWidget {
  const NewThreadSheet({super.key});

  static void show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const NewThreadSheet(),
      );

  @override
  ConsumerState<NewThreadSheet> createState() => _NewThreadSheetState();
}

class _NewThreadSheetState extends ConsumerState<NewThreadSheet> {
  int _tab = 0; // 0 = channel, 1 = thread, 2 = DM
  final _name = TextEditingController();
  final _topic = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_tab == 0 && _name.text.trim().isEmpty) return;
    setState(() => _creating = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (_tab) {
        0 => 'Channel #${_name.text.trim()} created',
        1 => 'Thread started',
        _ => 'Conversation started',
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Aura.radiusXl)),
        ),
        padding: EdgeInsets.fromLTRB(Aura.spaceLg, Aura.spaceSm,
            Aura.spaceLg, MediaQuery.viewInsetsOf(context).bottom > 0
                ? Aura.spaceLg
                : Aura.spaceXl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: Aura.spaceMd),
          AuraAnimatedSelector<int>(
            options: const [0, 1, 2],
            value: _tab,
            labelOf: (t) =>
                ['New channel', 'New thread', 'New DM'][t],
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: Aura.spaceLg),
          AnimatedSize(
            duration: Aura.durationNormal,
            curve: Aura.easingStandard,
            alignment: Alignment.topCenter,
            child: _tab == 0
                ? Column(children: [
                    TextField(
                      controller: _name,
                      style: Aura.bodyMd,
                      decoration: const InputDecoration(
                          hintText: 'channel-name (e.g. quiet-launch)'),
                    ),
                    const SizedBox(height: Aura.spaceMd),
                    TextField(
                      controller: _topic,
                      style: Aura.bodyMd,
                      decoration: const InputDecoration(
                          hintText: 'What’s this channel about? (optional)'),
                    ),
                  ])
                : _tab == 1
                    ? TextField(
                        autofocus: true,
                        style: Aura.bodyMd,
                        decoration: const InputDecoration(
                            hintText:
                                'Start a thread — pick a message to reply to'),
                      )
                    : ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AuraAvatar(
                            initials: 'SC',
                            imageUrl: MockAvatar.you,
                            size: 36),
                        title: const Text('Sarah Chen'),
                        subtitle: Text('Start a direct conversation',
                            style: Aura.bodySm.copyWith(
                                color: scheme.onSurfaceVariant)),
                        onTap: () {},
                      ),
          ),
          const SizedBox(height: Aura.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _creating ? null : _create,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Aura.primary,
              ),
              child: _creating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Aura.onPrimary))
                  : Text(switch (_tab) {
                      0 => 'Create channel',
                      1 => 'Open thread',
                      _ => 'Start conversation',
                    }),
            ),
          ),
        ]),
      ),
    );
  }
}
