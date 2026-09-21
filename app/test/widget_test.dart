import 'package:deutschplan/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app boots and renders its shell', (tester) async {
    await tester.pumpWidget(const DeutschPlanApp());
    expect(find.text('DeutschPlan'), findsOneWidget);
  });
}
