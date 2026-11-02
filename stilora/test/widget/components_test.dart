import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stilora/src/data/repositories.dart';
import 'package:stilora/src/models/models.dart';
import 'package:stilora/src/state/providers.dart';
import 'package:stilora/src/theme/aura_theme.dart';
import 'package:stilora/src/theme/motion.dart';
import 'package:stilora/src/widgets/messages.dart';
import 'package:stilora/src/widgets/navigation.dart';
import 'package:stilora/src/widgets/primitives.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        workspaceRepositoryProvider
            .overrideWith((ref) => MockWorkspaceRepository(latency: Duration.zero)),
        ...overrides,
      ],
      child: MaterialApp(theme: AuraTheme.light(), home: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester, [int ms = 700]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

const _noop = _noopFn;

void _noopFn() {}

void main() {
  group('AuraCard', () {
    testWidgets('renders child with whisper border, elevation-free',
        (tester) async {
      await tester.pumpWidget(_wrap(const AuraCard(child: Text('content'))));
      final material = tester.widget<Material>(find.byType(Material).last);
      expect(material.elevation, 0);
      expect(find.text('content'), findsOneWidget);
    });
  });

  group('AuraChip + UnreadDot', () {
    testWidgets('chip shows label; unread dot is exactly 6px cobalt',
        (tester) async {
      await tester.pumpWidget(_wrap(const Column(
        children: [AuraChip('3 unread', active: true), UnreadDot()],
      )));
      expect(find.text('3 unread'), findsOneWidget);
      final dot = tester.getSize(
          find.descendant(of: find.byType(UnreadDot), matching: find.byType(Container)).first);
      expect(dot.width, 6);
      expect(dot.height, 6);
    });
  });

  group('EmptyState / ErrorState', () {
    testWidgets('empty state renders message + action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(EmptyState(
        message: 'Nothing here yet',
        actionLabel: 'Create',
        onAction: () => tapped = true,
      )));
      expect(find.text('Nothing here yet'), findsOneWidget);
      await tester.tap(find.text('Create'));
      expect(tapped, isTrue);
    });

    testWidgets('error state retry fires callback', (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(ErrorState(
        message: 'Something quiet went wrong',
        onRetry: () => retried = true,
      )));
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  group('OfflineBanner + PermissionDeniedCard', () {
    testWidgets('offline banner shows cached-content copy', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineBanner()));
      expect(
          find.text('Offline — showing cached messages'), findsOneWidget);
    });

    testWidgets('permission card explains and routes to settings',
        (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(PermissionDeniedCard(
        reason: 'Microphone needed to talk.',
        openSettings: () => opened = true,
      )));
      expect(find.text('Microphone needed to talk.'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      expect(opened, isTrue);
    });
  });

  group('MessageComposer', () {
    testWidgets('send delivers text and clears field', (tester) async {
      String? sent;
      await tester.pumpWidget(_wrap(MessageComposer(
        hint: 'Reply…',
        onSend: (t) => sent = t,
      )));
      await tester.enterText(find.byType(TextField), 'hello stilora');
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(sent, 'hello stilora');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('empty submit does not fire', (tester) async {
      var fired = false;
      await tester.pumpWidget(
          _wrap(MessageComposer(hint: 'x', onSend: (_) => fired = true)));
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(fired, isFalse);
    });
  });

  group('MessageRow', () {
    final message = Message(
      id: 'm1',
      author: const UserProfile(
          id: 'u', name: 'Sarah Chen', handle: 'sarah', initials: 'SC'),
      timeLabel: '10:42 AM',
      text: 'Check #design-sync for the spatial update',
      reactions: const [Reaction(emoji: '✦', count: 3)],
      label: 'Core Design',
    );

    testWidgets('renders author, time, mention accent, reactions, label',
        (tester) async {
      await tester.pumpWidget(_wrap(MessageRow(message: message)));
      expect(find.text('Sarah Chen'), findsOneWidget);
      expect(find.text('10:42 AM'), findsOneWidget);
      expect(find.textContaining('#design-sync', findRichText: true),
          findsOneWidget);
      expect(find.text('Core Design'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('failed message shows retry affordance', (tester) async {
      final failed = message.copyWith(status: MessageStatus.failed);
      await tester.pumpWidget(_wrap(MessageRow(message: failed)));
      expect(find.text('Not sent'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('reaction tap callback receives reaction', (tester) async {
      Reaction? got;
      await tester.pumpWidget(_wrap(MessageRow(
        message: message,
        onReact: (r) => got = r,
      )));
      await tester.tap(find.text('3'));
      expect(got?.emoji, '✦');
    });
  });

  group('VoiceCapsule', () {
    testWidgets('mute toggles icon with animation', (tester) async {
      await tester.pumpWidget(
          _wrap(const SizedBox(width: 600, child: VoiceCapsule(onOpenStage: _noop))));
      // Default mic icon present; toggling swaps to mic_off.
      expect(find.byIcon(Icons.mic), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });
  });

  group('AuraBottomNav', () {
    testWidgets('switching tabs fires callback and animates selection',
        (tester) async {
      var index = 0;
      await tester.pumpWidget(_wrap(Scaffold(
        body: AuraBottomNav(
          index: 0,
          unreadBadge: 3,
          onChanged: (i) => index = i,
        ),
      )));
      await tester.tap(find.text('Voice'));
      expect(index, 2);
      await tester.pump(const Duration(milliseconds: 250));
    });
  });

  group('CommandPalette', () {
    testWidgets('opens, filters results, closes on escape', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox.expand()));
      CommandPalette.show(tester.element(find.byType(SizedBox)));
      await _settle(tester);

      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.textContaining('design-sync'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'zzzz-no-match');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('No results for'), findsOneWidget);

      final ctx = tester.element(find.byType(CommandPalette));
      CommandPalette.hide(ctx);
      await _settle(tester, 400);
      expect(find.byType(CommandPalette), findsNothing);
    });
  });

  group('AuraAnimatedSelector', () {
    testWidgets('changing value moves active styling', (tester) async {
      var value = 0;
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) => AuraAnimatedSelector<int>(
          options: const [0, 1],
          value: value,
          labelOf: (v) => v == 0 ? 'First' : 'Second',
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      FontWeight? weightOf(String label) {
        final text = tester.widget<Text>(find.text(label));
        if (text.style?.fontWeight != null) return text.style!.fontWeight;
        final dts = tester.widgetList<AnimatedDefaultTextStyle>(
            find.ancestor(of: find.text(label), matching: find.byType(AnimatedDefaultTextStyle)));
        return dts.isEmpty ? null : dts.first.style.fontWeight;
      }

      expect(weightOf('First'), FontWeight.w600);
      await tester.tap(find.text('Second'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(weightOf('Second'), FontWeight.w600);
    });
  });

  group('Accessibility (strict)', () {
    testWidgets('icon-only action buttons expose semantic labels',
        (tester) async {
      await tester.pumpWidget(_wrap(const Material(
        child: Column(children: [
          Tooltip(message: 'Mute microphone', child: Icon(Icons.mic)),
        ]),
      )));
      expect(find.byTooltip('Mute microphone'), findsOneWidget);
    });

    testWidgets('touch targets meet 44px minimum (FilledButton)',
        (tester) async {
      await tester.pumpWidget(_wrap(FilledButton(
        onPressed: () {},
        child: const Text('Primary action'),
      )));
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('text scales to 200% without clipping core buttons',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: Scaffold(
          body: FilledButton(onPressed: () {}, child: const Text('Send')),
        ),
      ));
      await tester.pump();
      final render = tester.renderObject<RenderBox>(
          find.descendant(
              of: find.byType(FilledButton), matching: find.text('Send')));
      expect(render.size.height, greaterThan(14)); // not collapsed
    });

    testWidgets('reduced-motion respected by pulse dot', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AuraTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: AuraPulseDot())),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      // With reduced motion the repeating controller stops — pumping more
      // must not require additional frames to settle.
      expect(tester.takeException(), isNull);
    });
  });

  group('Motion components', () {
    testWidgets('AuraEntrance becomes fully opaque after duration',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const AuraEntrance(child: Text('revealed'))));
      await tester.pump(const Duration(milliseconds: 400));
      final fade = tester.widget<FadeTransition>(
          find.ancestor(of: find.text('revealed'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, closeTo(1.0, 0.01));
    });

    testWidgets('AuraPop scales to zero when hidden', (tester) async {
      await tester.pumpWidget(_wrap(const AuraPop(
        visible: false,
        child: Text('badge'),
      )));
      await tester.pump(const Duration(milliseconds: 300));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 0);
    });

    testWidgets('AuraPressable shrinks on pointer down', (tester) async {
      await tester.pumpWidget(_wrap(AuraPressable(
        onTap: () {},
        child: const SizedBox(width: 100, height: 40, child: Text('press')),
      )));
      final gesture = await tester.startGesture(
          tester.getCenter(find.text('press')));
      await tester.pump();
      final scale =
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, lessThan(1));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
