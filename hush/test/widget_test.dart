import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hush/main.dart';

void main() {
  testWidgets('Hush boots to the email + password sign-in screen',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HushApp()));
    // Let entrance animations' delayed starts fire and complete.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Welcome back'), findsWidgets);
    expect(find.text('Hush'), findsWidgets);
    expect(find.text('EMAIL'), findsWidgets);
    expect(find.text('PASSWORD'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
    // No third-party auth anywhere.
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
  });
}
