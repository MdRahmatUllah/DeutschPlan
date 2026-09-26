import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'text_clipping.dart';

/// The golden audit's own checks (#551).
void main() {
  Future<void> field(WidgetTester tester, InputDecoration decoration) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: TextField(autofocus: true, decoration: decoration),
              ),
            ),
          ),
        ),
      );

  const long = 'Search German, English or Bangla';

  testWidgets('#551 hintsCut lets a field hint cut to one line pass', (
    tester,
  ) async {
    await field(tester, const InputDecoration(hintText: long));
    expect(() => expectAllLinesShown(tester), throwsA(isA<TestFailure>()));
    expectAllLinesShown(tester, hintsCut: true);
  });

  testWidgets("#551 hintsCut doesn't let a field's label or helper be cut", (
    tester,
  ) async {
    await field(
      tester,
      const InputDecoration(
        labelText: long,
        helperText: long,
        helperMaxLines: 1,
      ),
    );
    expect(
      () => expectAllLinesShown(tester, hintsCut: true),
      throwsA(isA<TestFailure>()),
    );
  });
}
