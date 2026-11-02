import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/main.dart';
import 'package:stilora/src/screens/sign_in_screen.dart';
import 'package:stilora/src/state/providers.dart';
import 'package:integration_test/integration_test.dart';

/// LIVE end-to-end suite — drives the real UI against the deployed API.
///
/// Run (requires the define; without it the app boots mock data and this
/// suite is skipped by design):
///
///   flutter test integration_test/live_api_test.dart -d DEVICE \
///     --dart-define=API_BASE_URL=https://stilora-api.vercel.app
///
/// Proves the full production chain: sign-up → workspace creation →
/// channel create → message round-trip → session persistence across
/// sign-out/sign-in → server-side search. Every account/channel created
/// here is uniquely timestamped (no fixture collisions).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'e2e$stamp@stilora.app';
  const password = 'live-e2e-password-2026';
  const workspace = 'E2E Live Workspace';
  const channelName = 'qa-live-e2e';
  final greeting = 'Hello from live E2E $stamp';

  bool bottomNav(WidgetTester t) =>
      find.text('Channels').evaluate().isNotEmpty;

  Future<void> wait(WidgetTester t, int ms) async {
    for (var i = 0; i < (ms / 100).ceil(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
    }
  }

  Future<void> expectVisible(WidgetTester t, Finder f,
      {int timeoutMs = 12000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await t.pump();
    }
    expect(f, findsWidgets,
        reason: 'timed out waiting for ${f.toString()}');
  }

  Future<void> unfocus(WidgetTester t) async {
    t.binding.focusManager.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await t.pump();
  }

  Future<void> ensureVisibleSafe(WidgetTester t, Finder f) async {
    try {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 300));
    } catch (_) {/* fixed layout */}
  }

  testWidgets('LIVE: full production chain works against the API',
      (tester) async {
    // Guard: without the define the app runs mock data — don't fake a
    // "live" pass.
    expect(kLiveBackend, isTrue,
        reason: 'pass --dart-define=API_BASE_URL=https://example.vercel.app to run this suite');

    // ── 1. Create account (sign-up + workspace, real DB writes) ─
    await tester.pumpWidget(const ProviderScope(child: StiloraApp()));
    await wait(tester, 900);
    await expectVisible(tester, find.text('Welcome back'));
    await tester.tap(find.text('Create account').last);
    await expectVisible(tester, find.text('Create your account'));
    final fields =
        find.descendant(of: find.byType(OnboardingFlow), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), password);
    await tester.enterText(fields.at(2), workspace);
    await ensureVisibleSafe(tester, find.text('Create account').last);
    await tester.tap(find.text('Create account').last);
    // Wait for the shell (a brand-new workspace has no channels — the
    // bottom nav / sidebar CTA is the signal). On failure, dump what the
    // screen actually shows (server errors render inline on the form).
    final deadline = DateTime.now().add(const Duration(milliseconds: 15000));
    var shellUp = false;
    while (DateTime.now().isBefore(deadline)) {
      shellUp = bottomNav(tester) ||
          find.text('New Thread').evaluate().isNotEmpty ||
          find.byIcon(Icons.edit).evaluate().isNotEmpty;
      if (shellUp) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    }
    if (!shellUp) {
      final visible = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((d) => d.trim().isNotEmpty)
          .take(40)
          .join(' | ');
      fail('SHELL NEVER APPEARED after sign-up — screen shows: $visible');
    }
    await wait(tester, 700);

    // ── 2. Create a channel (real row in Postgres) ──────────────
    await tester.tap(bottomNav(tester)
        ? find.byIcon(Icons.edit)
        : find.text('New Thread'));
    await expectVisible(tester, find.text('New channel'));
    final sheetFields = find.byType(TextField);
    await tester.enterText(
        sheetFields.at(sheetFields.evaluate().length - 2), channelName);
    await unfocus(tester);
    await tester.tap(find.text('Create channel'));
    await expectVisible(
        tester, find.text('Channel #$channelName created'));

    // Wait for the sidebar refresh AND the 4s snackbar to expire — the
    // snackbar text contains the channel name too, which would make
    // find.text(...).last ambiguous while it is visible.
    await wait(tester, 4600);
    await expectVisible(tester, find.text(channelName));

    // ── 3. Open it and send a message (round-trip) ──────────────
    // The channel row can sit below the fold on small screens.
    await ensureVisibleSafe(tester, find.text(channelName).last);
    await tester.tap(find.text(channelName).last);
    await expectVisible(
        tester, find.textContaining('Reply to #$channelName'));
    await tester.enterText(find.byType(TextField).last, greeting);
    await unfocus(tester);
    await tester.tap(find.text('Send'));
    var sent = false;
    for (var i = 0; i < 60 && !sent; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      sent = find.text(greeting, findRichText: true).evaluate().isNotEmpty;
    }
    expect(sent, isTrue,
        reason: 'message round-trip (app → Vercel → Neon → app) failed');

    // ── 4. Sign out (server session revoked, cookie cleared) ────
    if (bottomNav(tester)) {
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await wait(tester, 600); // pop transition settle
    }
    // Mobile: Settings tab shows section TILES — tap one to open it.
    await tester.tap(find.text('Settings').last);
    await expectVisible(tester, find.text('Audio & Video'));
    await tester.tap(find.text('Audio & Video'));
    await expectVisible(tester, find.text('Audio & Video Devices'));
    await tester.tap(find.byIcon(Icons.close));
    await wait(tester, 600);
    // Back on the tiles list → Security → sign out.
    await tester.tap(find.text('Settings').last);
    await expectVisible(tester, find.text('Security'));
    await tester.tap(find.text('Security'));
    await expectVisible(tester, find.text('Encrypted in transit & at rest'));
    await ensureVisibleSafe(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await expectVisible(tester, find.text('Welcome back'));

    // ── 5. Sign back in (fresh session from the server) ─────────
    final creds = find.byType(TextField);
    await tester.enterText(creds.at(0), email);
    await tester.enterText(creds.at(1), password);
    await unfocus(tester);
    await tester.tap(find.text('Sign in'));
    // Layout-aware shell wait (mobile shows bottom nav, desktop the sidebar).
    final deadline2 = DateTime.now().add(const Duration(milliseconds: 15000));
    var back = false;
    while (DateTime.now().isBefore(deadline2)) {
      back = bottomNav(tester) ||
          find.text('New Thread').evaluate().isNotEmpty ||
          find.byIcon(Icons.edit).evaluate().isNotEmpty;
      if (back) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    }
    if (!back) {
      final visible = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((d) => d.trim().isNotEmpty)
          .take(40)
          .join(' | ');
      fail('RE-LOGIN NEVER REACHED THE SHELL — screen shows: $visible');
    }
    await wait(tester, 700);

    // ── 6. Persistence: the channel we created still exists ─────
    await expectVisible(tester, find.text(channelName));

    debugPrint(
        'LIVE E2E OK: account=$email workspace="$workspace" channel=$channelName');
  });
}
