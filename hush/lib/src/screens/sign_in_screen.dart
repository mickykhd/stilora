import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Unified sign-in — same three methods on every platform:
/// Magic Link · Password · Scan QR (DESIGN.md › Screen inventory).
///
/// Desktop renders the centered sanctuary card; mobile renders the
/// full-bleed envelope shell. One widget, layout-driven.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _AuthMode { magic, password, qr }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  _AuthMode _mode = _AuthMode.magic;
  final _email = TextEditingController(text: 'alex@studio.design');
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid work email.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _submitting = false);
    if (_mode == _AuthMode.magic) {
      // The OTP/link screen listens for this and takes over the shell.
      ref.read(magicLinkSentToProvider.notifier).state = email;
    } else {
      ref.read(signedInProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > Aura.breakpointTablet;
    return Scaffold(
      body: SafeArea(
        child: wide ? _desktopLayout(context) : _mobileLayout(context),
      ),
    );
  }

  // ── Desktop: quiet header + centered card + meta footer ────────
  Widget _desktopLayout(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceXl, vertical: Aura.spaceLg),
        child: Row(children: [
          _BrandMark(size: 28),
          const SizedBox(width: 10),
          Text('Hush',
              style: Aura.headlineSm
                  .copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('Need a workspace?',
              style: Aura.bodySm.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: Aura.spaceMd),
          _Link('Create account', () => _goOnboarding(context)),
        ]),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Aura.marginMobile),
            child: AuraEntrance(
              duration: Aura.durationSlow,
              offset: const Offset(0, 0.03),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AuraCard(
                  padding: const EdgeInsets.all(Aura.spaceXl),
                  child: Column(children: [
                    _BrandMark(size: 40),
                    const SizedBox(height: Aura.spaceMd),
                    Text('Welcome back',
                        style: Aura.headlineLg
                            .copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: Aura.spaceXs),
                    Text('Enter your details to access your workspace',
                        style: Aura.bodyMd
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: Aura.spaceLg),
                    _authBody(context),
                    const SizedBox(height: Aura.spaceLg),
                    _TrustFooter(orientation: Axis.horizontal),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Aura.spaceXl, vertical: Aura.spaceMd),
        child: Row(children: [
          _Link('Privacy', () {}),
          const SizedBox(width: Aura.spaceLg),
          _Link('Terms', () {}),
          const SizedBox(width: Aura.spaceLg),
          _Link('System Status', () {}),
          const Spacer(),
          Text('Hush · v1.0',
              style: Aura.labelSm.copyWith(color: scheme.outline)),
        ]),
      ),
    ]);
  }

  // ── Mobile: envelope shell ─────────────────────────────────────
  Widget _mobileLayout(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Aura.marginMobile),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).vertical -
                64),
        child: Column(children: [
          const SizedBox(height: Aura.spaceXl),
          AuraEntrance.staggered(
            step: const Duration(milliseconds: 60),
            children: [
              Center(child: _BrandMark(size: 48)),
              const SizedBox(height: Aura.spaceMd),
              Center(
                child: Text('Hush',
                    style: Aura.headlineSm
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: Aura.spaceXs),
              Center(
                child: Text('Welcome back',
                    style: Aura.headlineXlMobile
                        .copyWith(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: Aura.spaceXs),
              Center(
                child: Text(
                  'Enter your workspace credentials to restore your continuous focus stream.',
                  textAlign: TextAlign.center,
                  style: Aura.bodySm
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: Aura.spaceLg),
          AuraEntrance(
            delay: const Duration(milliseconds: 220),
            duration: Aura.durationSlow,
            child: AuraCard(
              padding: const EdgeInsets.all(Aura.spaceLg),
              child: _authBody(context),
            ),
          ),
          const SizedBox(height: Aura.spaceLg),
          AuraEntrance(
            delay: const Duration(milliseconds: 340),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Need a workspace?',
                    style: Aura.bodyMd
                        .copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(width: Aura.spaceSm),
                _Link('Create account', () => _goOnboarding(context)),
              ]),
              const SizedBox(height: Aura.spaceMd),
              const _TrustFooter(orientation: Axis.vertical),
            ]),
          ),
          const SizedBox(height: Aura.spaceXl),
        ]),
      ),
    );
  }

  // ── Shared auth body: method selector + active form ────────────
  Widget _authBody(BuildContext context) {
    return AuraEntrance.staggered(
      step: const Duration(milliseconds: 50),
      children: [
        AuraAnimatedSelector<_AuthMode>(
          options: const [_AuthMode.magic, _AuthMode.password, _AuthMode.qr],
          value: _mode,
          labelOf: (m) => switch (m) {
            _AuthMode.magic => 'Magic Link',
            _AuthMode.password => 'Password',
            _AuthMode.qr => 'Scan QR',
          },
          onChanged: (m) => setState(() {
            _mode = m;
            _error = null;
          }),
        ),
        const SizedBox(height: Aura.spaceLg),
        // Animated swap between the three forms
        AnimatedSwitcher(
          duration: Aura.durationNormal,
          switchInCurve: Aura.easingEmphasized,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                      begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(anim),
              child: child,
            ),
          ),
          child: switch (_mode) {
            _AuthMode.magic => _magicForm(context, key: const ValueKey('magic')),
            _AuthMode.password =>
              _passwordForm(context, key: const ValueKey('password')),
            _AuthMode.qr => _qrView(context, key: const ValueKey('qr')),
          },
        ),
      ],
    );
  }

  Widget _magicForm(BuildContext context, {Key? key}) {
    final scheme = ColorScheme.of(context);
    return Column(key: key, children: [
      _GoogleButton(onPressed: () {
        ref.read(signedInProvider.notifier).state = true;
      }),
      const SizedBox(height: Aura.spaceMd),
      Row(children: [
        Expanded(child: Divider(color: scheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Aura.spaceSm),
          child: Text('OR EMAIL',
              style: Aura.labelSm.copyWith(color: scheme.outline)),
        ),
        Expanded(child: Divider(color: scheme.outlineVariant)),
      ]),
      const SizedBox(height: Aura.spaceMd),
      _LabeledField(
        label: 'Work email',
        child: TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          style: Aura.bodyMd,
          decoration: const InputDecoration(hintText: 'name@company.com'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Aura.spaceSm),
        _AnimatedError(_error!),
      ],
      const SizedBox(height: Aura.spaceMd),
      _PrimaryButton(
        label: 'Send magic link',
        busy: _submitting,
        onPressed: _submit,
      ),
    ]);
  }

  Widget _passwordForm(BuildContext context, {Key? key}) {
    return Column(key: key, children: [
      _LabeledField(
        label: 'Work email',
        child: TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          style: Aura.bodyMd,
          decoration: const InputDecoration(hintText: 'name@company.com'),
        ),
      ),
      const SizedBox(height: Aura.spaceMd),
      _LabeledField(
        label: 'Password',
        trailing: _Link('Forgot?', () {}),
        child: TextField(
          controller: _password,
          obscureText: true,
          style: Aura.bodyMd,
          decoration: const InputDecoration(hintText: '••••••••••••'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Aura.spaceSm),
        _AnimatedError(_error!),
      ],
      const SizedBox(height: Aura.spaceMd),
      _PrimaryButton(label: 'Sign in', busy: _submitting, onPressed: _submit),
    ]);
  }

  Widget _qrView(BuildContext context, {Key? key}) {
    final scheme = ColorScheme.of(context);
    return Column(key: key, children: [
      Container(
        padding: const EdgeInsets.all(Aura.spaceMd),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Aura.radiusXl),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(children: [
          // Animated QR placeholder
          _AnimatedQrBox(),
          const SizedBox(height: Aura.spaceMd),
          Text('Scan with your mobile app',
              style: Aura.bodySm.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Open Hush → Settings → Quick Link',
              style: Aura.labelSm.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      const SizedBox(height: Aura.spaceMd),
      AuraChip('● Expiring in 01:58', active: true),
    ]);
  }

  void _goOnboarding(BuildContext context) {
    Navigator.of(context).push(_fadeRoute(const OnboardingFlow()));
  }

  static Route<void> _fadeRoute(Widget page) => PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Aura.easingStandard),
          child: child,
        ),
        transitionDuration: Aura.durationNormal,
      );
}

// ── Small building blocks ────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Aura.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Aura.radiusXl),
          border: Border.all(color: Aura.surfaceVariant.withValues(alpha: 0.4)),
        ),
        child: Icon(Icons.grain, color: Aura.primary, size: size * 0.5),
      );
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(label,
            style: Aura.labelMd.copyWith(color: scheme.primary)),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label.toUpperCase(),
            style: Aura.labelSm.copyWith(color: scheme.onSurfaceVariant)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 6),
      child,
    ]);
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Aura.primaryContainer,
            foregroundColor: Aura.onPrimary,
            minimumSize: const Size.fromHeight(48),
          ),
          child: AnimatedSwitcher(
            duration: Aura.durationFast,
            transitionBuilder: (c, a) =>
                FadeTransition(opacity: a, child: c),
            child: busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Aura.onPrimary),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label),
                      const SizedBox(width: Aura.spaceXs),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
          ),
        ),
      );
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.g_mobiledata, size: 22),
          label: const Text('Continue with Google'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      );
}

class _AnimatedError extends StatelessWidget {
  const _AnimatedError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Aura.durationNormal,
        curve: Aura.easingEmphasized,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * -4), child: child),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 14, color: Aura.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message,
                style: Aura.bodySm.copyWith(color: Aura.error)),
          ),
        ]),
      );
}

class _AnimatedQrBox extends StatefulWidget {
  @override
  State<_AnimatedQrBox> createState() => _AnimatedQrBoxState();
}

class _AnimatedQrBoxState extends State<_AnimatedQrBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final scanAnim = Tween<double>(begin: 0.08, end: 0.92).animate(
        CurvedAnimation(parent: _c, curve: const Interval(0, 0.6,
            curve: Aura.easingStandard)));

    return SizedBox(
      width: 160, height: 160,
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Aura.radiusLg),
          ),
          child: Center(
            child: Icon(Icons.qr_code_2,
                size: 96, color: scheme.outline.withValues(alpha: 0.5)),
          ),
        ),
        // Scanning laser line
        AnimatedBuilder(
          animation: scanAnim,
          builder: (context, _) => Positioned(
            left: 16, right: 16,
            top: scanAnim.value * 160,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: Aura.primary,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Aura.primary.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter({required this.orientation});
  final Axis orientation;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final items = [
      (Icons.lock_outline, 'Encrypted in transit & at rest'),
      (Icons.schedule, 'SSO Ready'),
    ];
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(items[i].$1, size: 14, color: scheme.outline),
        const SizedBox(width: 5),
        Text(items[i].$2,
            style: Aura.labelSm.copyWith(color: scheme.onSurfaceVariant)),
      ]));
      if (i < items.length - 1) {
        children.add(orientation == Axis.horizontal
            ? const SizedBox(width: Aura.spaceLg)
            : const SizedBox(height: Aura.spaceSm));
      }
    }
    return orientation == Axis.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: children)
        : Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Aura.spaceMd, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(Aura.radiusFull),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          );
  }
}

/// Onboarding: create workspace (from "Create account").
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    ref.read(onboardedWorkspaceProvider.notifier).state = _name.text.trim();
    ref.read(signedInProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Aura.marginMobile),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AuraEntrance.staggered(
              step: const Duration(milliseconds: 70),
              children: [
                const Center(child: _BrandMark(size: 44)),
                const SizedBox(height: Aura.spaceMd),
                Center(
                  child: Text('Create your workspace',
                      style: Aura.headlineLg
                          .copyWith(fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: Aura.spaceXs),
                Center(
                  child: Text(
                    'A quiet room for your team. You can invite people anytime.',
                    textAlign: TextAlign.center,
                    style: Aura.bodyMd
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Aura.spaceLg),
                AuraCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WORKSPACE NAME',
                          style: Aura.labelSm
                              .copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _name,
                        style: Aura.bodyMd,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Studio Flow'),
                      ),
                      const SizedBox(height: Aura.spaceLg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _create,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Aura.primary,
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Aura.onPrimary),
                                )
                              : const Text('Create workspace'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Aura.spaceMd),
                Center(
                  child: InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Text('Back to sign in',
                        style: Aura.labelMd
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
