import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin_panel/main.dart';

void main() {
  testWidgets('Admin app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: LoopCallAdminApp()));
    expect(find.byType(LoopCallAdminApp), findsOneWidget);
  });
}
