// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/features/learn/grammar_topic_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/today_fixtures.dart';
import 'golden_harness.dart';

/// L4 · Grammar topic — #118. The artboard's Konjunktiv II – Höflichkeit:
/// the rule, two examples with play, the Watch out callout, Practise and
/// Mark as learned, and the step's neighbours.
void main() {
  goldenTest(
    'grammar_topic',
    builder: (context) => ProviderScope(
      overrides: todayStub(),
      child: const GrammarTopicScreen(uid: 'g3'),
    ),
  );
}
