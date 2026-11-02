import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'src/screens/sign_in_screen.dart';
import 'src/screens/workspace_shell.dart';
import 'src/state/providers.dart';
import 'src/theme/aura_theme.dart';
import 'src/theme/tokens.dart';

/// Stilora — a calm, focused communication workspace.
///
/// Sentry boots only when SENTRY_DSN is provided at build time:
///   flutter run --dart-define=SENTRY_DSN=...
/// With no DSN (default, and required for the OSS zero-cost path) the
/// app runs entirely without third-party telemetry.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (sentryDsn.isEmpty) {
    runApp(const ProviderScope(child: StiloraApp()));
  } else {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment = 'production';
      },
      appRunner: () => runApp(const ProviderScope(child: StiloraApp())),
    );
  }
}

class StiloraApp extends ConsumerWidget {
  const StiloraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Stilora',
      debugShowCheckedModeBanner: false,
      theme: AuraTheme.light(),
      darkTheme: AuraTheme.dark(),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const _AuthGate(),
    );
  }
}

/// Crossfades between sign-in → workspace so the auth transition feels
/// continuous (no jarring screen swaps).
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInProvider);

    final child = signedIn
        ? const WorkspaceShell(key: ValueKey('shell'))
        : const SignInScreen(key: ValueKey('signin'));

    // Global auth crossfade lives in AnimatedSwitcher below.
    return AnimatedSwitcher(
      duration: Aura.durationNormal,
      switchInCurve: Aura.easingEmphasized,
      switchOutCurve: Aura.easingStandard,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.995, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
