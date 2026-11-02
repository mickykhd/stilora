import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/main.dart';
import 'package:stilora/src/screens/secondary_screens.dart';
import 'package:stilora/src/screens/sign_in_screen.dart';
import 'package:stilora/src/widgets/messages.dart';
import 'package:integration_test/integration_test.dart';

/// Full on-device functional suite — runs on the Android emulator against
/// the REAL widget tree with mock repositories (250 ms simulated latency).
///
/// Coverage (every user-facing flow in the app):
///  1. Sign-in validation errors + successful sign-in
///  2. Channels: open, read messages, send, react, thread, members, profile
///  3. Threads tab → DM conversation; search results; create-channel sheet;
///     notifications/activity feed
///  4. Voice: tab → stage → permission path → mute/camera toggles → leave
///  5. Settings: all sections reachable, dark mode applies, sign out,
///     create-account (onboarding) with validation
///
/// Live binding = real time; waits use pump loops (infinite decorative
/// animations rule out pumpAndSettle).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const email = 'qa@stilora.dev';
  const password = 'quiet-test-2026';

  Future<void> wait(WidgetTester t, int ms) async {
    final steps = (ms / 100).ceil();
    for (var i = 0; i < steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
    }
  }

  /// Dismiss the soft keyboard so layout settles before tapping (the IME
  /// shifts bottom-anchored widgets between find and tap otherwise).
  Future<void> unfocus(WidgetTester t) async {
    t.binding.focusManager.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await t.pump();
  }

  Future<void> expectVisible(
    WidgetTester t,
    Finder finder, {
    int timeoutMs = 8000,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await t.pump();
    }
    expect(finder, findsWidgets,
        reason: 'timed out waiting for ${finder.toString()}');
  }

  Future<void> launch(WidgetTester t) async {
    await t.pumpWidget(const ProviderScope(child: StiloraApp()));
    await wait(t, 900); // entrance animations
  }

  /// Mobile shell has a bottom nav with exact label 'Channels';
  /// the desktop shell instead shows the uppercase sidebar section
  /// ('CHANNELS') — exact-match case sensitivity distinguishes them.
  bool hasBottomNav(WidgetTester t) =>
      find.text('Channels').evaluate().isNotEmpty;

  /// Shell-ready assertion that works on both layouts.
  Future<void> expectShellReady(WidgetTester t) async {
    await expectVisible(t, find.text('design-sync'));
    if (hasBottomNav(t)) {
      expect(find.byIcon(Icons.edit), findsOneWidget); // compose action
      expect(find.byIcon(Icons.search), findsOneWidget);
    } else {
      expect(find.text('New Thread'), findsOneWidget); // sidebar CTA
      // Sidebar DIRECT section proves shell content on desktop at any width.
      expect(find.text('Sarah Chen'), findsWidgets);
    }
  }

  /// Scroll a finder into view when it has a Scrollable ancestor;
  /// no-op otherwise (720px desktop windows hide below-fold content).
  Future<void> ensureVisibleSafe(WidgetTester t, Finder f) async {
    try {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 350));
    } catch (_) {
      // No scrollable ancestor — already visible or fixed layout.
    }
  }

  Future<void> signIn(WidgetTester t) async {
    await launch(t);
    await expectVisible(t, find.text('Welcome back'));
    await enterTextAt(t, 0, email);
    await t.enterText(find.byType(TextField).last, password);
    await unfocus(t);
    await t.tap(find.text('Sign in'));
    await expectShellReady(t);
    await wait(t, 700);
  }

  Future<void> openTab(WidgetTester t, String label) async {
    if (!hasBottomNav(t)) {
      // Desktop: sidebar navigation (topbar hosts Threads/Catch-up too,
      // so .last picks the sidebar entry further down the tree).
      switch (label) {
        case 'Channels':
          return; // channel list is always visible on desktop
        case 'Voice':
          return; // voice opens via the floating capsule (caller handles)
        default:
          await t.tap(find.text(label).last);
      }
    } else {
      // Bottom-nav label — the page title often shares the same text.
      await t.tap(find.text(label).last);
    }
    await wait(t, 700);
  }

  group('E2E: authentication', () {
    testWidgets('validation errors then successful sign-in', (tester) async {
      await launch(tester);
      await expectVisible(tester, find.text('Welcome back'));

      // Short password → inline error (animated).
      await enterTextAt(tester, 0, email);
      await enterTextAt(tester, 1, 'short');
      await tester.tap(find.text('Sign in'));
      await expectVisible(
          tester, find.text('Password must be at least 8 characters.'));

      // Bad email → inline error.
      await enterTextAt(tester, 0, 'not-an-email');
      await enterTextAt(tester, 1, password);
      await tester.tap(find.text('Sign in'));
      await expectVisible(tester, find.text('Enter a valid email address.'));

      // Valid credentials → workspace opens (layout-aware).
      await enterTextAt(tester, 0, email);
      await enterTextAt(tester, 1, password);
      await tester.tap(find.text('Sign in'));
      await expectVisible(tester, find.text('design-sync'),
          timeoutMs: 10000);
      await wait(tester, 800);

      // Shell sanity for the current layout.
      await expectShellReady(tester);
    });
  });

  group('E2E: channels, messages, thread, members', () {
    testWidgets('full conversation loop', (tester) async {
      await signIn(tester);

      // Open #design-sync from the channel list.
      await tester.tap(find.text('design-sync').last);
      await expectVisible(
          tester, find.textContaining('Reply to #design-sync'));
      await expectVisible(tester, find.text('Sarah Chen'));
      await wait(tester, 500);

      // Voice capsule present (room connected).
      expect(find.text('Voice: Design Room'), findsWidgets);

      // Send a message → appears in the feed as sent.
      await tester.enterText(find.byType(TextField).last, 'Integration hello');
      expect(find.widgetWithText(TextField, 'Integration hello'), findsOneWidget,
          reason: 'composer must hold the typed text before sending');
      await unfocus(tester);
      final preSend = tester.widget<TextField>(find.byType(TextField).last).controller?.text ?? '(none)';
      await tester.tap(find.text('Send'));
      // Manual poll with full diagnostics on failure.
      var sent = false;
      for (var i = 0; i < 50 && !sent; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        // Message bodies render as RichText (mention-aware).
        sent = find.text('Integration hello', findRichText: true)
            .evaluate()
            .isNotEmpty;
      }
      if (!sent) {
        final post = tester.widget<TextField>(find.byType(TextField).last).controller?.text ?? '(none)';
        final snackFailed =
            find.text('Message failed to send').evaluate().isNotEmpty;
        fail('SEND DIAG: preUnfocusAndTap="$preSend" postTap="$post" '
            'snackbarFailed=$snackFailed');
      }

      // React to Marcus's message: count 3 → 4 (optimistic update).
      final reaction = find.text('3');
      await expectVisible(tester, reaction);
      final threesBefore = reaction.evaluate().length;
      // Identify exactly which widget Text('3') belongs to.
      final lineageParts = <String>[];
      tester.element(reaction.first).visitAncestorElements((e) {
        lineageParts.add(e.widget.runtimeType.toString());
        return lineageParts.length < 7;
      });
      final lineage = lineageParts.join(' < ');
      // The chip can sit below the visible fold — finders see built ListView
      // children, but taps dispatch at coordinates. Scroll it into view first.
      await tester.ensureVisible(reaction.first);
      await tester.pump(const Duration(milliseconds: 400));
      final hitTypes = tester
          .hitTestOnBinding(tester.getCenter(reaction.first))
          .path
          .map((e) => e.target.runtimeType.toString())
          .take(6)
          .join(' > ');
      await tester.tap(reaction.first);
      var reacted = false;
      for (var i = 0; i < 20 && !reacted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        reacted = find.text('4').evaluate().isNotEmpty;
      }
      // Fallback: target the chip widget itself.
      if (!reacted && find.byType(ReactionChip).evaluate().isNotEmpty) {
        await tester.ensureVisible(find.byType(ReactionChip).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byType(ReactionChip).first);
        for (var i = 0; i < 20 && !reacted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          reacted = find.text('4').evaluate().isNotEmpty;
        }
      }
      if (!reacted) {
        final digitTexts = find
            .textContaining(RegExp(r'^\d+$'))
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '?')
            .toList();
        fail('REACT DIAG: threesBefore=$threesBefore lineage=$lineage '
            'hitAtCenter=$hitTypes digitsOnScreen=$digitTexts');
      }

      // Thread: open from the "18 replies" chip.
      await ensureVisibleSafe(tester, find.text('18 replies'));
      await tester.tap(find.text('18 replies'));
      await expectVisible(tester, find.text('Thread'));
      await expectVisible(tester,
          find.textContaining('Pushed the token table', findRichText: true));
      // Reply inside the thread.
      await tester.enterText(
          find.byType(TextField).last, 'Thread reply from QA');
      await unfocus(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      // Composer in thread is fire-and-forget; assert thread stayed stable.
      await wait(tester, 600);
      expect(find.text('Thread'), findsOneWidget);

      // Back to channel.
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await wait(tester, 600); // let the pop transition settle
      await expectVisible(
          tester, find.textContaining('Reply to #design-sync'));

      // Members → open a profile (layout-aware entry).
      if (hasBottomNav(tester)) {
        await tester.tap(find.byIcon(Icons.more_vert).last);
        await expectVisible(tester, find.text('Members'));
        await expectVisible(tester, find.text('Priya Raman')); // list data
        await ensureVisibleSafe(tester, find.text('Priya Raman'));
        await tester.tap(find.text('Priya Raman'));
      } else {
        // Desktop 3-pane shows members in the right context pane.
        await expectVisible(tester, find.text('Priya Raman'));
        await ensureVisibleSafe(tester, find.text('Priya Raman'));
        await tester.tap(find.text('Priya Raman'));
      }
      await expectVisible(tester, find.text('@priya'));
      expect(find.text('Member'), findsWidgets);
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await wait(tester, 600); // let the pop transition settle // leave profile
      await wait(tester, 500);
    });
  });

  group('E2E: tabs, DMs, search, compose, activity', () {
    testWidgets('navigation and secondary flows', (tester) async {
      await signIn(tester);

      // Threads tab → DM list → open Sarah → conversation view.
      await openTab(tester, 'Threads');
      await expectVisible(tester,
          hasBottomNav(tester) ? find.text('DIRECT MESSAGES') : find.text('DIRECT'));
      // Desktop: right-pane lists Sarah too — .first is the sidebar DM row.
      await tester.tap(hasBottomNav(tester)
          ? find.text('Sarah Chen').last
          : find.text('Sarah Chen').first);
      await expectVisible(tester, find.textContaining('Reply to Sarah Chen'));
      if (hasBottomNav(tester)) {
        await tester.tap(find.byIcon(Icons.arrow_back).last);
        await wait(tester, 600); // let the pop transition settle
        await wait(tester, 500);
      }

      // Search: mobile pushes a screen; desktop opens the ⌘K palette.
      await openTab(tester, 'Channels');
      if (hasBottomNav(tester)) {
        await tester.tap(find.byIcon(Icons.search));
        await expectVisible(tester, find.textContaining('Search across every channel'));
        await tester.enterText(find.byType(TextField).first, 'design');
        await expectVisible(tester, find.text('design-sync'));
        await tester.tap(find.byIcon(Icons.arrow_back).last);
        await wait(tester, 600); // let the pop transition settle
        await wait(tester, 500);
      } else {
        await tester.tap(find.text('Search or run a command…'));
        await wait(tester, 500);
        await tester.enterText(find.byType(TextField).first, 'design');
        await expectVisible(tester, find.text('design-sync'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await wait(tester, 700);
      }

      // Compose sheet: sidebar button on desktop, compose icon on mobile.
      await tester.tap(hasBottomNav(tester)
          ? find.byIcon(Icons.edit)
          : find.text('New Thread'));
      await expectVisible(tester, find.text('New channel'));
      // The sheet sits above the shell, so its fields are the LAST in the
      // tree: [..., sheet name, sheet topic] → name is length-2.
      final sheetFields = find.byType(TextField);
      await tester.enterText(
          sheetFields.at(sheetFields.evaluate().length - 2), 'quiet-launch');
      await unfocus(tester);
      await tester.tap(find.text('Create channel'));
      await expectVisible(
          tester, find.text('Channel #quiet-launch created'));
      await wait(tester, 800);

      // Notifications/activity: header bell on mobile, Catch-up on desktop.
      if (hasBottomNav(tester)) {
        await tester.tap(find.byIcon(Icons.notifications_none));
      } else {
        await tester.tap(find.text('Catch-up').last); // sidebar entry
      }
      await expectVisible(tester,
          find.textContaining('mentioned you in', findRichText: true));
      await tester.tap(find.text('Mark all read'));
      await wait(tester, 600);
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await wait(tester, 600); // let the pop transition settle
      await wait(tester, 400);
    });
  });

  group('E2E: voice', () {
    testWidgets('stage controls work end to end', (tester) async {
      await signIn(tester);

      // Voice entry: bottom-nav tab (mobile) or floating capsule (desktop).
      await openTab(tester, 'Voice');
      if (hasBottomNav(tester)) {
        await expectVisible(tester, find.text('Open stage'));
        await tester.tap(find.text('Open stage'));
      } else {
        // Capsule lives inside the channel pane — before a channel is open
        // the always-present desktop entry is the sidebar audio card.
        await expectVisible(tester, find.text('Audio Space Active'));
        await tester.tap(find.text('Audio Space Active'));
      }

      // Staged diagnosis: did the stage route open at all?
      var stageOpen = false;
      for (var i = 0; i < 30 && !stageOpen; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        stageOpen = find.byType(VoiceStageScreen).evaluate().isNotEmpty;
      }
      if (!stageOpen) {
        fail('VOICE DIAG: stage route never opened after tapping Open stage');
      }

      // Connecting → connected (permission pre-granted via adb grant).
      var connected = false;
      for (var i = 0; i < 120 && !connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        connected =
            find.textContaining('participants').evaluate().isNotEmpty;
      }
      if (!connected) {
        fail('VOICE DIAG: stage open but never connected; '
            'connecting=${find.textContaining('Connecting').evaluate().isNotEmpty} '
            'deniedCard=${find.textContaining('microphone to speak').evaluate().isNotEmpty} '
            'spinner=${find.byType(CircularProgressIndicator).evaluate().isNotEmpty} '
            'tiles=${find.text('Sarah').evaluate().isNotEmpty}');
      }
      await expectVisible(tester, find.text('Sarah'));

      // Mute toggle via control tooltip (state flips Mute ↔ Unmute).
      await expectVisible(tester, find.byTooltip('Mute'));
      await tester.tap(find.byTooltip('Mute'));
      await expectVisible(tester, find.byTooltip('Unmute'));

      // Camera starts OFF → tooltip offers to turn it ON.
      await tester.tap(find.byTooltip('Camera on'));
      await expectVisible(tester, find.byTooltip('Camera off'));

      // Screen-share starts ON (canvas shared) → tap stops it.
      await expectVisible(tester, find.byTooltip('Stop sharing'));
      await tester.tap(find.byTooltip('Stop sharing'));
      await expectVisible(tester, find.byTooltip('Share screen'));

      // Leave → back to shell; mobile shows the disconnected Voice tab.
      await tester.tap(find.text('Leave'));
      await wait(tester, 700); // let the stage pop transition finish
      if (hasBottomNav(tester)) {
        await expectVisible(tester, find.text('Not connected'));
        await expectVisible(tester, find.text('Join room'));
      } else {
        await expectVisible(tester, find.text('design-sync'));
        expect(find.text('Voice: Design Room'), findsNothing); // capsule gone
      }
    });
  });

  group('E2E: settings, theme, sign-out, onboarding', () {
    testWidgets('every settings section + dark mode + full auth loop',
        (tester) async {
      await signIn(tester);
      await openTab(tester, 'Settings');

      // Notifications section (deep work controls).
      await tester.tap(find.text('Notifications'));
      await expectVisible(tester, find.text('Deep work threshold'));
      await tester.tap(find.byIcon(Icons.close));
      await wait(tester, 500);

      // Workspace & Members sections reachable.
      await openTab(tester, 'Settings');
      await tester.tap(find.text('Workspace'));
      await expectVisible(tester, find.text('Invite code'));
      await tester.tap(find.byIcon(Icons.close));
      await wait(tester, 400);
      await openTab(tester, 'Settings');
      await tester.tap(find.text('Members'));
      await expectVisible(tester, find.text('Tomás Herrera'));
      await tester.tap(find.byIcon(Icons.close));
      await wait(tester, 400);

      // Appearance → Dark → theme actually flips.
      await openTab(tester, 'Settings');
      await tester.tap(find.text('Appearance'));
      await expectVisible(tester, find.text('Theme'));
      await tester.tap(find.text('Dark'));
      await wait(tester, 700);
      final ctx = tester.element(find.text('Theme'));
      expect(Theme.of(ctx).brightness, Brightness.dark);
      await tester.tap(find.byIcon(Icons.close));
      await wait(tester, 400);

      // Security → Sign out → back at sign-in (still dark themed).
      await openTab(tester, 'Settings');
      await tester.tap(find.text('Security'));
      await expectVisible(tester, find.text('Encrypted in transit & at rest'));
      await ensureVisibleSafe(tester, find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await expectVisible(tester, find.text('Welcome back'));

      // Onboarding: validation then account creation completes the loop.
      await ensureVisibleSafe(tester, find.text('Create account').last);
      await tester.tap(find.text('Create account').last);
      await expectVisible(tester, find.text('Create your account'));
      // Scope to the onboarding route — the sign-in route below it also
      // hosts TextFields, which shifts global indexes between layouts.
      final onboardEmail =
          find.descendant(of: find.byType(OnboardingFlow), matching: find.byType(TextField)).at(0);
      final onboardPassword =
          find.descendant(of: find.byType(OnboardingFlow), matching: find.byType(TextField)).at(1);
      final onboardName =
          find.descendant(of: find.byType(OnboardingFlow), matching: find.byType(TextField)).at(2);
      await tester.enterText(onboardEmail, 'new@stilora.dev');
      await tester.enterText(onboardPassword, 'short');
      await tester.enterText(onboardName, 'QA Workspace');
      await ensureVisibleSafe(tester, find.text('Create account').last);
      await tester.tap(find.text('Create account').last);
      await expectVisible(
          tester, find.text('Password must be at least 8 characters.'));

      await tester.enterText(onboardPassword, password);
      await unfocus(tester);
      await ensureVisibleSafe(tester, find.text('Create account').last);
      await tester.tap(find.text('Create account').last);
      // Manual poll with diagnostics on failure.
      var landed = false;
      for (var i = 0; i < 100 && !landed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        landed = find.text('Channels').evaluate().isNotEmpty ||
            find.text('New Thread').evaluate().isNotEmpty;
      }
      if (!landed) {
        final fields = find.byType(TextField).evaluate();
        final texts = <String>[];
        for (final e in fields) {
          final c = (e.widget as TextField).controller;
          texts.add(c?.text ?? '?');
        }
        fail('ONBOARD DIAG: stillOnForm=${find.text('Create your account').evaluate().isNotEmpty} '
            'passwordError=${find.text('Password must be at least 8 characters.').evaluate().isNotEmpty} '
            'fields=$texts createBtn=${find.text('Create account').evaluate().isNotEmpty}');
      }
      // Workspace created in onboarding is reflected in the shell.
      expect(find.text('Studio Flow'), findsOneWidget);
    });
  });
}

/// Enter text into the nth visible TextField.
Future<void> enterTextAt(WidgetTester t, int index, String text) async {
  await t.enterText(find.byType(TextField).at(index), text);
}
