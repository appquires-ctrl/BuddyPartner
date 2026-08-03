import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame inside ProviderScope.
    await tester.pumpWidget(
      const ProviderScope(
        child: BuddyPartnerApp(),
      ),
    );

    // Let the entrance animation/router settle
    await tester.pumpAndSettle();
  });
}
