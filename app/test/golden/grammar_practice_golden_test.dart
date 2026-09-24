// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/domain/grammar_item_generator.dart';
import 'package:deutschplan/features/learn/grammar_practice_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L15 · Grammar practice — #119. The artboard: Konjunktiv II –
/// Höflichkeit, *Pick the form* answered wrong — Können for Könnten — with
/// the rule line and *See rule*; and each item type unanswered.
void main() {
  const pick = PickTheForm(
    before: '',
    after: 'Sie mir bitte das Formular schicken?',
    options: <String>['Könnten', 'Können', 'Konnten'],
    answer: 'Könnten',
    translation: 'Could you please send me the form?',
  );
  const gap = GapFill(
    before: 'Ich',
    after: 'gern einen Kaffee.',
    answer: 'hätte',
    translation: "I'd like a coffee.",
  );
  const spot = SpotTheError(
    tokens: <String>['Können', 'Sie', 'mir', 'bitte', 'helfen?'],
    wrong: 0,
    correction: 'Könnten',
  );
  const order = OrderTheSentence(
    chips: <String>['Sie', 'helfen?', 'Könnten', 'mir'],
    answer: <String>['Könnten', 'Sie', 'mir', 'helfen?'],
  );
  const recall = RuleRecall(
    question: 'Konjunktiv II – Höflichkeit',
    options: <String>[
      'Use könnte or würde with the infinitive to ask politely.',
      'The conjugated verb goes to the end of a weil clause.',
      'Adjectives after der take -e or -en.',
      'Separable prefixes go to the end in the present.',
    ],
    answer: 0,
  );

  Widget screen(GrammarItem first) => ProviderScope(
    overrides: [
      ...todayStub(),
      practiceSetProvider.overrideWith(
        (ref, uid) async => (
          topic: artboardTopic(),
          items: <GrammarItem>[first, gap, pick, spot, order],
        ),
      ),
    ],
    child: const GrammarPracticeScreen(topicUids: <String>['g3']),
  );

  goldenTest(
    'grammar_practice',
    builder: (context) => screen(pick),
    act: (tester) async {
      await tester.tap(find.text('Können'));
      await tester.pumpAndSettle();
    },
  );

  for (final (name, item) in <(String, GrammarItem)>[
    ('gap_fill', gap),
    ('spot_the_error', spot),
    ('order_the_sentence', order),
    ('rule_recall', recall),
  ]) {
    goldenTest(
      'grammar_practice_$name',
      modes: const <GoldenMode>[GoldenMode.light],
      devices: const <GoldenDevice>[GoldenDevice.phone],
      builder: (context) => screen(item),
    );
  }
}
