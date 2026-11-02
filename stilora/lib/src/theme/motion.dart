import 'package:flutter/material.dart';

import 'tokens.dart';

/// ── Stilora motion toolkit ─────────────────────────────────────────
/// Every animated behavior in the app composes from these helpers so
/// timing/curves stay consistent with DESIGN.md › Motion tokens.
///
/// House style: calm, measured, "breathing" motion — short durations,
/// standard easing, spring settles for spatial changes. Nothing bouncy
/// or attention-seeking (sanctuary aesthetic), but present everywhere
/// interaction happens.

/// Standard fade+rise entrance (menus, cards, detail panes).
class AuraEntrance extends StatefulWidget {
  const AuraEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Aura.durationNormal,
    this.offset = const Offset(0, 0.04),
    this.curve = Aura.easingStandard,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final Curve curve;

  /// Wraps a list with a staggered cascade (index * step).
  static Widget staggered({
    Key? key,
    required List<Widget> children,
    Duration step = const Duration(milliseconds: 45),
    Duration duration = Aura.durationNormal,
    Axis axis = Axis.vertical,
  }) {
    return _StaggeredList(
      key: key,
      step: step,
      duration: duration,
      axis: axis,
      children: children,
    );
  }

  @override
  State<AuraEntrance> createState() => _AuraEntranceState();
}

class _AuraEntranceState extends State<AuraEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fade = CurvedAnimation(parent: _c, curve: widget.curve);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: widget.curve));
    _play();
  }

  Future<void> _play() async {
    if (widget.delay > Duration.zero) await Future<void>.delayed(widget.delay);
    if (mounted) await _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

class _StaggeredList extends StatefulWidget {
  const _StaggeredList({
    super.key,
    required this.children,
    required this.step,
    required this.duration,
    required this.axis,
  });

  final List<Widget> children;
  final Duration step;
  final Duration duration;
  final Axis axis;

  @override
  State<_StaggeredList> createState() => _StaggeredListState();
}

class _StaggeredListState extends State<_StaggeredList>
    with SingleTickerProviderStateMixin {
  late final int _totalMs;
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _totalMs = widget.duration.inMilliseconds +
        widget.step.inMilliseconds * widget.children.length;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _totalMs));
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.forward());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      final start =
          (i * widget.step.inMilliseconds) / (_totalMs == 0 ? 1 : _totalMs);
      final end = ((i + 1) * widget.step.inMilliseconds +
              widget.duration.inMilliseconds) /
          (_totalMs == 0 ? 1 : _totalMs);
      final anim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _c,
          curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
              curve: Aura.easingStandard),
        ),
      );
      items.add(FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: widget.axis == Axis.vertical
                ? const Offset(0, 0.06)
                : const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(anim),
          child: widget.children[i],
        ),
      ));
    }
    return widget.axis == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: items)
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: items,
          );
  }
}

/// Scale+fade pop — for badges, dots, FABs, reaction chips.
class AuraPop extends StatelessWidget {
  const AuraPop({
    super.key,
    required this.child,
    this.visible = true,
    this.duration = Aura.durationNormal,
  });

  final Widget child;
  final bool visible;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: visible ? 1 : 0,
        duration: duration,
        curve: Aura.easingEmphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          curve: Aura.easingStandard,
          child: child,
        ),
      );
}

/// Animated container for hover states (border darken, tint wash).
class AuraHoverable extends StatefulWidget {
  const AuraHoverable({
    super.key,
    required this.child,
    this.onTap,
    this.onHoverChanged,
    this.hoverColor,
    this.hoverBorder,
    this.borderRadius = Aura.radiusLg,
    this.padding = EdgeInsets.zero,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHoverChanged;
  final Color? hoverColor;
  final Color? hoverBorder;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool enabled;

  @override
  State<AuraHoverable> createState() => _AuraHoverableState();
}

class _AuraHoverableState extends State<AuraHoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() {
        _hover = true;
        widget.onHoverChanged?.call(true);
      }),
      onExit: (_) => setState(() {
        _hover = false;
        widget.onHoverChanged?.call(false);
      }),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Aura.durationFast,
          curve: Aura.easingStandard,
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            color: _hover ? (widget.hoverColor ?? scheme.surfaceContainerLow) : Colors.transparent,
            border: Border.all(
              color: _hover
                  ? (widget.hoverBorder ?? scheme.outlineVariant)
                  : Colors.transparent,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Pulsing live dot — voice rooms, "recording", audio-space-active.
class AuraPulseDot extends StatefulWidget {
  const AuraPulseDot({
    super.key,
    this.color = Aura.secondary,
    this.size = 8,
    this.ring = true,
  });

  final Color color;
  final double size;
  final bool ring;

  @override
  State<AuraPulseDot> createState() => _AuraPulseDotState();
}

class _AuraPulseDotState extends State<AuraPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return SizedBox(
      width: widget.size * 3,
      height: widget.size * 3,
      child: Stack(alignment: Alignment.center, children: [
        if (widget.ring)
          FadeTransition(
            opacity: Tween(begin: 0.5, end: 0.0).animate(anim),
            child: ScaleTransition(
              scale: Tween(begin: 0.4, end: 1.6).animate(anim),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ]),
    );
  }
}

/// Speaking audio bars (voice capsule + video stage participant tiles).
class AuraAudioBars extends StatefulWidget {
  const AuraAudioBars({
    super.key,
    this.color = Aura.primary,
    this.active = true,
    this.barCount = 4,
    this.height = 14,
  });

  final Color color;
  final bool active;
  final int barCount;
  final double height;

  @override
  State<AuraAudioBars> createState() => _AuraAudioBarsState();
}

class _AuraAudioBarsState extends State<AuraAudioBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  )..repeat(reverse: true);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce != _reduced) {
      _reduced = reduce;
      if (reduce) {
        _c.stop();
        _c.value = 0.5;
      } else {
        _c.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < widget.barCount; i++)
          Container(
            width: 2.5,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ]);
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.barCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Transform.translate(
                  offset: Offset(0, _barOffset(i)),
                  child: Container(
                    width: 2.5,
                    height: _barHeight(i),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _phase(int i) =>
      ((_c.value + i * 0.17) % 1.0); // staggered per bar
  double _barHeight(int i) {
    final t = Curves.easeInOut.transform(_phase(i));
    final h = 3 + t * (widget.height - 3);
    return h.clamp(3, widget.height);
  }

  double _barOffset(int i) => (_barHeight(i) - 3) / 2 * -1;
}

/// Wrapper giving any tappable child a spring "press" feel.
class AuraPressable extends StatefulWidget {
  const AuraPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  @override
  State<AuraPressable> createState() => _AuraPressableState();
}

class _AuraPressableState extends State<AuraPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _down ? widget.scaleDown : 1,
            duration: Aura.durationInstant,
            curve: Aura.easingEmphasized,
            child: widget.child,
          ),
        ),
      );
}

/// Animated tab underline pill (sign-in method switcher, settings tabs).
class AuraAnimatedSelector<T> extends StatelessWidget {
  const AuraAnimatedSelector({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.padding = const EdgeInsets.all(Aura.spaceXs),
  });

  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Aura.radiusLg),
      ),
      child: Row(children: [
        for (final option in options)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: AnimatedContainer(
                duration: Aura.durationNormal,
                curve: Aura.easingStandard,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: option == value
                      ? scheme.surfaceContainerLowest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(Aura.radiusMd),
                  boxShadow: option == value
                      ? [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedDefaultTextStyle(
                  duration: Aura.durationNormal,
                  style: Aura.labelMd.copyWith(
                    color: option == value
                        ? (option == options.first ? scheme.onSurface : scheme.primary)
                        : scheme.onSurfaceVariant,
                    fontWeight:
                        option == value ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Text(labelOf(option), textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Custom page transition: calm fade + gentle rise, used for all routes.
class AuraPage<T> extends Page<T> {
  const AuraPage({required this.child, this.allowSnapshotting = true});

  final Widget child;
  final bool allowSnapshotting;

  @override
  Route<T> createRoute(BuildContext context) => PageRouteBuilder<T>(
        settings: this,
        transitionDuration: Aura.durationSlow,
        reverseTransitionDuration: Aura.durationNormal,
        opaque: false,
        allowSnapshotting: allowSnapshotting,
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder: (context, anim, secondary, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Aura.easingStandard,
            reverseCurve: Aura.easingStandard,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// Hero-like shared-element accent for the voice capsule → stage route.
class AuraHeroFade extends StatelessWidget {
  const AuraHeroFade({super.key, required this.tag, required this.child});
  final String tag;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Hero(tag: tag, child: child);
}

/// Animated value switcher — smooth digit/label changes (counts, timers).
class AuraAnimatedNumber extends StatelessWidget {
  const AuraAnimatedNumber(this.value, {super.key, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Aura.durationNormal,
        switchInCurve: Aura.easingEmphasized,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          alignment: Alignment.bottomCenter,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Text('$value',
            key: ValueKey(value),
            style: style ?? Aura.labelMd),
      );
}

/// Scroll reveal: fades list content in as it enters the viewport.
class AuraRevealOnScroll extends StatelessWidget {
  const AuraRevealOnScroll({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => AuraEntrance(
        delay: Duration(milliseconds: (index.clamp(0, 12)) * 30),
        child: child,
      );
}
