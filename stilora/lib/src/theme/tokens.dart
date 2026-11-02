import 'package:flutter/material.dart';

/// Stilora design tokens — generated from `aura/DESIGN.md` (source of truth).
///
/// Every value here MUST match the YAML frontmatter of DESIGN.md.
/// Golden tests enforce parity: changing a token without updating the
/// design doc (or vice versa) will fail review.
abstract final class Aura {
  // ── Light theme ────────────────────────────────────────────────
  static const surface = Color(0xFFF9F9FF);
  static const surfaceDim = Color(0xFFD3DAEF);
  static const surfaceBright = Color(0xFFF9F9FF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF1F3FF);
  static const surfaceContainer = Color(0xFFE9EDFF);
  static const surfaceContainerHigh = Color(0xFFE1E8FD);
  static const surfaceContainerHighest = Color(0xFFDCE2F7);
  static const onSurface = Color(0xFF141B2B);
  static const onSurfaceVariant = Color(0xFF464555);
  static const inverseSurface = Color(0xFF293040);
  static const inverseOnSurface = Color(0xFFEDF0FF);
  static const outline = Color(0xFF777587);
  static const outlineVariant = Color(0xFFC7C4D8);
  static const surfaceTint = Color(0xFF4D44E3);
  static const primary = Color(0xFF3525CD);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF4F46E5);
  static const onPrimaryContainer = Color(0xFFDAD7FF);
  static const inversePrimary = Color(0xFFC3C0FF);
  static const secondary = Color(0xFF0051D5);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF316BF3);
  static const onSecondaryContainer = Color(0xFFFEFCFF);
  static const tertiary = Color(0xFF7E3000);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFA44100);
  static const onTertiaryContainer = Color(0xFFFFD2BE);
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
  static const primaryFixed = Color(0xFFE2DFFF);
  static const primaryFixedDim = Color(0xFFC3C0FF);
  static const onPrimaryFixed = Color(0xFF0F0069);
  static const secondaryFixed = Color(0xFFDBE1FF);
  static const secondaryFixedDim = Color(0xFFB4C5FF);
  static const onSecondaryFixed = Color(0xFF00174B);
  static const tertiaryFixed = Color(0xFFFFDBCC);
  static const tertiaryFixedDim = Color(0xFFFFB695);
  static const background = Color(0xFFF9F9FF);
  static const onBackground = Color(0xFF141B2B);
  static const surfaceVariant = Color(0xFFDCE2F7);

  // ── Dark theme ─────────────────────────────────────────────────
  static const dSurface = Color(0xFF0F1119);
  static const dSurfaceDim = Color(0xFF0A0C12);
  static const dSurfaceBright = Color(0xFF1A1D29);
  static const dSurfaceContainerLowest = Color(0xFF0C0E15);
  static const dSurfaceContainerLow = Color(0xFF12141D);
  static const dSurfaceContainer = Color(0xFF181B26);
  static const dSurfaceContainerHigh = Color(0xFF1E2130);
  static const dSurfaceContainerHighest = Color(0xFF252839);
  static const dOnSurface = Color(0xFFE3E6F2);
  static const dOnSurfaceVariant = Color(0xFFB4B6C9);
  static const dInverseSurface = Color(0xFFEDF0FF);
  static const dInverseOnSurface = Color(0xFF293040);
  static const dOutline = Color(0xFF8D8FA4);
  static const dOutlineVariant = Color(0xFF3A3D4F);
  static const dPrimary = Color(0xFFC3C0FF);
  static const dOnPrimary = Color(0xFF12005E);
  static const dPrimaryContainer = Color(0xFF4F46E5);
  static const dOnPrimaryContainer = Color(0xFFDAD7FF);
  static const dInversePrimary = Color(0xFF3525CD);
  static const dSecondary = Color(0xFF9DBCFF);
  static const dOnSecondary = Color(0xFF00174B);
  static const dError = Color(0xFFFFB4AB);
  static const dOnError = Color(0xFF690005);
  static const dErrorContainer = Color(0xFF93000A);
  static const dOnErrorContainer = Color(0xFFFFDAD6);
  static const dBackground = Color(0xFF0F1119);
  static const dOnBackground = Color(0xFFE3E6F2);
  static const dSurfaceVariant = Color(0xFF252839);

  // ── Typography (Geist only) ────────────────────────────────────
  static const fontFamily = 'Geist';

  static const displayLg = TextStyle(
    fontFamily: fontFamily, fontSize: 56, fontWeight: FontWeight.w400,
    height: 1.1, letterSpacing: -1.68,
  );
  static const headlineXl = TextStyle(
    fontFamily: fontFamily, fontSize: 40, fontWeight: FontWeight.w500,
    height: 1.15, letterSpacing: -1.0,
  );
  static const headlineXlMobile = TextStyle(
    fontFamily: fontFamily, fontSize: 32, fontWeight: FontWeight.w500,
    height: 1.2, letterSpacing: -0.64,
  );
  static const headlineLg = TextStyle(
    fontFamily: fontFamily, fontSize: 28, fontWeight: FontWeight.w500,
    height: 1.25, letterSpacing: -0.56,
  );
  static const headlineSm = TextStyle(
    fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w600,
    height: 1.3, letterSpacing: -0.3,
  );
  static const bodyLg = TextStyle(
    fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w400,
    height: 1.6, letterSpacing: -0.18,
  );
  static const bodyMd = TextStyle(
    fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w400,
    height: 1.55, letterSpacing: -0.075,
  );
  static const bodySm = TextStyle(
    fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w400,
    height: 1.45, letterSpacing: 0,
  );
  static const labelMd = TextStyle(
    fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w500,
    height: 1.2, letterSpacing: 0,
  );
  static const labelSm = TextStyle(
    fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w600,
    height: 1.1, letterSpacing: 0.44,
  );

  // ── Spacing ────────────────────────────────────────────────────
  static const gutter = 20.0;      // 1.25rem
  static const gutterMobile = 12.0; // 0.75rem
  static const margin = 40.0;      // 2.5rem
  static const marginMobile = 16.0; // 1rem
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 16.0;
  static const spaceLg = 24.0;
  static const spaceXl = 40.0;

  // ── Radius (corrected: xl = 12px to match mockups) ─────────────
  static const radiusSm = 4.0;
  static const radiusDefault = 8.0;
  static const radiusMd = 8.0;
  static const radiusLg = 8.0;
  static const radiusXl = 12.0;
  static const radiusFull = 999.0;

  // ── Motion ─────────────────────────────────────────────────────
  static const durationInstant = Duration(milliseconds: 100);
  static const durationFast = Duration(milliseconds: 150);
  static const durationNormal = Duration(milliseconds: 200);
  static const durationSlow = Duration(milliseconds: 300);
  static const easingStandard = Cubic(0.2, 0, 0, 1);
  static const easingEmphasized = Cubic(0.3, 0, 0, 1);

  // ── Focus ──────────────────────────────────────────────────────
  static const focusRingWidth = 2.0;
  static const focusRingColor = Color(0xFF4F46E5);
  static const focusRingOffset = 2.0;

  // ── Elevation (halos are exceptional — transient layers only) ──
  static const haloDropdown = [
    BoxShadow(
      color: Color(0x0A111827), // rgba(17,24,39,0.04)
      blurRadius: 40, offset: Offset(0, 20), spreadRadius: -15,
    ),
  ];
  static const haloDialog = [
    BoxShadow(
      color: Color(0x14000000), // rgba(0,0,0,0.08)
      blurRadius: 60, offset: Offset(0, 30), spreadRadius: -20,
    ),
  ];

  // ── Presence ───────────────────────────────────────────────────
  static const presenceOnline = Color(0xFF0051D5);
  static const presenceIdle = Color(0xFFFFB695);
  static const presenceOffline = Color(0xFFC7C4D8);
  static const presenceSpeaking = Color(0xFF3525CD);

  // ── Breakpoints ────────────────────────────────────────────────
  static const breakpointMobile = 767.0;
  static const breakpointTablet = 1024.0;

  /// True for desktop-class layouts (> 1024px per DESIGN.md).
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width > breakpointTablet;
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width <= breakpointMobile;
}
