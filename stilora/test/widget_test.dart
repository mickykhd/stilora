import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stilora/main.dart';

void main() {
  testWidgets('Stilora boots to the email + password sign-in screen',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StiloraApp()));
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
}
