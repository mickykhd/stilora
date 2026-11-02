import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Elevated surface: white (light) / container-lowest (dark), 1px whisper
/// border, `rounded-xl` (12px), flat at rest — borders darken on hover,
/// never translate (DESIGN.md › Cards).
class AuraCard extends StatelessWidget {
  const AuraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Aura.spaceLg),
    this.hoverable = false,
    this.onTap,
    this.border,
    this.color,
    this.radius = Aura.radiusXl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hoverable;
  final VoidCallback? onTap;
  final Color? border;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final card = Material(
      color: color ?? scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: border ?? scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    );
    return card;
  }
}

/// Small tonal metadata chip: recessed fill + `label-sm` graphite type.
class AuraChip extends StatelessWidget {
  const AuraChip(this.label, {super.key, this.icon, this.active = false});

  final String label;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Aura.spaceSm, vertical: 3),
      decoration: BoxDecoration(
        color: active ? Aura.primaryFixed : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Aura.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: active ? Aura.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Aura.labelSm.copyWith(
              color: active ? Aura.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The single, minimal 6px cobalt unread dot — never a red badge.
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: const BoxDecoration(
        color: Aura.secondary, shape: BoxShape.circle,
      ));
}

class PresenceDot extends StatelessWidget {
  const PresenceDot(this.presence, {super.key, this.size = 8, this.ring});
  final int presence; // maps UserPresence index: 0 online, 1 idle, 2 offline
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final color = switch (presence) {
      0 => Aura.presenceOnline,
      1 => Aura.presenceIdle,
      _ => Aura.presenceOffline,
    };
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: ring != null
            ? Border.all(color: ring!, width: 2)
            : null,
      ),
    );
  }
}

/// Circular avatar with initials fallback (no network image in tests).
class AuraAvatar extends StatelessWidget {
  const AuraAvatar({
    super.key,
    required this.initials,
    this.imageUrl,
    this.size = 40,
    this.presence,
    this.ringColor,
  });

  final String initials;
  final String? imageUrl;
  final double size;

  /// 0 online, 1 idle, 2 offline, null = no dot.
  final int? presence;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final showImage = imageUrl != null && (imageUrl?.startsWith('http') ?? false);
    final body = ClipOval(
      child: Container(
        width: size, height: size,
        color: scheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: showImage
            ? Image.network(
                imageUrl!,
                width: size, height: size, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initials(scheme),
                loadingBuilder: (c, child, p) =>
                    p == null ? child : _initials(scheme),
              )
            : _initials(scheme),
      ),
    );
    return SizedBox(
      width: size + 4, height: size + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 2, top: 2,
          child: Container(
            decoration: ringColor != null
                ? BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: ringColor!, width: 1))
                : null,
            child: body,
          ),
        ),
        if (presence != null)
          Positioned(
            right: 0, bottom: 0,
            child: PresenceDot(presence!, size: size * 0.28,
              ring: scheme.surfaceContainerLowest),
          ),
      ]),
    );
  }

  Widget _initials(ColorScheme scheme) => Text(
        initials,
        style: Aura.labelSm.copyWith(
          color: scheme.primary,
          fontSize: size * 0.32,
        ),
      );
}

/// Loading skeleton block — surface tones, shaped like the content it
/// replaces (DESIGN.md › State matrix: no spinners on shaped content).
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = Aura.radiusSm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Aura.easingStandard),
      ),
      child: Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Calm empty state: one line of copy + a single primary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Aura.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: scheme.outline),
              const SizedBox(height: Aura.spaceMd),
            ],
            Text(message, textAlign: TextAlign.center,
                style: Aura.bodyMd.copyWith(color: scheme.onSurfaceVariant)),
            if (actionLabel != null) ...[
              const SizedBox(height: Aura.spaceLg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline error state with retry — never a full-red page.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.offline = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Aura.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.cloud_off : Icons.error_outline,
                size: 32, color: scheme.outline),
            const SizedBox(height: Aura.spaceMd),
            Text(message, textAlign: TextAlign.center,
                style: Aura.bodyMd.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Aura.spaceLg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent slim offline banner.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: Aura.spaceMd, vertical: 6),
      color: Aura.inverseSurface,
      child: Text(
        'Offline — showing cached messages',
        textAlign: TextAlign.center,
        style: Aura.labelMd.copyWith(color: Aura.inverseOnSurface),
      ),
    );
  }
}

/// Permission-denied explainer: why we need it + route to settings.
class PermissionDeniedCard extends StatelessWidget {
  const PermissionDeniedCard({
    super.key,
    required this.reason,
    required this.openSettings,
    this.icon = Icons.mic_none,
  });

  final String reason;
  final VoidCallback openSettings;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: scheme.outline),
          const SizedBox(height: Aura.spaceMd),
          Text(reason, textAlign: TextAlign.center,
              style: Aura.bodyMd.copyWith(color: scheme.onSurface)),
          const SizedBox(height: Aura.spaceLg),
          FilledButton(onPressed: openSettings,
              child: const Text('Open settings')),
        ],
      ),
    );
  }
}

/// Uppercase section label used across sidebars and settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Aura.spaceSm, Aura.spaceMd,
          Aura.spaceSm, Aura.spaceXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text.toUpperCase(),
              style: Aura.labelSm.copyWith(color: scheme.outline)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Focus ring wrapper for custom interactive widgets (a11y requirement).
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Aura.radiusLg),
            border: Border.all(
              color: _focused ? Aura.focusRingColor : Colors.transparent,
              width: Aura.focusRingWidth,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
