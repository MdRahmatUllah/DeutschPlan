import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'text_clipping.dart';

/// The golden audit's own checks (#551).
void main() {
  testWidgets("#565 a field's hint cut to its one line fails, as any text "
      'cut to its lines does', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search German, English or Bangla',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(() => expectAllLinesShown(tester), throwsA(isA<TestFailure>()));
  });
}
