// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/features/exam/exam_review_screen.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/exam_result_fixtures.dart';
import '../features/today_fixtures.dart' show artboardTopic;
import 'golden_harness.dart';

/// L14 · Exam review — #136. The ExamReview artboard: *Wrong only · 9*
/// chosen, the wrong questions in their cards with an example or a rule.
void main() {
  Widget review() => ProviderScope(
    overrides: [
      ...examResultStub(),
      studyBackProvider.overrideWith(
        (ref, uid) async => (
          examples: <StudyExample>[
            (
              german: 'Die Wohnung hat drei Zimmer.',
              english: 'The flat has three rooms.',
            ),
          ],
          tip: (en: 'Nouns ending in -ung are feminine.', bn: null),
        ),
      ),
      examReviewTopicProvider.overrideWith((ref, uid) async => artboardTopic()),
      examGenderTopicProvider.overrideWith(
        (ref, step) async => artboardTopic(),
      ),
    ],
    child: ExamReviewView(attemptId: 7, onBack: () {}),
  );

  Future<void> wrongOnly(WidgetTester tester) async {
    await tester.tap(find.textContaining('Wrong only'));
    await tester.pumpAndSettle();
  }

  goldenTest('exam_review', builder: (context) => review(), act: wrongOnly);

  goldenTest(
    'exam_review_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: (context) => review(),
    act: wrongOnly,
  );
}
