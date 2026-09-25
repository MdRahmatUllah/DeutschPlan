// #169, flow 2 of 2, first half: a mock begun and answered in part, then left
// mid-exam — no submit, no *Leave*. `tools/smoke.py` then force-stops the
// process, and exam_resume_test.dart starts a new one.

import 'package:deutschplan/features/learn/step_exams.dart' show examQuestions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'smoke.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'FR-L10-03 FR-L12-01: Mock 1 is begun and $answeredBeforeKill typed '
    'answers are written, then the app is left mid-exam',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final l10n = await launch(tester);
      // After first_day_test.dart, Today; run alone on a fresh install, S2.
      if (await startsInSetup(tester, l10n)) await onboard(tester, l10n);
      await unlockExams(tester);
      await openExamHub(tester, l10n);

      // The first *Start* is Mock 1's; FR-L10-03: *Begin exam* creates the
      // attempt and opens L12 on it.
      await tapOn(tester, find.text(l10n.examHubStart));
      await tapOn(tester, find.text(l10n.examIntroBegin));

      // The paper opens on Vocabulary (BR-EXAM-03's order), answered by
      // typing; a typed answer is written as the learner moves on.
      for (var n = 1; n <= answeredBeforeKill; n++) {
        await pumpUntil(
          tester,
          find.text(l10n.examRunQuestion(n, examQuestions)),
          timeout: const Duration(seconds: 60),
        );
        await pumpUntil(tester, find.byType(TextField));
        await tester.enterText(find.byType(TextField), typedAnswer(n));
        await tapOn(tester, find.text(l10n.examRunNext));
      }
      await pumpUntil(
        tester,
        find.text(l10n.examRunQuestion(answeredBeforeKill + 1, examQuestions)),
      );

      // The runner writes without awaiting: give the last write time to
      // land. Then the test ends here, mid-exam, and the process is killed.
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
