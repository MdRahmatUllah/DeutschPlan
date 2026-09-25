@TestOn('vm')
library;

import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plan engine — #76, BR-PLAN-01…05.
///
/// `plan-engine.md` names the tests that must exist: first day, missed two
/// days, rest day no growth, revise fill order, idempotent reopen, midnight
/// rollover. The ones it names that belong to #77 — skip, auto-advance, the
/// pause flag — are not here, and the engine does not pretend to do them.
///
/// Everything runs against [FakeStore]: a few maps. The rules here are about
/// dates, and a test that has to build a database to move the calendar forward
/// is a test nobody writes.
void main() {
  /// A Monday, so the weekday maths is legible.
  const monday = '2026-03-02';

  late FakeStore store;

  PlanEngine engineWith({
    int revise = 10,
    int catchup = 30,
    bool autoAdvance = true,
    bool pauseNewWhenBacklog = false,
  }) => PlanEngine(
    store: store,
    reviseCount: revise,
    backlogCatchupDays: catchup,
    autoAdvance: autoAdvance,
    pauseNewWhenBacklog: pauseNewWhenBacklog,
  );

  setUp(() {
    store = FakeStore()
      ..enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: PlanEngine.allDays,
      )
      // Enough not to run out: the catch-up test walks 31 days at 7 a day.
      ..vocabulary = <String>[for (var i = 1; i <= 500; i++) 'w$i'];
  });

  group('FR-L2-03 switchStep', () {
    test('completes the current step today and enrols the new one at the '
        'pace given', () async {
      final engine = engineWith();
      await engine.openDay(monday);
      await engine.switchStep('A2.1', monday, dailyNew: 10, studyDaysMask: 31);
      expect(store.completed, <String>['A1.1@$monday']);
      expect(store.enrollment?.sublevelCode, 'A2.1');
      expect(store.enrollment?.startedOn, monday);
      expect(
        (store.enrollment?.dailyNew, store.enrollment?.studyDaysMask),
        (10, 31),
      );
    });

    test("BR-PLAN-08 today's plan is left as it is", () async {
      final engine = engineWith();
      final before = await engine.openDay(monday);
      final planned = store.lastPlanned;
      await engine.switchStep(
        'A2.1',
        monday,
        dailyNew: 7,
        studyDaysMask: PlanEngine.allDays,
      );
      expect(store.lastPlanned, planned, reason: 'today is not planned again');
      final again = await engine.openDay(monday);
      expect(again.newToday, before.newToday);
    });

    test('with no step active, it only enrols', () async {
      store.enrollment = null;
      await engineWith().switchStep(
        'A1.2',
        monday,
        dailyNew: 7,
        studyDaysMask: PlanEngine.allDays,
      );
      expect(store.completed, isEmpty);
      expect(store.enrollment?.sublevelCode, 'A1.2');
    });

    test('the active step itself is left alone', () async {
      await engineWith().switchStep(
        'A1.1',
        monday,
        dailyNew: 12,
        studyDaysMask: PlanEngine.allDays,
      );
      expect(store.completed, isEmpty);
      expect(store.enrolled, isEmpty);
      expect(store.enrollment?.dailyNew, 7);
    });
  });

  group('BR-COURSE-05 startNextStep', () {
    setUp(() {
      store.wordsByStep = <String, List<String>>{
        'A1.1': <String>[for (var i = 1; i <= 7; i++) 'a$i'],
        'A1.2': <String>[for (var i = 1; i <= 50; i++) 'b$i'],
      };
    });

    test('enrolls the next step, and today gets its new words', () async {
      // Auto-advance off: A1.1 runs out on Monday and nothing replaces it.
      final engine = engineWith(autoAdvance: false);
      await engine.openDay(monday);
      store.complete(monday);
      final tuesday = addDays(monday, 1);
      final stuck = await engine.openDay(tuesday);
      expect(stuck.stepComplete, isTrue);
      expect(stuck.nextStep, 'A1.2');

      final started = await engine.startNextStep(
        tuesday,
        dailyNew: 5,
        studyDaysMask: PlanEngine.allDays,
      );
      expect(started, 'A1.2');
      expect(store.enrollment?.sublevelCode, 'A1.2');
      expect(store.enrollment?.dailyNew, 5, reason: "the learner's pace now");

      final opened = await engine.openDay(tuesday);
      expect(opened.activeStep, 'A1.2');
      expect(opened.newToday, <String>['b1', 'b2', 'b3', 'b4', 'b5']);
    });

    test('does nothing while a step is active', () async {
      final engine = engineWith(autoAdvance: false);
      expect(
        await engine.startNextStep(
          monday,
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        ),
        isNull,
      );
      expect(store.enrolled, isEmpty);
    });

    test('does nothing at the end of the course', () async {
      store
        ..course = <String>['A1.1']
        ..wordsByStep = <String, List<String>>{
          'A1.1': <String>[for (var i = 1; i <= 7; i++) 'a$i'],
        };
      final engine = engineWith(autoAdvance: false);
      await engine.openDay(monday);
      await engine.openDay(addDays(monday, 1));

      expect(
        await engine.startNextStep(
          addDays(monday, 1),
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        ),
        isNull,
      );
    });
  });

  group('FR-T6-02 previewDay', () {
    /// Everything the store holds that planning can change.
    String snapshot() =>
        '${store.plan}|${store.lastPlanned}|${store.enrollment?.sublevelCode}'
        '|${store.completed}|${store.enrolled.length}';

    Future<void> expectPreviewIsTheDay(PlanDate day) async {
      final engine = engineWith();
      final before = snapshot();

      final preview = await engine.previewDay(day);
      expect(snapshot(), before, reason: 'the preview wrote something');

      final opened = await engine.openDay(day);
      expect(preview.newToday, opened.newToday);
      expect(preview.revise, opened.revise);
      expect(preview.grammarDue, opened.grammarDue);
      expect(preview.backlog, opened.backlog);
      expect(preview.activeStep, opened.activeStep);
    }

    test('is what opening the day will do, and writes nothing', () async {
      await engineWith().openDay(monday);
      store.complete(monday);
      store.candidates = <RevisionCandidate>[
        RevisionCandidate(uid: 'w1', stability: 2, lastReview: monday),
      ];

      await expectPreviewIsTheDay(addDays(monday, 1));
    });

    test('across a step that runs out', () async {
      // Ten words in A1.1: Monday takes seven, so Tuesday finishes the step
      // and starts A1.2 — in the preview, without closing anything for real.
      store.wordsByStep = <String, List<String>>{
        'A1.1': <String>[for (var i = 1; i <= 10; i++) 'a$i'],
        'A1.2': <String>[for (var i = 1; i <= 50; i++) 'b$i'],
      };
      await engineWith().openDay(monday);
      store.complete(monday);

      final preview = await engineWith().previewDay(addDays(monday, 1));
      expect(preview.activeStep, 'A1.2');
      expect(store.enrollment?.sublevelCode, 'A1.1', reason: 'still A1.1');
      expect(store.completed, isEmpty);

      await expectPreviewIsTheDay(addDays(monday, 1));
    });

    test('across a missed day, which it shows as backlog', () async {
      await engineWith().openDay(monday);
      store.complete(monday);

      final wednesday = addDays(monday, 2);
      final preview = await engineWith().previewDay(wednesday);
      expect(preview.backlog, hasLength(7), reason: "Tuesday's words");

      await expectPreviewIsTheDay(wednesday);
    });
  });

  group('the first day', () {
    test('plans daily_new words and nothing before it', () async {
      final plan = await engineWith().openDay(monday);

      expect(plan.newToday, hasLength(7));
      expect(plan.newToday, <String>['w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7']);
      expect(plan.backlog, isEmpty, reason: 'nothing was missed yet');
      expect(plan.activeStep, 'A1.1');
      expect(plan.isStudyDay, isTrue);
    });

    test('the plan reads back in the order it was written', () async {
      // The order is the answer, not an accident of the query plan: new words
      // are walked in teaching order and revisions in BR-PLAN-03's priority.
      //
      // Uids deliberately out of alphabetical order. With 'seen0'..'seen3' a
      // list that came back sorted would pass this, which is exactly what let
      // a planted sort survive the first time I tried it.
      const byPriority = <String>['zulu', 'alpha', 'mike', 'bravo'];
      store.candidates = <RevisionCandidate>[
        for (var i = 0; i < byPriority.length; i++)
          RevisionCandidate(
            uid: byPriority[i],
            stability: 5,
            lastReview: addDays(monday, -10 + i),
          ),
      ];

      final plan = await engineWith(revise: 4).openDay(monday);

      expect(plan.newToday, store.plan['$monday/new']);
      expect(
        plan.revise,
        byPriority,
        reason: 'lowest retrievability first, and it survived the round trip',
      );

      // Day two, because day one is w1..w7 — which sorts into the same order
      // it was written in, so it cannot tell teaching order from a sort. Day
      // two crosses ten, where 'w10' sorts before 'w8'.
      final next = await engineWith(revise: 4).openDay(addDays(monday, 1));

      expect(next.newToday, <String>[
        'w8',
        'w9',
        'w10',
        'w11',
        'w12',
        'w13',
        'w14',
      ]);
      expect(
        next.newToday,
        isNot(<String>[...next.newToday]..sort()),
        reason: 'the fixture stopped being able to tell the two apart',
      );
    });

    test('takes them in teaching order, not at random', () async {
      await engineWith().openDay(monday);
      expect(store.plan['$monday/new'], <String>[
        'w1',
        'w2',
        'w3',
        'w4',
        'w5',
        'w6',
        'w7',
      ]);
    });

    test('has nothing to revise', () async {
      // Nothing has been met, so there is nothing to bring back.
      expect((await engineWith().openDay(monday)).revise, isEmpty);
    });

    test('and before enrolling, plans nothing at all', () async {
      store.enrollment = null;

      final plan = await engineWith().openDay(monday);

      expect(plan.newToday, isEmpty);
      expect(plan.activeStep, isNull);
      expect(store.lastPlanned, isNull, reason: 'it claimed to have planned');
    });
  });

  group('missed days (BR-PLAN-05)', () {
    test('two days missed gives a backlog of fourteen', () async {
      // The doc's own figure: open on Monday, come back on Thursday, and the
      // two skipped days are planned retroactively at 7 each.
      final engine = engineWith();
      await engine.openDay(monday);

      final thursday = addDays(monday, 3);
      final plan = await engine.openDay(thursday);

      expect(plan.newToday, hasLength(7));
      expect(plan.backlog, hasLength(21), reason: 'Mon + Tue + Wed');

      // Monday's seven were never done either, so the backlog is all three
      // earlier days. The two *missed* days are fourteen of it.
      expect(store.plan['${addDays(monday, 1)}/new'], hasLength(7));
      expect(store.plan['${addDays(monday, 2)}/new'], hasLength(7));
    });

    test('each missed day keeps its own date', () async {
      // A word has to carry the date it was meant for: that is what makes it
      // backlog rather than part of today, and what the backlog groups by.
      final engine = engineWith();
      await engine.openDay(addDays(monday, 2));

      expect(
        store.plan.keys,
        containsAll(<String>[
          '$monday/new',
          '${addDays(monday, 1)}/new',
          '${addDays(monday, 2)}/new',
        ]),
      );
    });

    test('nothing is generated before the catch-up window', () async {
      // Coming back after six months must not produce a thousand-word
      // backlog. Beyond the window the days are gone.
      final engine = engineWith(catchup: 30);
      final muchLater = addDays(monday, 200);

      await engine.openDay(muchLater);

      final planned = store.plan.keys.where((k) => k.endsWith('/new'));
      expect(planned, hasLength(31), reason: '30 days back, plus today');
      expect(
        planned.every((k) => daysBetween(k.split('/').first, muchLater) <= 30),
        isTrue,
      );
    });

    test('and never before the learner enrolled', () async {
      // The catch-up window reaches back further than the course exists.
      final engine = engineWith(catchup: 30);
      await engine.openDay(addDays(monday, 3));

      expect(
        store.plan.keys.every(
          (k) => daysBetween(monday, k.split('/').first) >= 0,
        ),
        isTrue,
        reason: 'it planned days before the enrollment started',
      );
    });

    test('a step that runs out with nowhere to go stops there', () async {
      // The last step of the course: nothing to advance into, so planning
      // ends rather than writing an empty plan for every remaining day.
      store.course = <String>['A1.1'];
      store.vocabulary = <String>['w1', 'w2', 'w3'];
      final engine = engineWith();

      await engine.openDay(addDays(monday, 10));

      expect(store.plan['$monday/new'], <String>['w1', 'w2', 'w3']);
      expect(store.plan.containsKey('${addDays(monday, 1)}/new'), isFalse);
    });

    test(
      'a later enrollment is not back-planned onto its predecessor',
      () async {
        // Restarting setup (#92) leaves `last_planned_date` from the old course
        // while the new enrollment starts today. Without the floor, the walk
        // begins the day after the *old* planning and writes rows dated before
        // the learner had a course.
        store.lastPlanned = monday;
        final restartedOn = addDays(monday, 10);
        store.enrollment = ActiveStep(
          sublevelCode: 'A2.1',
          startedOn: restartedOn,
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        );

        await engineWith().openDay(addDays(restartedOn, 2));

        for (final key in store.plan.keys) {
          expect(
            daysBetween(restartedOn, key.split('/').first),
            greaterThanOrEqualTo(0),
            reason: '$key is before the enrollment started',
          );
        }
        expect(store.plan, isNotEmpty, reason: 'it planned nothing at all');
      },
    );
  });

  group('rest days (BR-PLAN-01)', () {
    setUp(() {
      // Weekdays only: bits 0–4.
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: 0x1F,
      );
    });

    test('a rest day grows nothing', () async {
      final saturday = addDays(monday, 5);
      final engine = engineWith();

      final plan = await engine.openDay(saturday);

      expect(plan.isStudyDay, isFalse);
      expect(plan.newToday, isEmpty);
      expect(store.plan.containsKey('$saturday/new'), isFalse);
      expect(store.plan.containsKey('${addDays(monday, 6)}/new'), isFalse);
    });

    test('and the weekdays around it still do', () async {
      await engineWith().openDay(addDays(monday, 7));

      for (var i = 0; i < 5; i++) {
        expect(
          store.plan['${addDays(monday, i)}/new'],
          hasLength(7),
          reason: 'weekday ${addDays(monday, i)}',
        );
      }
      for (final weekend in <int>[5, 6]) {
        expect(
          store.plan.containsKey('${addDays(monday, weekend)}/new'),
          isFalse,
          reason: 'weekend ${addDays(monday, weekend)}',
        );
      }
    });

    test(
      'BR-PLAN-08: today turned off stays a study day, tomorrow follows',
      () async {
        final engine = engineWith();
        expect((await engine.openDay(monday)).isStudyDay, isTrue);

        // M5 turns Monday off during Monday.
        store.enrollment = const ActiveStep(
          sublevelCode: 'A1.1',
          startedOn: monday,
          dailyNew: 7,
          studyDaysMask: 0x1E,
        );

        final again = await engineWith().openDay(monday);
        expect(again.isStudyDay, isTrue);
        expect(again.newToday, hasLength(7));
        expect(
          (await engineWith().openDay(addDays(monday, 7))).isStudyDay,
          isFalse,
        );
      },
    );

    test('BR-PLAN-08: a rest day turned on stays a rest day', () async {
      final saturday = addDays(monday, 5);
      expect((await engineWith().openDay(saturday)).isStudyDay, isFalse);

      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: 0x3F,
      );

      expect((await engineWith().openDay(saturday)).isStudyDay, isFalse);
      expect(
        (await engineWith().openDay(addDays(saturday, 7))).isStudyDay,
        isTrue,
      );
    });

    test('revision is still offered on one', () async {
      // BR-PLAN-01: "no new words, no backlog growth, streak preserved;
      // revisions are optional" — offered, not withheld.
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(
          uid: 'seen',
          stability: 5,
          lastReview: monday,
          due: monday,
        ),
      ];

      final plan = await engineWith().openDay(addDays(monday, 5));

      expect(plan.isStudyDay, isFalse);
      expect(plan.revise, <String>['seen']);
    });

    test('every weekday maps to its own bit', () async {
      final engine = engineWith();
      for (var day = 0; day < 7; day++) {
        final date = addDays(monday, day);
        expect(
          engine.isStudyDay(date, 1 << day),
          isTrue,
          reason: 'bit $day should enable $date',
        );
        expect(
          engine.isStudyDay(date, PlanEngine.allDays & ~(1 << day)),
          isFalse,
          reason: 'clearing bit $day should disable $date',
        );
      }
    });
  });

  group('BR-PLAN-07 — the backlog pause', () {
    test('stops new words while the backlog is not empty', () async {
      // Monday's seven go unfinished, so from Tuesday the pause holds.
      final engine = engineWith(pauseNewWhenBacklog: true);
      await engine.openDay(monday);
      expect(store.plan['$monday/new'], hasLength(7));

      final later = await engine.openDay(addDays(monday, 3));

      expect(later.newToday, isEmpty);
      expect(later.newPaused, isTrue);
      for (var day = 1; day <= 3; day++) {
        expect(
          store.plan.containsKey('${addDays(monday, day)}/new'),
          isFalse,
          reason: 'day $day was planned while paused',
        );
      }
    });

    test('and revisions carry on', () async {
      // The rule is about new words. A learner who is behind still revises.
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(uid: 'seen', stability: 5, lastReview: monday),
      ];
      final engine = engineWith(pauseNewWhenBacklog: true);
      await engine.openDay(monday);

      final later = await engine.openDay(addDays(monday, 2));

      expect(later.newToday, isEmpty);
      expect(later.revise, <String>['seen']);
    });

    test('it resumes once the backlog is cleared', () async {
      final engine = engineWith(pauseNewWhenBacklog: true);
      await engine.openDay(monday);
      await engine.openDay(addDays(monday, 1));
      expect(store.plan.containsKey('${addDays(monday, 1)}/new'), isFalse);

      store.complete(monday);

      final resumed = await engine.openDay(addDays(monday, 2));

      expect(resumed.newToday, hasLength(7));
      expect(resumed.newPaused, isFalse);
    });

    test('and with the flag off a backlog does not stop anything', () async {
      final engine = engineWith();
      await engine.openDay(monday);

      final later = await engine.openDay(addDays(monday, 3));

      expect(later.newToday, hasLength(7));
      expect(later.newPaused, isFalse);
      expect(later.backlog, isNotEmpty, reason: 'the fixture proves nothing');
    });

    test('the pause is judged per day, not once for the run', () async {
      // Planning a day creates the rows that are backlog for the day after.
      // Checking once at the start would let a catch-up run plan every missed
      // day and leave the learner deeper in than when they opened the app.
      store.vocabulary = <String>[for (var i = 1; i <= 100; i++) 'w$i'];
      final engine = engineWith(pauseNewWhenBacklog: true);

      await engine.openDay(addDays(monday, 5));

      final planned = store.plan.keys.where((k) => k.endsWith('/new'));
      expect(
        planned,
        hasLength(1),
        reason: 'only the first day had an empty backlog in front of it',
      );
    });
  });

  group('BR-COURSE-05 — auto-advance', () {
    setUp(() {
      store.wordsByStep = <String, List<String>>{
        'A1.1': <String>['a1', 'a2', 'a3'],
        'A1.2': <String>['b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8'],
        'A2.1': <String>['c1', 'c2'],
      };
    });

    test('a step that runs out enrols the next one', () async {
      final engine = engineWith(autoAdvance: true);

      await engine.openDay(monday);

      // Three from A1.1, then four from A1.2 to fill the seven.
      expect(store.plan['$monday/new'], <String>[
        'a1',
        'a2',
        'a3',
        'b1',
        'b2',
        'b3',
        'b4',
      ]);
      expect(store.completed, <String>['A1.1@$monday']);
      expect(store.enrolled.single.sublevelCode, 'A1.2');
    });

    test('the new enrolment keeps the pace and the study days', () async {
      // BR-PLAN-08 freezes the pace per enrolment; advancing a step is not
      // the learner changing their mind about it.
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 5,
        studyDaysMask: 0x1F,
      );

      await engineWith().openDay(monday);

      final next = store.enrolled.single;
      expect(next.dailyNew, 5);
      expect(next.studyDaysMask, 0x1F);
      expect(next.startedOn, monday);
    });

    test('and it walks more than one step in a day if it has to', () async {
      // Three from A1.1 and one from A1.2 leave three of the seven unfilled,
      // so the day reaches into a third step. A2.1 has five, so it finishes
      // the day *without* running out — otherwise this would be testing the
      // end of the course rather than a second advance.
      store.wordsByStep['A1.2'] = <String>['b1'];
      store.wordsByStep['A2.1'] = <String>['c1', 'c2', 'c3', 'c4', 'c5'];
      final engine = engineWith();

      await engine.openDay(monday);

      expect(store.completed, <String>['A1.1@$monday', 'A1.2@$monday']);
      expect(store.enrolled.map((e) => e.sublevelCode), <String>[
        'A1.2',
        'A2.1',
      ]);
      expect(store.plan['$monday/new'], <String>[
        'a1',
        'a2',
        'a3',
        'b1',
        'c1',
        'c2',
        'c3',
      ]);
    });

    test('running out of course entirely closes the last step too', () async {
      // Every step exhausted and no next one: the run ends rather than
      // looping, and the last step is closed like the others.
      store.wordsByStep['A1.2'] = <String>['b1'];
      await engineWith().openDay(monday);

      expect(store.completed, <String>[
        'A1.1@$monday',
        'A1.2@$monday',
        'A2.1@$monday',
      ]);
      expect(store.plan['$monday/new'], hasLength(6), reason: '3 + 1 + 2');
    });

    test('with it off the step completes and nothing replaces it', () async {
      final engine = engineWith(autoAdvance: false);

      final plan = await engine.openDay(monday);

      expect(store.plan['$monday/new'], <String>['a1', 'a2', 'a3']);
      expect(store.enrolled, isEmpty, reason: 'it advanced anyway');
      expect(plan.stepComplete, isTrue);
      expect(plan.activeStep, isNull);
      expect(plan.nextStep, 'A1.2', reason: 'Today offers Start next step');
    });

    test('a learner mid-course is offered no next step', () async {
      // The discriminating case: they have finished A1.1 and are on A1.2, so
      // `lastCompletedStep` answers A1.1 and the step after it is the one they
      // are *already* studying. Offering it would put "Start next step" on
      // Today for a learner who is part way through.
      // A1.2 needs enough words to still be the active step on day two —
      // otherwise this tests the end of the course again.
      store.wordsByStep['A1.2'] = <String>[for (var i = 1; i <= 50; i++) 'b$i'];

      await engineWith().openDay(monday);
      expect(store.completed, <String>['A1.1@$monday']);
      expect(store.enrollment!.sublevelCode, 'A1.2');

      final plan = await engineWith().openDay(addDays(monday, 1));

      expect(plan.activeStep, 'A1.2');
      expect(plan.stepComplete, isFalse);
      expect(plan.nextStep, isNull, reason: 'it offered the active step');
    });

    test('at the end of the course there is no next step to offer', () async {
      store.course = <String>['A1.1'];
      final engine = engineWith();

      final plan = await engine.openDay(monday);

      expect(plan.stepComplete, isTrue);
      expect(plan.nextStep, isNull);
    });

    test('step complete is not the same as never having enrolled', () async {
      // Both leave `activeStep` null, and Today shows a different thing for
      // each: one offers the next step, the other is the onboarding case.
      store.enrollment = null;

      final plan = await engineWith().openDay(monday);

      expect(plan.activeStep, isNull);
      expect(plan.stepComplete, isFalse);
      expect(plan.nextStep, isNull);
    });
  });

  group('revise selection (BR-PLAN-03)', () {
    test('a due card comes before a weaker undue one', () {
      // The discriminating case. Ranking everything by retrievability gives
      // the same answer as due-first for most pairs, so a test has to use a
      // due card the learner is *more* likely to remember: strong, reviewed
      // yesterday, and due today anyway.
      final picked = selectRevisions(
        <RevisionCandidate>[
          const RevisionCandidate(
            uid: 'undue-but-shaky',
            stability: 1,
            lastReview: '2026-01-01',
          ),
          RevisionCandidate(
            uid: 'due-and-solid',
            stability: 400,
            lastReview: addDays(monday, -1),
            due: monday,
          ),
        ],
        on: monday,
        limit: 2,
        fsrs: Fsrs(),
      );

      expect(picked, <String>['due-and-solid', 'undue-but-shaky']);
    });

    test('due cards come first, earliest first', () {
      final picked = selectRevisions(
        <RevisionCandidate>[
          const RevisionCandidate(
            uid: 'later',
            stability: 5,
            lastReview: '2026-02-20',
            due: '2026-03-02',
          ),
          const RevisionCandidate(
            uid: 'earlier',
            stability: 5,
            lastReview: '2026-02-10',
            due: '2026-02-25',
          ),
        ],
        on: monday,
        limit: 10,
        fsrs: Fsrs(),
      );

      expect(picked, <String>['earlier', 'later']);
    });

    test('then the fill is by lowest retrievability', () {
      // Same stability, different elapsed: the one left longest is the one
      // most likely to have been lost.
      final picked = selectRevisions(
        <RevisionCandidate>[
          const RevisionCandidate(
            uid: 'fresh',
            stability: 10,
            lastReview: '2026-03-01',
          ),
          const RevisionCandidate(
            uid: 'stale',
            stability: 10,
            lastReview: '2026-01-01',
          ),
          const RevisionCandidate(
            uid: 'middling',
            stability: 10,
            lastReview: '2026-02-15',
          ),
        ],
        on: monday,
        limit: 10,
        fsrs: Fsrs(),
      );

      expect(picked, <String>['stale', 'middling', 'fresh']);
    });

    test('and a weaker card outranks an older one', () {
      // Retrievability, not elapsed time. A card reviewed a month ago with a
      // year of stability is safer than one reviewed a week ago with two days.
      final picked = selectRevisions(
        <RevisionCandidate>[
          const RevisionCandidate(
            uid: 'strong-and-old',
            stability: 365,
            lastReview: '2026-02-01',
          ),
          const RevisionCandidate(
            uid: 'weak-and-recent',
            stability: 2,
            lastReview: '2026-02-24',
          ),
        ],
        on: monday,
        limit: 10,
        fsrs: Fsrs(),
      );

      expect(picked, <String>['weak-and-recent', 'strong-and-old']);
    });

    test('excess due cards wait rather than overflowing the limit', () {
      final picked = selectRevisions(
        <RevisionCandidate>[
          for (var i = 0; i < 50; i++)
            RevisionCandidate(
              uid: 'w$i',
              stability: 5,
              lastReview: '2026-02-01',
              due: addDays('2026-02-01', i),
            ),
        ],
        on: monday,
        limit: 10,
        fsrs: Fsrs(),
      );

      expect(picked, hasLength(10));
      expect(picked.first, 'w0', reason: 'earliest due');
    });

    test('a limit of zero picks nothing', () {
      expect(
        selectRevisions(
          <RevisionCandidate>[
            const RevisionCandidate(
              uid: 'w1',
              stability: 5,
              lastReview: monday,
              due: monday,
            ),
          ],
          on: monday,
          limit: 0,
          fsrs: Fsrs(),
        ),
        isEmpty,
      );
    });

    test('a card due tomorrow is not due today', () {
      final picked = selectRevisions(
        <RevisionCandidate>[
          RevisionCandidate(
            uid: 'tomorrow',
            stability: 100,
            lastReview: monday,
            due: addDays(monday, 1),
          ),
          const RevisionCandidate(
            uid: 'undue-but-weak',
            stability: 1,
            lastReview: '2026-01-01',
          ),
        ],
        on: monday,
        limit: 1,
        fsrs: Fsrs(),
      );

      // Neither is due, so the weaker one wins on retrievability.
      expect(picked, <String>['undue-but-weak']);
    });

    test('the order is stable when two cards tie', () {
      // Without a tiebreak the plan reshuffles between openings of the same
      // day, which BR-PLAN-04 forbids.
      List<String> run() => selectRevisions(
        <RevisionCandidate>[
          for (final uid in <String>['c', 'a', 'b'])
            RevisionCandidate(uid: uid, stability: 5, lastReview: '2026-02-01'),
        ],
        on: monday,
        limit: 3,
        fsrs: Fsrs(),
      );

      expect(run(), <String>['a', 'b', 'c']);
      expect(run(), run());
    });

    test("today's new words are excluded", () async {
      // Meeting a word for the first time and revising it in the same session
      // is not revision.
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(uid: 'w1', stability: 1, lastReview: monday),
        const RevisionCandidate(uid: 'old', stability: 1, lastReview: monday),
      ];

      final plan = await engineWith().openDay(monday);

      expect(plan.newToday, contains('w1'));
      expect(plan.revise, <String>['old']);
    });
  });

  group('idempotence (BR-PLAN-04)', () {
    test('reopening the same day returns the same plan', () async {
      store.candidates = <RevisionCandidate>[
        for (var i = 0; i < 30; i++)
          RevisionCandidate(
            uid: 'seen$i',
            stability: 5,
            lastReview: addDays(monday, -i - 1),
          ),
      ];
      final engine = engineWith();

      final first = await engine.openDay(monday);
      final second = await engine.openDay(monday);

      expect(second.newToday, first.newToday);
      expect(second.revise, first.revise);
    });

    test('and does not double the rows', () async {
      final engine = engineWith();
      await engine.openDay(monday);
      final after = store.plan['$monday/new']!.length;

      await engine.openDay(monday);
      await engine.openDay(monday);

      expect(store.plan['$monday/new'], hasLength(after));
    });

    test('even when the schedule moved on in between', () async {
      // A word that fell due after the day was opened waits for tomorrow. The
      // plan the learner is part way through must not change under them.
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(uid: 'a', stability: 5, lastReview: monday),
      ];
      final engine = engineWith();
      final first = await engine.openDay(monday);

      store.candidates = <RevisionCandidate>[
        ...store.candidates,
        const RevisionCandidate(
          uid: 'suddenly-due',
          stability: 1,
          lastReview: '2026-01-01',
          due: monday,
        ),
      ];

      expect((await engine.openDay(monday)).revise, first.revise);
    });

    test(
      'BR-PLAN-08 a day opened with none keeps none when the count rises',
      () async {
        // #342: M3 or restart setup raises revise_count mid-day and the engine
        // is rebuilt. Today was opened with nothing to revise; it stays so.
        store.candidates = <RevisionCandidate>[
          const RevisionCandidate(
            uid: 'a',
            stability: 5,
            lastReview: '2026-02-20',
          ),
        ];
        await engineWith(revise: 0).openDay(monday);
        expect((await engineWith().openDay(monday)).revise, isEmpty);
        expect(
          (await engineWith().openDay(addDays(monday, 1))).revise,
          <String>['a'],
          reason: 'from tomorrow',
        );
      },
    );

    test(
      'a day with rows is left alone even if planning never finished',
      () async {
        // The guard inside the walk, which `last_planned_date` usually makes
        // unreachable. A crash between writing the rows and recording the date
        // leaves exactly this state, and re-walking would plan a *second* seven
        // words onto the same day.
        await store.addToPlan(monday, PlanKind.newWord, <String>['w1', 'w2']);
        expect(store.lastPlanned, isNull, reason: 'the fixture is the crash');

        await engineWith().openDay(monday);

        expect(store.plan['$monday/new'], <String>['w1', 'w2']);
      },
    );

    test('reopening does not re-walk days already planned', () async {
      final engine = engineWith();
      await engine.openDay(addDays(monday, 3));
      final planned = Map<String, List<String>>.from(store.plan);

      await engine.openDay(addDays(monday, 3));

      expect(store.plan.length, planned.length);
      for (final entry in planned.entries) {
        expect(store.plan[entry.key], entry.value, reason: entry.key);
      }
    });
  });

  group('the midnight rollover', () {
    test(
      'a new day gets its own plan, and yesterday becomes backlog',
      () async {
        final engine = engineWith();
        final today = await engine.openDay(monday);

        final tuesday = addDays(monday, 1);
        final tomorrow = await engine.openDay(tuesday);

        expect(tomorrow.newToday, isNot(today.newToday));
        expect(tomorrow.newToday, hasLength(7));
        expect(tomorrow.backlog, containsAll(today.newToday));
        expect(tomorrow.date, tuesday);
      },
    );

    test('and the same word is never planned as new twice', () async {
      final engine = engineWith();
      for (var day = 0; day < 10; day++) {
        await engine.openDay(addDays(monday, day));
      }

      final all = <String>[
        for (final entry in store.plan.entries)
          if (entry.key.endsWith('/new')) ...entry.value,
      ];

      expect(all.toSet(), hasLength(all.length), reason: 'a word repeated');
    });
  });

  group('the block order (BR-PLAN-02)', () {
    test('revise comes before new', () async {
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(uid: 'old', stability: 1, lastReview: monday),
      ];

      final plan = await engineWith().openDay(monday);

      expect(plan.wordBlocks.map((b) => b.$1), <PlanKind>[
        PlanKind.revise,
        PlanKind.newWord,
      ]);
      expect(plan.wordBlocks.first.$2, plan.revise);
    });

    test('and wordBlocks does not pretend to be the whole day', () async {
      // `PlanKind` has no value for grammar or sentences, so the accessor
      // cannot name them. The name has to say so, or a screen rendering it
      // silently drops the grammar block.
      store.grammarDue = <String>['g1'];

      final plan = await engineWith().openDay(monday);

      expect(plan.wordBlocks, hasLength(2));
      expect(plan.grammarDue, <String>['g1'], reason: 'read on its own');
    });

    test('grammar due is carried', () async {
      store.grammarDue = <String>['g1', 'g2'];
      expect((await engineWith().openDay(monday)).grammarDue, <String>[
        'g1',
        'g2',
      ]);
    });
  });

  group('#79 joined to the store', () {
    // `plan_stats_test.dart` covers the rules and `plan_store_test.dart` the
    // queries. These are the four methods that put the two together, which
    // nothing exercised until the review pointed it out.

    test('the streak reads the mask from the active step', () async {
      // A weekday-only learner keeps their streak across the weekend. With
      // the wrong mask the Saturday gap ends it.
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: 0x1F,
      );
      store.active = <PlanDate>{
        for (final day in <int>[0, 1, 2, 3, 4, 7]) addDays(monday, day),
      };

      expect(await engineWith().streak(addDays(monday, 7)), 6);
    });

    test(
      'BR-PLAN-01 #377 turning Sunday on keeps the streak and the best one',
      () async {
        // Mon–Sat for two weeks, Sundays rested. Then, on the third Monday
        // before studying, Sunday turns on from tomorrow.
        store.enrollment = const ActiveStep(
          sublevelCode: 'A1.1',
          startedOn: monday,
          dailyNew: 7,
          studyDaysMask: PlanEngine.allDays,
        );
        store.active = <PlanDate>{
          for (var day = 0; day < 14; day++)
            if (day % 7 != 6) addDays(monday, day),
        };
        final today = addDays(monday, 14);
        store.masks = withMask(
          const <MaskSpan>[],
          previous: 0x3F,
          mask: PlanEngine.allDays,
          from: addDays(today, 1),
        );
        expect(await engineWith().streak(today), 12, reason: 'Sundays rested');
        expect(await engineWith().bestStreak(today), 12);
      },
    );

    test('#377 a day after the change is judged by the new mask', () async {
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: PlanEngine.allDays,
      );
      // Mon–Sat, then every day from the second Monday: the second Sunday
      // is a study day, and missing it ends the streak.
      store.masks = <MaskSpan>[
        (from: '', mask: 0x3F),
        (from: addDays(monday, 7), mask: PlanEngine.allDays),
      ];
      store.active = <PlanDate>{
        for (var day = 0; day < 14; day++)
          if (day != 13) addDays(monday, day),
      };
      expect(await engineWith().streak(addDays(monday, 14)), 0);
    });

    test('#377 maskOn, withMask and the stored form', () {
      final history = withMask(
        const <MaskSpan>[],
        previous: 0x3F,
        mask: 0x7F,
        from: '2026-03-10',
      );
      expect(maskOn('2026-03-09', history, 1), 0x3F);
      expect(maskOn('2026-03-10', history, 1), 0x7F);
      expect(maskOn('2026-03-10', const <MaskSpan>[], 1), 1, reason: 'none');
      expect(decodeMaskHistory(encodeMaskHistory(history)), history);
      expect(decodeMaskHistory('not json'), isEmpty);
      // A second change on the same day replaces the first.
      final again = withMask(
        history,
        previous: 0x7F,
        mask: 0x1F,
        from: '2026-03-10',
      );
      expect(again.map((s) => s.mask), <int>[0x3F, 0x1F]);
    });

    test('and falls back to every day with no enrolment', () async {
      store.enrollment = null;
      store.active = <PlanDate>{monday, addDays(monday, 1)};

      expect(await engineWith().streak(addDays(monday, 1)), 2);
    });

    test('the schedule check divides by the enrolment pace', () async {
      // Not the setting: BR-PLAN-08 freezes the pace per enrolment, and these
      // days were planned at whatever it was then.
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 5,
        studyDaysMask: PlanEngine.allDays,
      );
      await engineWith().openDay(addDays(monday, 2));

      final status = await engineWith().scheduleCheck(addDays(monday, 2));

      expect(status.planned, 15, reason: 'three days at five');
      expect(status.introduced, 0);
      expect(status.daysBehind, 3.0);
    });

    test('and between steps it still reports a real number', () async {
      // Finishing a step with auto-advance off leaves no enrolment. Zero
      // there would print "0 days behind" beside "not on schedule".
      await engineWith().openDay(monday);
      store.enrollment = null;

      final status = await engineWith().scheduleCheck(
        monday,
        fallbackDailyNew: 7,
      );

      expect(status.behind, 7);
      expect(status.onSchedule, isFalse);
      expect(status.daysBehind, 1.0);
    });

    test('the estimate uses the defaults under seven sessions', () async {
      store.measured = const MeasuredSeconds(sessions: 6, newWord: 10);
      final plan = await engineWith().openDay(monday);

      expect(
        await engineWith().estimate(plan),
        const Duration(seconds: 45 * 7),
        reason: 'six sessions is not enough to trust the learner timings',
      );
    });

    test('and the learner timings at seven', () async {
      store.measured = const MeasuredSeconds(sessions: 7, newWord: 10);
      final plan = await engineWith().openDay(monday);

      expect(await engineWith().estimate(plan), const Duration(seconds: 70));
    });

    test('a timing that could not be measured keeps its default', () async {
      store.candidates = <RevisionCandidate>[
        const RevisionCandidate(uid: 'seen', stability: 5, lastReview: monday),
      ];
      store.measured = const MeasuredSeconds(sessions: 7, newWord: 10);
      final plan = await engineWith().openDay(monday);

      expect(
        await engineWith().estimate(plan),
        const Duration(seconds: 70 + 25),
        reason: 'the revision keeps the 25-second default',
      );
    });

    test('the day is complete once nothing is open', () async {
      final plan = await engineWith().openDay(monday);
      store.open[monday] = 3;

      expect(await engineWith().isDayComplete(plan), isFalse);

      store.open[monday] = 0;
      expect(await engineWith().isDayComplete(plan), isTrue);
    });

    test('and grammar still due keeps it open', () async {
      store.grammarDue = <String>['g1'];
      final plan = await engineWith().openDay(monday);
      store.open[monday] = 0;

      expect(await engineWith().isDayComplete(plan), isFalse);
    });

    test('a rest day is complete with the plan untouched', () async {
      store.enrollment = const ActiveStep(
        sublevelCode: 'A1.1',
        startedOn: monday,
        dailyNew: 7,
        studyDaysMask: 0x1F,
      );
      final saturday = addDays(monday, 5);
      final plan = await engineWith().openDay(saturday);
      store.open[saturday] = 4;

      expect(plan.isStudyDay, isFalse);
      expect(await engineWith().isDayComplete(plan), isTrue);
    });
  });

  group('the date helpers', () {
    test('a day is added on the calendar, not in hours', () {
      // `Duration(days: 1)` drifts by an hour across a DST change; in October
      // it lands on the previous day.
      for (final date in const <String>['2026-03-29', '2026-10-25']) {
        expect(daysBetween(date, addDays(date, 1)), 1, reason: date);
      }
    });

    test('it crosses months and years', () {
      expect(addDays('2026-01-31', 1), '2026-02-01');
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
      expect(addDays('2024-03-01', -1), '2024-02-29', reason: 'a leap year');
    });

    test('a date sorts as a string, which is what the queries rely on', () {
      final dates = <String>[
        for (var i = 0; i < 400; i += 17) addDays('2026-01-01', i),
      ];
      final sorted = <String>[...dates]..sort();

      expect(sorted, dates);
    });

    test('a malformed date is refused rather than silently wrong', () {
      expect(() => parsePlanDate('2026-03'), throwsArgumentError);
      expect(() => parsePlanDate(''), throwsArgumentError);
    });

    test('planDate pads, so the string sort holds in single digits', () {
      expect(planDate(DateTime(2026, 3, 4)), '2026-03-04');
      expect(planDate(DateTime(999, 1, 2)), '0999-01-02');
    });
  });
}

/// The store, as a few maps.
class FakeStore implements PlanStore {
  ActiveStep? enrollment;
  List<String> vocabulary = <String>[];
  List<RevisionCandidate> candidates = <RevisionCandidate>[];
  List<String> grammarDue = <String>[];
  PlanDate? lastPlanned;
  int? plannedStudyDays;

  /// `date/kind` to the uids planned.
  final Map<String, List<String>> plan = <String, List<String>>{};

  final Set<String> _everPlannedNew = <String>{};

  @override
  Future<ActiveStep?> activeStep() async => enrollment;

  @override
  Future<List<String>> unplannedWords(
    String sublevelCode, {
    required int limit,
  }) async => <String>[
    for (final uid in wordsByStep[sublevelCode] ?? vocabulary)
      if (!_everPlannedNew.contains(uid)) uid,
  ].take(limit).toList();

  @override
  Future<List<RevisionCandidate>> revisionCandidates() async => candidates;

  @override
  Future<List<String>> plannedOn(PlanDate date, PlanKind kind) async =>
      <String>[...?plan['$date/${kind.wire}']];

  @override
  Future<List<String>> grammarDueOn(PlanDate date) async => grammarDue;

  @override
  Future<void> addToPlan(
    PlanDate date,
    PlanKind kind,
    List<String> uids,
  ) async {
    final key = '$date/${kind.wire}';
    final existing = plan.putIfAbsent(key, () => <String>[]);
    for (final uid in uids) {
      if (existing.contains(uid)) continue;
      existing.add(uid);
      if (kind == PlanKind.newWord) _everPlannedNew.add(uid);
    }
  }

  /// Marks every row of [date] complete, so it leaves the backlog.
  void complete(PlanDate date) {
    for (final key in plan.keys.where((k) => k.startsWith('$date/'))) {
      _completed.addAll(plan[key]!);
    }
  }

  final Set<String> _completed = <String>{};

  @override
  Future<List<String>> backlogBefore(PlanDate today) async => <String>[
    for (final entry in plan.entries)
      if (entry.key.endsWith('/new') &&
          daysBetween(entry.key.split('/').first, today) > 0)
        for (final uid in entry.value)
          if (!_completed.contains(uid)) uid,
  ];

  @override
  Future<PlanDate?> lastPlannedDate() async => lastPlanned;

  @override
  Future<void> setLastPlannedDate(PlanDate date) async => lastPlanned = date;

  @override
  Future<int?> plannedMask() async => plannedStudyDays;

  @override
  Future<void> setPlannedMask(int mask) async => plannedStudyDays = mask;

  /// The course, in order. `vocabulary` belongs to whichever step is active.
  List<String> course = <String>['A1.1', 'A1.2', 'A2.1'];

  /// Words per step, for the auto-advance tests. When a step is missing here
  /// it falls back to [vocabulary], which is what the single-step tests use.
  Map<String, List<String>> wordsByStep = <String, List<String>>{};

  final List<String> completed = <String>[];
  final List<ActiveStep> enrolled = <ActiveStep>[];

  @override
  Future<String?> stepAfter(String sublevelCode) async {
    final at = course.indexOf(sublevelCode);
    return at < 0 || at + 1 >= course.length ? null : course[at + 1];
  }

  @override
  Future<void> completeStep(String sublevelCode, PlanDate on) async {
    completed.add('$sublevelCode@$on');
    if (enrollment?.sublevelCode == sublevelCode) enrollment = null;
  }

  @override
  Future<void> enroll(ActiveStep step) async {
    enrolled.add(step);
    enrollment = step;
  }

  @override
  Future<bool> hasEverEnrolled() async =>
      enrollment != null || enrolled.isNotEmpty || completed.isNotEmpty;

  @override
  Future<String?> lastCompletedStep() async =>
      completed.isEmpty ? null : completed.last.split('@').first;

  /// Days with activity, for the streak.
  Set<PlanDate> active = <PlanDate>{};

  /// #377: the masks over time; empty, as before any change.
  List<MaskSpan> masks = <MaskSpan>[];

  @override
  Future<List<MaskSpan>> studyDaysHistory() async => masks;

  /// What the logs could measure, for the estimate.
  MeasuredSeconds measured = const MeasuredSeconds(sessions: 0);

  /// Plan rows of a day that are neither done nor skipped.
  final Map<PlanDate, int> open = <PlanDate, int>{};

  @override
  Future<Set<PlanDate>> activeDays(
    PlanDate today, {
    required int lookbackDays,
  }) async => <PlanDate>{
    for (final day in active)
      if (daysBetween(day, today) >= 0 &&
          daysBetween(day, today) <= lookbackDays)
        day,
  };

  @override
  Future<(int, int)> newItemProgress(PlanDate today) async {
    var planned = 0;
    for (final entry in plan.entries) {
      if (!entry.key.endsWith('/new')) continue;
      if (daysBetween(entry.key.split('/').first, today) < 0) continue;
      planned += entry.value.length;
    }
    return (planned, _completed.length);
  }

  @override
  Future<int> openPlanItems(PlanDate date) async =>
      open[date] ?? (plan['$date/new'] ?? const <String>[]).length;

  @override
  Future<MeasuredSeconds> measuredSeconds() async => measured;
}
