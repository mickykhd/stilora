import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:stilora/src/data/mock_data.dart';
import 'package:stilora/src/data/repositories.dart';
import 'package:stilora/src/screens/secondary_screens.dart';
import 'package:stilora/src/screens/settings_screens.dart';
import 'package:stilora/src/screens/sign_in_screen.dart';
import 'package:stilora/src/screens/workspace_shell.dart';
import 'package:stilora/src/state/providers.dart';
import 'package:stilora/src/theme/aura_theme.dart';
import 'package:stilora/src/widgets/navigation.dart';

/// Golden suite — DESIGN.md parity enforcement (strict policy).
///
/// Screens rendered at 3 breakpoints × 2 themes. CI fails on any pixel
/// drift from the design tokens. Regenerate deliberately with:
///   flutter test --update-goldens test/goldens
///
/// Animation note: system "reduce motion" is enabled during capture so
/// entrance animations resolve instantly and repeating pulses hold a
/// deterministic frame — goldens stay stable across runs.
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Widget child,
    required double width,
    required double height,
    bool dark = false,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        workspaceRepositoryProvider
            .overrideWith((ref) => MockWorkspaceRepository(latency: Duration.zero)),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AuraTheme.light(),
        darkTheme: AuraTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        // Reduced motion: entrances resolve instantly, pulses hold a
        // deterministic frame — stable goldens across runs.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: child,
      ),
    ));
    // Fire delayed entrance starts, then let controllers complete.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Sizes: mobile 390×844, tablet 834×1112, desktop 1440×900.
  const mobile = (390.0, 844.0);
  const tablet = (834.0, 1112.0);
  const desktop = (1440.0, 900.0);

  group('Sign-in', () {
    for (final (label, size) in [
      ('mobile', mobile),
      ('desktop', desktop),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('renders on $label ${dark ? 'dark' : 'light'}',
            (tester) async {
          await pumpScreen(tester,
              child: const SignInScreen(),
              width: size.$1,
              height: size.$2,
              dark: dark);
          await expectLater(
            find.byType(SignInScreen),
            matchesGoldenFile('goldens/sign_in_${label}_${dark ? 'dark' : 'light'}.png'),
          );
        });
      }
    }
  });

  group('Workspace shell', () {
    final seededChannel = [
      activeChannelProvider.overrideWith((ref) => MockData.channels[1]),
    ];

    for (final (label, size) in [
      ('mobile', mobile),
      ('tablet', tablet),
      ('desktop', desktop),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('renders on $label ${dark ? 'dark' : 'light'}',
            (tester) async {
          await pumpScreen(tester,
              child: const WorkspaceShell(),
              width: size.$1,
              height: size.$2,
              dark: dark,
              overrides: seededChannel);
          await expectLater(
            find.byType(WorkspaceShell),
            matchesGoldenFile(
                'goldens/shell_${label}_${dark ? 'dark' : 'light'}.png'),
          );
        });
      }
    }
  });

  group('Voice stage', () {
    for (final (label, size) in [
      ('mobile', mobile),
      ('desktop', desktop),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('renders on $label ${dark ? 'dark' : 'light'}',
            (tester) async {
          await pumpScreen(tester,
              child: const VoiceStageScreen(),
              width: size.$1,
              height: size.$2,
              dark: dark);
          // Fake-time flush: permission checks use timeout fallbacks whose
          // timers must resolve before capture (instant in fake clock).
          await tester.pump(const Duration(seconds: 15));
          await expectLater(
            find.byType(VoiceStageScreen),
            matchesGoldenFile(
                'goldens/voice_${label}_${dark ? 'dark' : 'light'}.png'),
          );
          // Unmount, then flush any orphaned permission-delay timers.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 15));
        });
      }
    }
  });

  group('Settings', () {
    for (final (label, size) in [
      ('mobile', mobile),
      ('desktop', desktop),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('renders on $label ${dark ? 'dark' : 'light'}',
            (tester) async {
          await pumpScreen(tester,
              child: const SettingsScreen(),
              width: size.$1,
              height: size.$2,
              dark: dark);
          await expectLater(
            find.byType(SettingsScreen),
            matchesGoldenFile(
                'goldens/settings_${label}_${dark ? 'dark' : 'light'}.png'),
          );
        });
      }
    }
  });

  group('Activity + Search + Thread', () {
    for (final dark in [false, true]) {
      testWidgets('activity renders ${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpScreen(tester,
            child: const ActivityScreen(),
            width: mobile.$1,
            height: mobile.$2,
            dark: dark);
        await expectLater(
          find.byType(ActivityScreen),
          matchesGoldenFile('goldens/activity_${dark ? 'dark' : 'light'}.png'),
        );
      });

      testWidgets('search results render ${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpScreen(tester,
            child: const SearchScreen(),
            width: mobile.$1,
            height: mobile.$2,
            dark: dark);
        await tester.enterText(find.byType(TextField), 'design');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await expectLater(
          find.byType(SearchScreen),
          matchesGoldenFile('goldens/search_${dark ? 'dark' : 'light'}.png'),
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1200));
      });

      testWidgets('thread renders ${dark ? 'dark' : 'light'}',
          (tester) async {
        await pumpScreen(
          tester,
          child: ThreadScreen(root: MockData.designSyncMessages.first),
          width: desktop.$1,
          height: desktop.$2,
          dark: dark,
        );
        await expectLater(
          find.byType(ThreadScreen),
          matchesGoldenFile('goldens/thread_${dark ? 'dark' : 'light'}.png'),
        );
      });
    }
  });

  group('Command palette', () {
    for (final dark in [false, true]) {
      testWidgets('open palette ${dark ? 'dark' : 'light'}', (tester) async {
        await pumpScreen(tester,
            child: const WorkspaceShell(),
            width: desktop.$1,
            height: desktop.$2,
            dark: dark);
        CommandPalette.show(tester.element(find.byType(WorkspaceShell)));
        await tester.pumpAndSettle(const Duration(milliseconds: 40));
        await expectLater(
          find.byType(CommandPalette),
          matchesGoldenFile('goldens/palette_${dark ? 'dark' : 'light'}.png'),
        );
        final ctx = tester.element(find.byType(CommandPalette));
        CommandPalette.hide(ctx);
        await tester.pump(const Duration(milliseconds: 400));
      });
    }
  });
}
