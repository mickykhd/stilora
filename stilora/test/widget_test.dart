import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stilora/main.dart';
import 'package:stilora/src/state/providers.dart';

void main() {
  testWidgets('Stilora boots to the email + password sign-in screen',
      (tester) async {
    // No persisted session → sign-in. (The platform path_provider channel
    // never answers under the test binding, so the boot restore is faked.)
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRestoreProvider.overrideWith((ref) async => false)],
      child: const StiloraApp(),
    ));
    // Let entrance animations' delayed starts fire and complete.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Welcome back'), findsWidgets);
    expect(find.text('Stilora'), findsWidgets);
    expect(find.text('EMAIL'), findsWidgets);
    expect(find.text('PASSWORD'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
    // No third-party auth anywhere.
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
  });

  testWidgets('Stilora restores a persisted session straight to the shell',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRestoreProvider.overrideWith((ref) async => true)],
      child: const StiloraApp(),
    ));
    // Allow the boot crossfade to complete.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('shell')), findsOneWidget);
    expect(find.byKey(const ValueKey('signin')), findsNothing);
  });
}
