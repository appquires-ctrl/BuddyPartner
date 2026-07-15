import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/app/app.dart';

void main() {
  testWidgets('Splash screen shows smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame inside ProviderScope.
    await tester.pumpWidget(
      const ProviderScope(
        child: LoopCallApp(),
      ),
    );

    // Verify that the splash wordmark "LoopCall" is present
    expect(find.text('LoopCall'), findsOneWidget);
    
    // Verify that the CTA button "Get Started" is present
    expect(find.text('Get Started'), findsOneWidget);

    // Let the finite entrance animations settle to prevent pending timers assertions
    await tester.pump(const Duration(seconds: 2));
  });
}
