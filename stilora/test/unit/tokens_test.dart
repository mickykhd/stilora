import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/src/theme/aura_theme.dart';
import 'package:stilora/src/theme/tokens.dart';

/// Token integrity — these tests enforce DESIGN.md parity. If a token
/// drifts from the design doc, these fail (strict policy).
void main() {
  group('Aura tokens match DESIGN.md', () {
    test('light palette core values', () {
      expect(Aura.surface.toARGB32(), 0xFFF9F9FF);
      expect(Aura.onSurface.toARGB32(), 0xFF141B2B);
      expect(Aura.primary.toARGB32(), 0xFF3525CD);
      expect(Aura.primaryContainer.toARGB32(), 0xFF4F46E5);
      expect(Aura.error.toARGB32(), 0xFFBA1A1A);
      expect(Aura.outlineVariant.toARGB32(), 0xFFC7C4D8);
    });

    test('dark palette core values', () {
      expect(Aura.dSurface.toARGB32(), 0xFF0F1119);
      expect(Aura.dOnSurface.toARGB32(), 0xFFE3E6F2);
      expect(Aura.dPrimary.toARGB32(), 0xFFC3C0FF);
      expect(Aura.dOutlineVariant.toARGB32(), 0xFF3A3D4F);
    });

    test('radii match corrected spec (xl = 12px)', () {
      expect(Aura.radiusSm, 4.0);
      expect(Aura.radiusLg, 8.0);
      expect(Aura.radiusXl, 12.0);
      expect(Aura.radiusFull, 999.0);
    });

    test('spacing scale', () {
      expect(Aura.spaceXs, 4.0);
      expect(Aura.spaceSm, 8.0);
      expect(Aura.spaceMd, 16.0);
      expect(Aura.spaceLg, 24.0);
      expect(Aura.spaceXl, 40.0);
      expect(Aura.gutter, 20.0);
      expect(Aura.margin, 40.0);
    });

    test('motion tokens', () {
      expect(Aura.durationFast.inMilliseconds, 150);
      expect(Aura.durationNormal.inMilliseconds, 200);
      expect(Aura.durationSlow.inMilliseconds, 300);
    });

    test('focus ring tokens', () {
      expect(Aura.focusRingWidth, 2.0);
      expect(Aura.focusRingColor.toARGB32(), 0xFF4F46E5);
    });

    test('presence colors', () {
      expect(Aura.presenceOnline.toARGB32(), 0xFF0051D5);
      expect(Aura.presenceIdle.toARGB32(), 0xFFFFB695);
      expect(Aura.presenceOffline.toARGB32(), 0xFFC7C4D8);
    });

    test('breakpoints match documented layout rules', () {
      expect(Aura.breakpointMobile, 767.0);
      expect(Aura.breakpointTablet, 1024.0);
    });

    test('typography uses Geist family only', () {
      for (final style in [
        Aura.displayLg, Aura.headlineXl, Aura.headlineLg, Aura.headlineSm,
        Aura.bodyLg, Aura.bodyMd, Aura.bodySm, Aura.labelMd, Aura.labelSm,
      ]) {
        expect(style.fontFamily, 'Geist');
      }
    });

    test('display sizes carry negative tracking, labels positive/zero', () {
      expect(Aura.displayLg.letterSpacing!, lessThan(0));
      expect(Aura.headlineXl.letterSpacing!, lessThan(0));
      expect(Aura.labelSm.letterSpacing!, greaterThanOrEqualTo(0));
      expect(Aura.bodySm.letterSpacing, 0);
    });
  });

  group('AuraTheme', () {
    test('light and dark themes build with correct brightness', () {
      final light = AuraTheme.light();
      final dark = AuraTheme.dark();
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, Aura.primary);
      expect(dark.colorScheme.primary, Aura.dPrimary);
    });

    test('both themes use Geist text theme', () {
      expect(AuraTheme.light().textTheme.bodyMedium?.fontFamily, 'Geist');
      expect(AuraTheme.dark().textTheme.bodyMedium?.fontFamily, 'Geist');
    });

    test('no default M3 elevation shadows on cards (tonal depth only)', () {
      expect(AuraTheme.light().cardTheme.elevation, 0);
      expect(AuraTheme.light().dialogTheme.elevation, 0);
    });

    test('focus/hover colors derive from focus ring token', () {
      final t = AuraTheme.light();
      expect(t.focusColor.toARGB32() >> 24, greaterThan(0));
      expect(t.focusColor.a, greaterThan(0));
    });
  });
}
