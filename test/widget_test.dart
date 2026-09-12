import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame inside ProviderScope.
    await tester.pumpWidget(
      const ProviderScope(
        child: BuddyPartnerApp(),
      ),
    );

    // Pump frames to allow initial build and splash animations to render
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
