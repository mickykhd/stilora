import 'package:flutter/material.dart';

import 'tokens.dart';

/// Stilora theme factory — light & dark, built strictly from [Aura] tokens.
abstract final class AuraTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? Aura.dPrimary : Aura.primary,
      onPrimary: isDark ? Aura.dOnPrimary : Aura.onPrimary,
      primaryContainer: isDark ? Aura.dPrimaryContainer : Aura.primaryContainer,
      onPrimaryContainer:
          isDark ? Aura.dOnPrimaryContainer : Aura.onPrimaryContainer,
      secondary: isDark ? Aura.dSecondary : Aura.secondary,
      onSecondary: isDark ? Aura.dOnSecondary : Aura.onSecondary,
      secondaryContainer:
          isDark ? Aura.dSurfaceContainerHigh : Aura.secondaryContainer,
      onSecondaryContainer: isDark
          ? Aura.dOnSurface
          : Aura.onSecondaryContainer,
      tertiary: isDark ? Aura.tertiaryFixedDim : Aura.tertiary,
      onTertiary: isDark ? Aura.onTertiary : Aura.onTertiary,
      tertiaryContainer:
          isDark ? Aura.dSurfaceContainerHigh : Aura.tertiaryContainer,
      onTertiaryContainer: isDark
          ? Aura.dOnSurface
          : Aura.onTertiaryContainer,
      error: isDark ? Aura.dError : Aura.error,
      onError: isDark ? Aura.dOnError : Aura.onError,
      errorContainer: isDark ? Aura.dErrorContainer : Aura.errorContainer,
      onErrorContainer:
          isDark ? Aura.dOnErrorContainer : Aura.onErrorContainer,
      surface: isDark ? Aura.dSurface : Aura.surface,
      onSurface: isDark ? Aura.dOnSurface : Aura.onSurface,
      onSurfaceVariant:
          isDark ? Aura.dOnSurfaceVariant : Aura.onSurfaceVariant,
      surfaceContainerHighest: isDark
          ? Aura.dSurfaceContainerHighest
          : Aura.surfaceContainerHighest,
      surfaceContainerHigh:
          isDark ? Aura.dSurfaceContainerHigh : Aura.surfaceContainerHigh,
      surfaceContainer:
          isDark ? Aura.dSurfaceContainer : Aura.surfaceContainer,
      surfaceContainerLow:
          isDark ? Aura.dSurfaceContainerLow : Aura.surfaceContainerLow,
      surfaceContainerLowest: isDark
          ? Aura.dSurfaceContainerLowest
          : Aura.surfaceContainerLowest,
      outline: isDark ? Aura.dOutline : Aura.outline,
      outlineVariant: isDark ? Aura.dOutlineVariant : Aura.outlineVariant,
      shadow: const Color(0xFF000000),
      scrim: const Color(0x66000000),
      inverseSurface: isDark ? Aura.dInverseSurface : Aura.inverseSurface,
      onInverseSurface:
          isDark ? Aura.dInverseOnSurface : Aura.inverseOnSurface,
      inversePrimary: isDark ? Aura.dInversePrimary : Aura.inversePrimary,
    );

    final baseText = ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: Aura.fontFamily,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: baseText,
      splashFactory: InkSparkle.splashFactory,
      // No drop shadows anywhere except transient floating layers:
      // elevated cards use tonal layering + borders instead (see AuraCard).
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Aura.radiusXl),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Aura.radiusXl),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Aura.dSurfaceContainerLow : Aura.surfaceContainerLow,
        hintStyle: baseText.bodyMedium?.copyWith(color: scheme.outline),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Aura.spaceSm, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Aura.radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Aura.radiusLg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Aura.radiusLg),
          borderSide: const BorderSide(color: Aura.focusRingColor, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? Aura.dPrimaryContainer : Aura.primaryContainer,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(44, 44), // ≥44px touch target
          padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
          textStyle: Aura.labelMd,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Aura.radiusLg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 44),
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
          textStyle: Aura.labelMd,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Aura.radiusLg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(44, 44),
          textStyle: Aura.labelMd,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size(44, 44), // 44px hit area (visual 32px ok)
          padding: EdgeInsets.zero,
        ),
      ),
      // Focus-visible ring on every interactive element (DESIGN.md a11y).
      focusColor: Aura.focusRingColor.withValues(alpha: 0.25),
      hoverColor: Aura.focusRingColor.withValues(alpha: 0.08),
      highlightColor: Aura.focusRingColor.withValues(alpha: 0.12),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 0.5,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.outline,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Aura.spaceSm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            baseText.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Aura.radiusLg),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? Aura.dPrimary : Aura.primaryContainer,
      ),
    );
  }
}

/// Builds a focus ring decoration matching the `focus` tokens.
/// Applied via Focus widgets on custom interactive components.
BoxDecoration focusRingDecoration(bool focused) => BoxDecoration(
      borderRadius: BorderRadius.circular(Aura.radiusLg),
      border: Border.all(
        color: focused ? Aura.focusRingColor : Colors.transparent,
        width: Aura.focusRingWidth,
      ),
    );
