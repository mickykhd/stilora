import 'dart:math';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/primitives.dart';

/// OTP code fallback — shown when the magic-link deep link is missed
/// (DESIGN.md › Screen inventory). Six animated digit boxes, auto-advance,
/// paste support, resend timer.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _length = 6;
  final _digits = List<String>.filled(_length, '');
  final _nodes = List<FocusNode>.generate(_length, (_) => FocusNode());
  bool _verifying = false;
  bool _wrong = false;
  int _resendIn = 30;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 0) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _wrong = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    // Demo: any code passes except 000000 (exercises the error animation).
    if (_digits.join() == '000000') {
      setState(() {
        _verifying = false;
        _wrong = true;
      });
      return;
    }
    ref.read(magicLinkSentToProvider.notifier).state = null;
    ref.read(signedInProvider.notifier).state = true;
  }

  void _onChanged(int index, String value) {
    setState(() {
      if (value.length > 1) {
        // Paste: fill from index onward.
        final chars = value.replaceAll(RegExp(r'\D'), '').split('');
        for (var i = 0; i < _length; i++) {
          final charIndex = i - index;
          _digits[i] =
              charIndex >= 0 && charIndex < chars.length ? chars[charIndex] : _digits[i];
        }
        final filled = chars.length.clamp(0, _length - index);
        _nodes[(index + filled).clamp(0, _length - 1)].requestFocus();
      } else {
        _digits[index] = value;
        if (value.isNotEmpty && index < _length - 1) {
          _nodes[index + 1].requestFocus();
        }
      }
      _wrong = false;
    });
    if (_digits.every((d) => d.isNotEmpty)) _verify();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final email = ref.watch(magicLinkSentToProvider) ?? 'your inbox';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Aura.marginMobile),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AuraEntrance.staggered(
              step: const Duration(milliseconds: 60),
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(Aura.spaceMd),
                    decoration: BoxDecoration(
                      color: Aura.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(Aura.radiusXl),
                    ),
                    child: const Icon(Icons.mark_email_read_outlined,
                        color: Aura.primary, size: 26),
                  ),
                ),
                const SizedBox(height: Aura.spaceLg),
                Center(
                  child: Text('Check your code',
                      style: Aura.headlineLg
                          .copyWith(fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: Aura.spaceXs),
                Center(
                  child: Text(
                    'We sent a 6-digit code to $email. '
                    'Enter it below, or use the link in the email.',
                    textAlign: TextAlign.center,
                    style: Aura.bodyMd
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: Aura.spaceLg),
                AuraCard(
                  child: Column(children: [
                    // Digit boxes with shake on error
                    _ShakeWrap(
                      active: _wrong,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: Center(
                                child: _DigitBox(
                                  node: _nodes[i],
                                  value: _digits[i],
                                  error: _wrong,
                                  onChanged: (v) => _onChanged(i, v),
                                  onBackspace: () {
                                    if (i > 0) {
                                      _digits[i] = '';
                                      _nodes[i - 1].requestFocus();
                                      setState(() {});
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_wrong) ...[
                      const SizedBox(height: Aura.spaceSm),
                      Text('That code didn’t match — try again.',
                          style: Aura.bodySm.copyWith(color: Aura.error)),
                    ],
                    const SizedBox(height: Aura.spaceLg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _verifying || !_digits.every((d) => d.isNotEmpty)
                                ? null
                                : _verify,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Aura.primary,
                        ),
                        child: _verifying
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Aura.onPrimary),
                              )
                            : const Text('Verify & continue'),
                      ),
                    ),
                    const SizedBox(height: Aura.spaceMd),
                    AnimatedOpacity(
                      opacity: _resendIn > 0 ? 1 : 0.0,
                      duration: Aura.durationNormal,
                      child: Text(
                        'Resend code in 0:${_resendIn.toString().padLeft(2, '0')}',
                        style: Aura.bodySm.copyWith(color: scheme.outline),
                      ),
                    ),
                    if (_resendIn == 0)
                      InkWell(
                        onTap: () => setState(() {
                          _resendIn = 30;
                          _startResendTimer();
                        }),
                        child: Text('Resend code',
                            style: Aura.labelMd
                                .copyWith(color: scheme.primary)),
                      ),
                  ]),
                ),
                const SizedBox(height: Aura.spaceMd),
                Center(
                  child: InkWell(
                    onTap: () =>
                        ref.read(magicLinkSentToProvider.notifier).state = null,
                    child: Text('Use a different email',
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

class _DigitBox extends StatefulWidget {
  const _DigitBox({
    required this.node,
    required this.value,
    required this.error,
    required this.onChanged,
    required this.onBackspace,
  });

  final FocusNode node;
  final String value;
  final bool error;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  State<_DigitBox> createState() => _DigitBoxState();
}

class _DigitBoxState extends State<_DigitBox> {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final filled = widget.value.isNotEmpty;

    // Listen to the node instead of wrapping another Focus around it —
    // a FocusNode may only attach to one Focus widget (TextField owns it).
    return ListenableBuilder(
      listenable: widget.node,
      builder: (context, _) {
        final focused = widget.node.hasFocus;
        return GestureDetector(
          onTap: () => widget.node.requestFocus(),
          child: AnimatedContainer(
            duration: Aura.durationNormal,
            curve: Aura.easingStandard,
            width: double.infinity,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled
                  ? scheme.surfaceContainerLowest
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(Aura.radiusLg),
              border: Border.all(
                color: widget.error
                    ? Aura.error
                    : focused
                        ? Aura.focusRingColor
                        : filled
                            ? scheme.outlineVariant
                            : Colors.transparent,
                width: focused || widget.error ? 2 : 1,
              ),
            ),
            child: TextField(
              focusNode: widget.node,
              autofocus: false,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 2,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              style: Aura.headlineSm.copyWith(fontSize: 22),
              decoration: const InputDecoration(
                counterText: '',
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                if (v.isEmpty && widget.value.isNotEmpty) {
                  widget.onBackspace();
                  return;
                }
                widget.onChanged(v.substring(v.length - 1));
              },
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal shake for wrong-code feedback (respects reduced motion).
class _ShakeWrap extends StatefulWidget {
  const _ShakeWrap({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_ShakeWrap> createState() => _ShakeWrapState();
}

class _ShakeWrapState extends State<_ShakeWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void didUpdateWidget(covariant _ShakeWrap old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !_reduced) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = sin(t * pi * 6) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
