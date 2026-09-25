import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/features/search/add_word_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// R2 · Add / edit my word — #143. The AddWord artboard: "Pfand" with das,
/// already in the course at A1.2, its meaning and where it was seen.
void main() {
  final pfand = WordHit(
    word: artboardWords().first.word.word.copyWith(
      german: 'Pfand',
      article: const Value('das'),
      sublevelCode: 'A1.2',
    ),
    tier: SearchTier.exact,
    rank: 0,
  );

  goldenTest(
    'add_word',
    overrides: [
      courseMatchProvider.overrideWith(
        (ref, german) async => german == 'Pfand' ? pfand : null,
      ),
    ],
    builder: (_) => const AddWordScreen(german: 'Pfand'),
    act: (tester) async {
      await tester.tap(find.text('das').first);
      await tester.enterText(
        find.byType(TextField).at(1),
        'deposit (on bottles)',
      );
      await tester.enterText(find.byType(TextField).at(2), 'Rewe receipt');
      await tester.pump(AddWordScreen.debounce);
      await tester.pumpAndSettle();
      // The artboard is at rest: no field typed in, so no umlaut row.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    },
  );
}
