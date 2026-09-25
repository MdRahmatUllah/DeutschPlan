// #169, flow 2 of 2, second half: a new process, after exam_start_test.dart's
// was force-stopped (`tools/smoke.py`). The exam it left must still be there,
// with its answers.

import 'package:deutschplan/features/learn/step_exams.dart' show examQuestions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'smoke.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'FR-L10-02 FR-L12-01 FR-L12-04: after the process is killed, Mock 1 '
    'resumes at the first unanswered question with its answers, then is left',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final l10n = await launch(tester);
      expect(
        await startsInSetup(tester, l10n),
        isFalse,
        reason:
            'S2 again: user.db did not survive the relaunch. `flutter '
            'test` uninstalls the app after a run unless given --no-uninstall',
      );
      await openExamHub(tester, l10n);

      // FR-L10-02: the unfinished attempt offers *Resume*, not *Start*.
      await tapOn(tester, find.text(l10n.examHubResume));

      // FR-L12-01: back at the first unanswered question…
      await pumpUntil(
        tester,
        find.text(l10n.examRunQuestion(answeredBeforeKill + 1, examQuestions)),
        timeout: const Duration(seconds: 60),
      );
      // …with every answer given before the kill.
      for (var n = answeredBeforeKill; n >= 1; n--) {
        await tapOn(tester, find.text(l10n.examRunPrevious));
        await pumpUntil(
          tester,
          find.text(l10n.examRunQuestion(n, examQuestions)),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          typedAnswer(n),
        );
      }

      // FR-L12-04: left cleanly — pause asks, *Leave* abandons, and the hub
      // counts it as an attempt with nothing to resume.
      await tapOn(tester, semanticsLabelled(l10n.examRunPause));
      await tapOn(tester, find.text(l10n.examLeaveConfirm));
      await pumpUntil(tester, find.textContaining(l10n.examHubAttempts(1)));
      expect(find.text(l10n.examHubResume), findsNothing);
    },
  );
}
