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

  PlanEngine engineWith({int revise = 10, int catchup = 30}) => PlanEngine(
    store: store,
    reviseCount: revise,
    backlogCatchupDays: catchup,
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

  group('the first day', () {
    test('plans daily_new words and nothing before it', () async {
      final plan = await engineWith().openDay(monday);

      expect(plan.newToday, hasLength(7));
      expect(plan.newToday, <String>['w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7']);
      expect(plan.backlog, isEmpty, reason: 'nothing was missed yet');
      expect(plan.activeStep, 'A1.1');
      expect(plan.isStudyDay, isTrue);
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

    test('a step that runs out writes nothing for the days after it', () async {
      // #77 advances to the next step (BR-COURSE-05). Until then, running out
      // is the end of planning — not an empty plan written for every
      // remaining day.
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

      expect(plan.blocks.map((b) => b.$1), <PlanKind>[
        PlanKind.revise,
        PlanKind.newWord,
      ]);
      expect(plan.blocks.first.$2, plan.revise);
    });

    test('grammar due is carried', () async {
      store.grammarDue = <String>['g1', 'g2'];
      expect((await engineWith().openDay(monday)).grammarDue, <String>[
        'g1',
        'g2',
      ]);
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
    for (final uid in vocabulary)
      if (!_everPlannedNew.contains(uid)) uid,
  ].take(limit).toList();

  @override
  Future<List<RevisionCandidate>> revisionCandidates() async => candidates;

  @override
  Future<Set<String>> plannedOn(PlanDate date, PlanKind kind) async =>
      (plan['$date/${kind.wire}'] ?? const <String>[]).toSet();

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

  @override
  Future<List<String>> backlogBefore(PlanDate today) async => <String>[
    for (final entry in plan.entries)
      if (entry.key.endsWith('/new') &&
          daysBetween(entry.key.split('/').first, today) > 0)
        ...entry.value,
  ];

  @override
  Future<PlanDate?> lastPlannedDate() async => lastPlanned;

  @override
  Future<void> setLastPlannedDate(PlanDate date) async => lastPlanned = date;
}
