import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../data/mock_data.dart';
import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'secondary_screens.dart';

/// Settings — overlay sheet with left section nav (desktop) and a
/// stacked section list (mobile). Sections per DESIGN.md inventory:
/// Profile · Notifications · Workspace · Members · Audio & Video ·
/// Appearance · Security.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection = 4});

  /// 0 Profile · 1 Notifications · 2 Workspace · 3 Members ·
  /// 4 Audio & Video · 5 Appearance · 6 Security
  final int initialSection;

  static void push(BuildContext context, {int initialSection = 4}) =>
      Navigator.of(context).push(AuraPage<void>(
          child: SettingsScreen(initialSection: initialSection)).createRoute(context));

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _section = widget.initialSection; // Audio & Video by default

  static const _sections = [
    (Icons.person_outline, 'Profile'),
    (Icons.notifications_none, 'Notifications'),
    (Icons.workspaces_outlined, 'Workspace'),
    (Icons.group_outlined, 'Members'),
    (Icons.tune, 'Audio & Video'),
    (Icons.dark_mode_outlined, 'Appearance'),
    (Icons.lock_outline, 'Security'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final wide = MediaQuery.sizeOf(context).width > 768;

    return Scaffold(
      body: Container(
        color: scheme.surface,
        child: Column(children: [
          // Top bar (mirrors app chrome)
          Material(
            color: scheme.surfaceContainerLowest,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: scheme.surfaceContainerHighest)),
              ),
              child: Row(children: [
                Text('Stilora',
                    style: Aura.headlineSm
                        .copyWith(fontWeight: FontWeight.w500, fontSize: 17)),
                if (wide) ...[
                  const SizedBox(width: Aura.spaceLg),
                  Text('Threads',
                      style: Aura.labelMd
                          .copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: Aura.spaceMd),
                  Text('Catch-up',
                      style: Aura.labelMd
                          .copyWith(color: scheme.onSurfaceVariant)),
                ],
                const Spacer(),
                if (wide) ...[
                  AuraChip('• Hardware Synced', active: true),
                  const SizedBox(width: Aura.spaceSm),
                ],
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close settings',
                ),
              ]),
            ),
          ),
          Expanded(
            child: Row(children: [
              // Section nav (desktop)
              if (wide)
                Container(
                  width: 232,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(
                        right:
                            BorderSide(color: scheme.surfaceContainerHighest)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(Aura.spaceSm),
                    children: [
                      for (var i = 0; i < _sections.length; i++)
                        _SettingsNavTile(
                          icon: _sections[i].$1,
                          label: _sections[i].$2,
                          active: _section == i,
                          onTap: () => setState(() => _section = i),
                        ),
                    ],
                  ),
                ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                      wide ? Aura.spaceXl : Aura.spaceMd),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: AnimatedSwitcher(
                        duration: Aura.durationNormal,
                        switchInCurve: Aura.easingEmphasized,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0, 0.03),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: switch (_section) {
                          0 => const _ProfileSection(
                              key: ValueKey('profile')),
                          1 => const _NotificationsSection(
                              key: ValueKey('notif')),
                          2 => const _WorkspaceSection(
                              key: ValueKey('ws')),
                          3 => const _MembersSection(
                              key: ValueKey('members')),
                          4 => const _AvSection(key: ValueKey('av')),
                          5 => const _AppearanceSection(
                              key: ValueKey('appearance')),
                          _ => const _SecuritySection(
                              key: ValueKey('security')),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SettingsNavTile extends StatefulWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SettingsNavTile> createState() => _SettingsNavTileState();
}

class _SettingsNavTileState extends State<_SettingsNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final lit = _hover || widget.active;
    return InkWell(
      onTap: widget.onTap,
      onHover: (h) => setState(() => _hover = h),
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceSm, vertical: 10),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: widget.active
              ? Aura.primaryFixed.withValues(alpha: 0.5)
              : lit
                  ? scheme.surfaceContainer
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          Icon(widget.icon,
              size: 17,
              color:
                  widget.active ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(widget.label,
              style: Aura.labelMd.copyWith(
                color:
                    widget.active ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight:
                    widget.active ? FontWeight.w600 : FontWeight.w500,
              )),
        ]),
      ),
    );
  }
}

// ── Section scaffolds ────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.eyebrow, required this.title, required this.subtitle});

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Aura.spaceLg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow.toUpperCase(),
            style: Aura.labelSm
                .copyWith(color: scheme.primary, letterSpacing: 1.6)),
        const SizedBox(height: 4),
        Text(title,
            style: Aura.headlineLg.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: Aura.bodyMd.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: Aura.spaceMd),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ]),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child, this.title, this.trailing});

  final Widget child;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AuraCard(
        padding: const EdgeInsets.all(Aura.spaceLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!,
                    style: Aura.headlineSm.copyWith(fontSize: 16)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: Aura.spaceMd),
          ],
          child,
        ]),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Aura.onPrimary,
        activeTrackColor: Aura.primaryContainer,
      );
}

// ── Profile ──────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 60),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences',
          title: 'Your profile',
          subtitle: 'How you appear across your workspace.',
        ),
        AuraCard(
          child: Row(children: [
            AuraAvatar(
                initials: MockData.you.initials,
                size: 64,
                presence: MockData.you.presence.index),
            const SizedBox(width: Aura.spaceLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(MockData.you.name, style: Aura.headlineSm),
                  Text(
                      '@${MockData.you.handle} • ${MockData.you.roleLabel}',
                      style: Aura.bodySm
                          .copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            OutlinedButton(onPressed: () {}, child: const Text('Edit')),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Display name',
          child: const TextField(
              style: TextStyle(), decoration: InputDecoration(hintText: 'You')),
        ),
      ],
    );
  }
}

// ── Notifications ────────────────────────────────────────────────

class _NotificationsSection extends ConsumerStatefulWidget {
  const _NotificationsSection({super.key});

  @override
  ConsumerState<_NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState
    extends ConsumerState<_NotificationsSection> {
  bool _deepWork = true;
  bool _mentions = true;
  bool _threads = true;
  bool _voice = false;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 60),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences',
          title: 'Notifications',
          subtitle: 'Held until your next intentional break.',
        ),
        _SettingCard(
          title: 'Deep work threshold',
          trailing: _Toggle(value: _deepWork, onChanged: (v) => setState(() => _deepWork = v)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'While active, notifications are held and delivered together when the window ends.',
              style: Aura.bodySm
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (_deepWork) ...[
              const SizedBox(height: Aura.spaceMd),
              Row(children: [
                Expanded(
                  child: _TimeField(
                    label: 'From',
                    time: _start,
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _start);
                      if (t != null) setState(() => _start = t);
                    },
                  ),
                ),
                const SizedBox(width: Aura.spaceMd),
                Expanded(
                  child: _TimeField(
                    label: 'Until',
                    time: _end,
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _end);
                      if (t != null) setState(() => _end = t);
                    },
                  ),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Deliver immediately',
          child: Column(children: [
            _ToggleRow(
                label: 'Mentions & keywords',
                value: _mentions,
                onChanged: (v) => setState(() => _mentions = v)),
            _ToggleRow(
                label: 'Thread replies',
                value: _threads,
                onChanged: (v) => setState(() => _threads = v)),
            _ToggleRow(
                label: 'Voice room invites',
                value: _voice,
                onChanged: (v) => setState(() => _voice = v)),
          ]),
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField(
      {required this.label, required this.time, required this.onTap});

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceMd, vertical: 12),
        decoration: BoxDecoration(
          color: Aura.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          Icon(Icons.schedule, size: 15, color: scheme.outline),
          const SizedBox(width: 8),
          Text(label, style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(time.format(context), style: Aura.labelMd),
        ]),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: Aura.bodyMd)),
          _Toggle(value: value, onChanged: onChanged),
        ]),
      );
}

// ── Workspace & Members ──────────────────────────────────────────

class _WorkspaceSection extends StatelessWidget {
  const _WorkspaceSection({super.key});

  @override
  Widget build(BuildContext context) => AuraEntrance.staggered(
        step: const Duration(milliseconds: 60),
        children: [
          const _SectionHeader(
            eyebrow: 'Preferences',
            title: 'Workspace',
            subtitle: 'Name, invite code, and defaults for your workspace.',
          ),
          _SettingCard(
            title: 'Workspace name',
            child: const TextField(
                decoration: InputDecoration(hintText: 'e.g. Workspace name')),
          ),
          const SizedBox(height: Aura.spaceMd),
          _SettingCard(
            title: 'Invite code',
            trailing: OutlinedButton(
                onPressed: () {}, child: const Text('Regenerate')),
            child: SelectableText('stilora-quiet-flow-24',
                style: Aura.bodyMd.copyWith(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1)),
          ),
        ],
      );
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final members = ref.watch(membersProvider);

    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 55),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences',
          title: 'Members',
          subtitle: '5 people in Studio Flow.',
        ),
        AuraCard(
          padding: EdgeInsets.zero,
          child: members.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Aura.spaceXl),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, __) => ErrorState(
                message: 'Couldn’t load members.',
                onRetry: () => ref.invalidate(membersProvider)),
            data: (list) => Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                ListTile(
                  leading: AuraAvatar(
                    initials: list[i].initials,
                    imageUrl: list[i].avatarUrl,
                    size: 34,
                    presence: list[i].presence.index,
                  ),
                  title: Text(list[i].name, style: Aura.labelMd),
                  subtitle: Text(list[i].roleLabel,
                      style: Aura.bodySm
                          .copyWith(color: scheme.onSurfaceVariant)),
                  trailing: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz, size: 18)),
                  onTap: () => ProfileScreen.push(context, list[i]),
                ),
                if (i < list.length - 1)
                  Divider(
                      color:
                          scheme.outlineVariant.withValues(alpha: 0.4)),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Audio & Video (mirrors the mockup) ──────────────────────────

class _AvSection extends StatefulWidget {
  const _AvSection({super.key});

  @override
  State<_AvSection> createState() => _AvSectionState();
}

class _AvSectionState extends State<_AvSection> with SingleTickerProviderStateMixin {
  double _gain = 82;
  double _volume = 68;
  bool _vad = true;
  bool _mirror = true;
  bool _depth = false;
  bool _neural = true;
  bool _noise = true;
  bool _aec = true;
  late final AnimationController _levelC = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _levelC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final wide = MediaQuery.sizeOf(context).width > 900;

    final left = AuraEntrance.staggered(
      step: const Duration(milliseconds: 60),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences • System Audio & Video Subsystem',
          title: 'Audio & Video Devices',
          subtitle:
              'Configure input clarity, echo suppression, audio monitoring, and optical framing with uncompressed zero-latency preview.',
        ),
        _SettingCard(
          title: 'Input Device',
          trailing: AuraChip('48.0 kHz • 24-Bit', active: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Selected primary recording microphone',
                style: Aura.bodySm
                    .copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Aura.spaceMd),
            const _Dropdown(
                items: [
                  'Rode NT-USB Mini (Studio Precision)',
                  'Built-in Microphone Array',
                  'AirPods Pro (Hands-Free)',
                ]),
            const SizedBox(height: Aura.spaceLg),
            _SliderRow(
                label: 'Input Sensitivity & Gain',
                value: _gain,
                unit: '%',
                onChanged: (v) => setState(() => _gain = v)),
            const SizedBox(height: Aura.spaceMd),
            Row(children: [
              Text('LIVE INPUT LEVEL',
                  style: Aura.labelSm.copyWith(color: scheme.outline)),
              const Spacer(),
              const AuraPulseDot(color: Aura.secondary, size: 5, ring: false),
              const SizedBox(width: 6),
              Text('Real-time test',
                  style: Aura.labelSm.copyWith(color: scheme.primary)),
            ]),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: _levelC,
              builder: (context, _) => Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: _levelC.value * 7 > i
                            ? (i > 4 ? Aura.secondary : Aura.primary)
                            : scheme.surfaceContainerHigh,
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Speak naturally to test baseline capture headroom.',
                style: Aura.bodySm
                    .copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Output Device',
          trailing: TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow, size: 15),
              label: const Text('Test Sound')),
          child: Column(children: [
            const _Dropdown(
                items: [
                  'Sennheiser HD 600 via DAC (Balanced)',
                  'Built-in Speakers',
                  'External Headset',
                ]),
            const SizedBox(height: Aura.spaceLg),
            _SliderRow(
                label: 'Output Volume',
                value: _volume,
                unit: '%',
                onChanged: (v) => setState(() => _volume = v)),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Input Transmission Mode',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Manage voice transmission trigger logic',
                style: Aura.bodySm
                    .copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Aura.spaceMd),
            AuraAnimatedSelector<bool>(
              options: const [true, false],
              value: _vad,
              labelOf: (v) => v ? 'Voice Activity' : 'Push to Talk',
              onChanged: (v) => setState(() => _vad = v),
            ),
            const SizedBox(height: Aura.spaceLg),
            _SliderRow(
              label: 'Gate Threshold Sensitivity',
              value: 46,
              suffixLabel: '-46 dB (Auto-calibrated)',
              min: 0,
              max: 90,
              onChanged: (_) {},
            ),
            const SizedBox(height: 8),
            Text(
              'Background noise below −46 dB will be suppressed automatically.',
              style: Aura.bodySm
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ],
    );

    final right = AuraEntrance.staggered(
      step: const Duration(milliseconds: 70),
      children: [
        _SettingCard(
          title: 'Camera Source',
          trailing: AuraChip('1080p60', active: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Optical framing device',
                style: Aura.bodySm
                    .copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Aura.spaceMd),
            const _Dropdown(
                items: [
                  'FaceTime HD Camera (Ultra-Wide Pro)',
                  'Integrated Webcam',
                  'OBS Virtual Camera',
                ]),
            const SizedBox(height: Aura.spaceMd),
            // Camera preview
            Container(
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Aura.radiusLg),
                gradient: LinearGradient(colors: [
                  scheme.surfaceContainerHigh,
                  scheme.surfaceContainer,
                ]),
              ),
              child: Stack(children: [
                Center(
                    child: Icon(Icons.person, size: 72,
                        color: scheme.outline.withValues(alpha: 0.4))),
                Positioned(
                  left: 10, top: 10,
                  child: AuraChip('● Preview Active', active: true),
                ),
                Positioned(
                  right: 10, bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius:
                          BorderRadius.circular(Aura.radiusFull),
                    ),
                    child: Text('1920 × 1080 • 60 FPS',
                        style: Aura.labelSm
                            .copyWith(color: Colors.white)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: Aura.spaceMd),
            _ToggleRow(
                label: 'Mirror My Video',
                value: _mirror,
                onChanged: (v) => setState(() => _mirror = v)),
            _ToggleRow(
                label: 'Portrait Depth & Background Blur',
                value: _depth,
                onChanged: (v) => setState(() => _depth = v)),
            _ToggleRow(
                label: 'Neural Engine Processing',
                value: _neural,
                onChanged: (v) => setState(() => _neural = v)),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Acoustic Clarity Enhancements',
          child: Column(children: [
            _CheckRow(
                label: 'Zero-Artifact Noise Suppression',
                detail:
                    'Eliminates mechanical keyboard clicks & fan hum',
                value: _noise,
                onChanged: (v) => setState(() => _noise = v)),
            const SizedBox(height: Aura.spaceSm),
            _CheckRow(
                label: 'Acoustic Echo Cancellation',
                detail:
                    'Prevents speaker feedback during open-mic discussions',
                value: _aec,
                onChanged: (v) => setState(() => _aec = v)),
          ]),
        ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: Aura.spaceLg),
          SizedBox(width: 380, child: right),
        ],
      );
    }
    return Column(children: [left, const SizedBox(height: Aura.spaceMd), right]);
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: items.first,
        isExpanded: true,
        style: Aura.bodyMd,
        dropdownColor: Aura.surfaceContainerLowest,
        icon: const Icon(Icons.expand_more, size: 20),
        menuMaxHeight: 280,
        decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
        items: [
          for (final it in items)
            DropdownMenuItem(
              value: it,
              child: Text(it,
                  overflow: TextOverflow.ellipsis, style: Aura.bodyMd),
            ),
        ],
        onChanged: (_) {},
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.unit = '',
    this.suffixLabel,
    this.min = 0,
    this.max = 100,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String unit;
  final String? suffixLabel;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text(label,
              style: Aura.labelMd.copyWith(color: scheme.onSurface)),
        ),
        Text(suffixLabel ?? '${value.round()}$unit',
            style: Aura.labelSm.copyWith(color: scheme.primary)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: Aura.primary,
          inactiveTrackColor: scheme.surfaceContainerHigh,
          thumbColor: Aura.primary,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(
      {required this.label,
      required this.detail,
      required this.value,
      required this.onChanged});

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      child: AnimatedContainer(
        duration: Aura.durationFast,
        padding: const EdgeInsets.all(Aura.spaceSm),
        decoration: BoxDecoration(
          color: value
              ? Aura.primaryFixed.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: Aura.durationFast,
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? Aura.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: value ? Aura.primary : scheme.outlineVariant,
                  width: 1.5),
            ),
            child: AnimatedScale(
              scale: value ? 1 : 0,
              duration: Aura.durationFast,
              child: const Icon(Icons.check,
                  size: 14, color: Aura.onPrimary),
            ),
          ),
          const SizedBox(width: Aura.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Aura.labelMd),
                Text(detail,
                    style: Aura.bodySm
                        .copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Appearance ───────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final mode = ref.watch(themeModeProvider);

    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 60),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences',
          title: 'Appearance',
          subtitle: 'Light, dark, or follow the system — full parity either way.',
        ),
        AuraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: Aura.labelMd),
              const SizedBox(height: Aura.spaceMd),
              AuraAnimatedSelector<String>(
                options: const ['system', 'light', 'dark'],
                value: mode,
                labelOf: (m) =>
                    switch (m) { 'light' => 'Light', 'dark' => 'Dark', _ => 'System' },
                onChanged: (m) =>
                    ref.read(themeModeProvider.notifier).state = m,
              ),
              const SizedBox(height: Aura.spaceMd),
              Text(
                'Every screen ships both themes — goldens enforce parity.',
                style: Aura.bodySm
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Motion',
          child: Text(
            'Stilora uses calm, measured transitions and respects your system’s '
            '“reduce motion” setting automatically.',
            style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ── Security ─────────────────────────────────────────────────────

/// Security section needs refs for sign-out, so it's a Consumer.
class _SecuritySection extends ConsumerWidget {
  const _SecuritySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 60),
      children: [
        const _SectionHeader(
          eyebrow: 'Preferences',
          title: 'Security',
          subtitle: 'Sessions, devices, and encryption posture.',
        ),
        _SettingCard(
          title: 'Encryption',
          child: Row(children: [
            Icon(Icons.lock_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Encrypted in transit & at rest',
                  style: Aura.bodyMd),
            ),
            AuraChip('Active', active: true),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Active sessions',
          child: Column(children: [
            _SessionRow(
                device: 'This device • Linux',
                meta: 'Current session',
                current: true),
            Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _SessionRow(
                device: 'Pixel 9 • Android',
                meta: 'Last active 2h ago',
                current: false),
          ]),
        ),
        const SizedBox(height: Aura.spaceMd),
        _SettingCard(
          title: 'Danger zone',
          child: Row(children: [
            Expanded(
              child: Text('Sign out of all devices',
                  style: Aura.bodyMd.copyWith(color: Aura.error)),
            ),
            OutlinedButton(
              onPressed: () {
                // Real sign-out: drops the session and returns to sign-in.
                ref.read(signedInProvider.notifier).state = false;
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Aura.error),
                  foregroundColor: Aura.error),
              child: const Text('Sign out'),
            ),
          ]),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(
      {required this.device, required this.meta, required this.current});

  final String device;
  final String meta;
  final bool current;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(current ? Icons.phone_android : Icons.devices,
              size: 18, color: Aura.outline),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device, style: Aura.labelMd),
              Text(meta,
                  style: Aura.bodySm.copyWith(color: Aura.outline)),
            ]),
          ),
          if (current) const AuraChip('This device', active: true),
        ]),
      );
}

// ── Mobile tabs (bottom nav destinations) ───────────────────────

/// Threads/Channels list tab (mobile, pre-channel).
class MobileListTab extends ConsumerWidget {
  const MobileListTab({
    super.key,
    required this.dmMode,
    required this.onChannelSelected,
    required this.onDmSelected,
    required this.onSearch,
    required this.onCompose,
    this.onActivity,
  });

  final bool dmMode;
  final ValueChanged<Channel> onChannelSelected;
  final ValueChanged<DmConversation> onDmSelected;
  final VoidCallback onSearch;
  final VoidCallback onCompose;
  final VoidCallback? onActivity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final workspace =
        ref.watch(workspaceProvider).valueOrNull ?? MockData.workspace;
    final channels = ref.watch(channelsProvider);
    final dms = ref.watch(conversationsProvider);
    final room = ref.watch(voiceRoomProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(channelsProvider);
            ref.invalidate(conversationsProvider);
          },
          child: ListView(padding: const EdgeInsets.all(Aura.gutterMobile), children: [
            // Header
            AuraEntrance.staggered(
              step: const Duration(milliseconds: 50),
              children: [
                Row(children: [
                  AuraAvatar(initials: workspace.initials, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(workspace.name,
                              style: Aura.headlineSm.copyWith(fontSize: 18)),
                          const SizedBox(width: 6),
                          Icon(Icons.unfold_more,
                              size: 15, color: scheme.outline),
                        ]),
                        Row(children: [
                          const PresenceDot(0, size: 6),
                          const SizedBox(width: 5),
                          Text('${workspace.onlineCount} online',
                              style: Aura.bodySm.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(
                      onPressed: onSearch,
                      icon: const Icon(Icons.search)),
                  IconButton(
                    onPressed: onActivity,
                    icon: const Icon(Icons.notifications_none),
                    tooltip: 'Notifications',
                  ),
                  AuraPressable(
                    onTap: onCompose,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Aura.primaryFixed,
                        borderRadius:
                            BorderRadius.circular(Aura.radiusLg),
                      ),
                      child: const Icon(Icons.edit,
                          size: 18, color: Aura.primary),
                    ),
                  ),
                ]),
                const SizedBox(height: Aura.spaceMd),
                // Voice capsule
                if (room.connected)
                  AuraPressable(
                    onTap: () => ref
                        .read(voiceRoomProvider.notifier)
                        .update((r) => r),
                    child: Container(
                      padding: const EdgeInsets.all(Aura.spaceSm + 2),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius:
                            BorderRadius.circular(Aura.radiusXl),
                        border: Border.all(
                            color: scheme.outlineVariant
                                .withValues(alpha: 0.6)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Aura.primaryFixed,
                            borderRadius:
                                BorderRadius.circular(Aura.radiusLg),
                          ),
                          child: const Icon(Icons.mic,
                              size: 17, color: Aura.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Flexible(
                                  child: Text(room.roomName,
                                      overflow: TextOverflow.ellipsis,
                                      style: Aura.labelMd.copyWith(
                                          fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 6),
                                const UnreadDot(),
                              ]),
                              Text(room.stateLabel,
                                  style: Aura.bodySm.copyWith(
                                      color:
                                          scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: scheme.outlineVariant),
                            borderRadius:
                                BorderRadius.circular(Aura.radiusLg),
                          ),
                          child: Row(children: [
                            Icon(Icons.mic_off,
                                size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text('Mute', style: Aura.labelSm),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: Aura.spaceLg),
                // Featured thread card
                Row(children: [
                  Text('FEATURED THREAD',
                      style: Aura.labelSm
                          .copyWith(color: scheme.outline)),
                  const Spacer(),
                  Text('View thread',
                      style: Aura.labelMd
                          .copyWith(color: scheme.primary)),
                ]),
                const SizedBox(height: Aura.spaceSm),
                AuraCard(
                  padding: const EdgeInsets.all(Aura.spaceMd),
                  onTap: () {
                    final list = channels.valueOrNull;
                    if (list != null && list.length > 1) {
                      onChannelSelected(list[1]);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('# ',
                            style: Aura.labelMd
                                .copyWith(color: scheme.primary)),
                        Text('design-sync',
                            style: Aura.labelMd.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('14m ago',
                            style: Aura.bodySm
                                .copyWith(color: scheme.outline)),
                      ]),
                      const SizedBox(height: Aura.spaceSm),
                      Text('Scandinavian Spacing Tokens & Calm Architecture',
                          style: Aura.headlineSm.copyWith(fontSize: 17)),
                      const SizedBox(height: Aura.spaceSm),
                      Text(
                        'Sarah Chen: “Consolidated all margins to 1.25rem gutters. Eliminating colored badge…',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Aura.bodyMd
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Aura.spaceMd),
                      Row(children: [
                        AuraChip('SC MV +4'),
                        const Spacer(),
                        Icon(Icons.chat_bubble_outline,
                            size: 14, color: scheme.outline),
                        const SizedBox(width: 4),
                        Text('18 replies',
                            style: Aura.labelSm
                                .copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(width: Aura.spaceMd),
                        const Icon(Icons.favorite_border,
                            size: 14, color: Aura.primary),
                        const SizedBox(width: 4),
                        Text('9',
                            style: Aura.labelSm
                                .copyWith(color: Aura.primary)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Aura.spaceLg),
            if (!dmMode)
              channels.when(
                loading: () => const Column(children: [
                  SkeletonBlock(height: 18),
                  SizedBox(height: 10),
                  SkeletonBlock(height: 18),
                ]),
                error: (_, __) => ErrorState(
                    message: 'Couldn’t load channels.',
                    onRetry: () => ref.invalidate(channelsProvider)),
                data: (list) => Column(children: [
                  Row(children: [
                    Text('CHANNELS',
                        style: Aura.labelSm
                            .copyWith(color: scheme.outline)),
                    const SizedBox(width: 8),
                    AuraChip('${list.length}'),
                    const Spacer(),
                    Icon(Icons.add, size: 17, color: scheme.outline),
                  ]),
                  const SizedBox(height: Aura.spaceSm),
                  AuraEntrance.staggered(
                    step: const Duration(milliseconds: 40),
                    children: [
                      for (final c in list)
                        _MobileChannelRow(
                            channel: c, onTap: () => onChannelSelected(c)),
                    ],
                  ),
                ]),
              )
            else
              dms.when(
                loading: () => const Column(children: [
                  SkeletonBlock(height: 18),
                  SizedBox(height: 10),
                  SkeletonBlock(height: 18),
                ]),
                error: (_, __) => ErrorState(
                    message: 'Couldn’t load conversations.',
                    onRetry: () => ref.invalidate(conversationsProvider)),
                data: (list) => Column(children: [
                  Row(children: [
                    Text('DIRECT MESSAGES',
                        style: Aura.labelSm
                            .copyWith(color: scheme.outline)),
                    const SizedBox(width: 8),
                    AuraChip('${list.length}'),
                    const Spacer(),
                    Icon(Icons.more_horiz, size: 17, color: scheme.outline),
                  ]),
                  const SizedBox(height: Aura.spaceSm),
                  AuraEntrance.staggered(
                    step: const Duration(milliseconds: 40),
                    children: [
                      for (final dm in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: AuraAvatar(
                            initials: dm.peer.initials,
                            imageUrl: dm.peer.avatarUrl,
                            size: 44,
                            presence: dm.peer.presence.index,
                          ),
                          title: Text(dm.peer.name,
                              style: Aura.labelMd),
                          subtitle: Text(dm.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Aura.bodySm.copyWith(
                                  color: scheme.onSurfaceVariant)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(dm.timeLabel,
                                  style: Aura.labelSm
                                      .copyWith(color: scheme.outline)),
                              if (dm.unread)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: UnreadDot(),
                                ),
                            ],
                          ),
                          onTap: () => onDmSelected(dm),
                        ),
                    ],
                  ),
                ]),
              ),
            const SizedBox(height: Aura.spaceLg),
            // Deep-work note
            AuraEntrance(
              child: Container(
                padding: const EdgeInsets.all(Aura.spaceMd),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius:
                      BorderRadius.circular(Aura.radiusXl),
                ),
                child: Row(children: [
                  Icon(Icons.self_improvement,
                      size: 18, color: scheme.outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Deep work threshold active. Notifications held until next intentional break.',
                      style: Aura.bodySm
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Aura.spaceLg),
          ]),
        ),
      ),
    );
  }
}

class _MobileChannelRow extends StatefulWidget {
  const _MobileChannelRow({required this.channel, required this.onTap});

  final Channel channel;
  final VoidCallback onTap;

  @override
  State<_MobileChannelRow> createState() => _MobileChannelRowState();
}

class _MobileChannelRowState extends State<_MobileChannelRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final c = widget.channel;

    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Aura.durationFast,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
              horizontal: Aura.spaceSm, vertical: 13),
          decoration: BoxDecoration(
            color: _down
                ? scheme.surfaceContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Aura.radiusLg),
          ),
          child: Row(children: [
            Text('#',
                style: Aura.bodyMd.copyWith(
                    color: c.unreadCount > 0
                        ? scheme.primary
                        : scheme.outline,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  style: Aura.bodyMd.copyWith(
                    color: c.unreadCount > 0
                        ? scheme.primary
                        : scheme.onSurface,
                    fontWeight: c.unreadCount > 0
                        ? FontWeight.w600
                        : FontWeight.w400,
                  )),
            ),
            if (c.unreadCount > 0)
              AuraChip('${c.unreadCount} unread', active: true)
            else
              Text(c.lastActivityLabel,
                  style: Aura.bodySm
                      .copyWith(color: scheme.outline)),
          ]),
        ),
      ),
    );
  }
}

/// Voice tab (mobile): room overview + join.
class MobileVoiceTab extends ConsumerWidget {
  const MobileVoiceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final room = ref.watch(voiceRoomProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Aura.gutterMobile),
          child: AuraEntrance.staggered(
            step: const Duration(milliseconds: 60),
            children: [
              Text('Voice', style: Aura.headlineXlMobile),
              const SizedBox(height: Aura.spaceLg),
              AuraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const AuraPulseDot(color: Aura.secondary, size: 7),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(room.roomName,
                            style: Aura.headlineSm
                                .copyWith(fontSize: 17)),
                      ),
                    ]),
                    const SizedBox(height: Aura.spaceSm),
                    Text(room.connected ? room.stateLabel : 'Not connected',
                        style: Aura.bodySm
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: Aura.spaceLg),
                    // Participant avatars
                    Row(children: [
                      for (var i = 0;
                          i < room.participants.length && i < 5;
                          i++)
                        Padding(
                          padding:
                              const EdgeInsets.only(right: 8),
                          child: AuraAvatar(
                            initials: room.participants[i].initials,
                            imageUrl: room.participants[i].avatarUrl,
                            size: 44,
                            presence:
                                room.participants[i].presence.index,
                            ringColor: room.speakingIds
                                        .contains(room.participants[i].id)
                                    ? Aura.primary
                                    : null,
                          ),
                        ),
                      if (room.participants.isEmpty)
                        Text('Nobody here yet',
                            style: Aura.bodySm.copyWith(
                                color: scheme.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: Aura.spaceLg),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              VoiceStageScreen.push(context),
                          style: FilledButton.styleFrom(
                              backgroundColor: Aura.primary,
                              minimumSize: const Size.fromHeight(46)),
                          icon: Icon(
                              room.connected
                                  ? Icons.video_call
                                  : Icons.voice_chat,
                              size: 17),
                          label: Text(room.connected
                              ? 'Open stage'
                              : 'Join room'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: Aura.spaceMd),
              AuraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recent rooms',
                        style: Aura.headlineSm
                            .copyWith(fontSize: 16)),
                    const SizedBox(height: Aura.spaceMd),
                    _RoomRow(
                        name: 'Design Sync Standup',
                        meta: 'Yesterday • 22 min'),
                    Divider(
                        color: scheme.outlineVariant
                            .withValues(alpha: 0.4)),
                    _RoomRow(
                        name: 'Quiet Co-working',
                        meta: 'Monday • 1h 40m'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.name, required this.meta});

  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Aura.surfaceContainerLow,
              borderRadius: BorderRadius.circular(Aura.radiusLg),
            ),
            child: const Icon(Icons.graphic_eq,
                size: 15, color: Aura.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Aura.labelMd),
                Text(meta,
                    style: Aura.bodySm
                        .copyWith(color: Aura.outline)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: Aura.outline),
        ]),
      );
}

/// Settings tab (mobile): section list → pushes SettingsScreen.
class MobileSettingsTab extends StatelessWidget {
  const MobileSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: AuraEntrance.staggered(
          step: const Duration(milliseconds: 55),
          children: [
            Padding(
              padding: const EdgeInsets.all(Aura.gutterMobile),
              child: Text('Settings',
                  style: Aura.headlineXlMobile),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Aura.gutterMobile),
              child: AuraCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, icon, label) in [
                    (0, Icons.person_outline, 'Profile'),
                    (1, Icons.notifications_none, 'Notifications'),
                    (2, Icons.workspaces_outlined, 'Workspace'),
                    (3, Icons.group_outlined, 'Members'),
                    (4, Icons.tune, 'Audio & Video'),
                    (5, Icons.dark_mode_outlined, 'Appearance'),
                    (6, Icons.lock_outline, 'Security'),
                  ]) ...[
                    ListTile(
                      leading: Icon(icon, size: 19, color: scheme.outline),
                      title: Text(label, style: Aura.labelMd),
                      trailing: Icon(Icons.chevron_right,
                          size: 18, color: scheme.outline),
                      onTap: () =>
                          SettingsScreen.push(context, initialSection: i),
                    ),
                    if (i < 6)
                      Divider(
                          color: scheme.outlineVariant
                              .withValues(alpha: 0.4)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: Aura.spaceMd),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Aura.gutterMobile),
              child: Text('Stilora · v1.0',
                  style: Aura.labelSm.copyWith(color: scheme.outline)),
            ),
          ],
        ),
      ),
    );
  }
}
