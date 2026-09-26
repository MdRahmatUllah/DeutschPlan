import 'dart:async';
import 'dart:io';

import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/setup_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/domain/plan_engine.dart'
    show MaskSpan, addDays, decodeMaskHistory, planDate;
import 'package:drift/drift.dart' show DatabaseConnection, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:drift/drift.dart' as drift show Table, TableInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../db/content_fixture.dart';
import '../services/fake_tts.dart';

/// T1's data, against a real plan — #95.
void main() {
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late DateTime now;
  late ProviderContainer container;
  var voiceReady = false;

  const today = '2026-09-21';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_today');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    // The plan below revises r1 and r2 and has b1 and b2 waiting: words of
    // the step finished in August. The course must have them, or they are a
    // content update's removed words and hidden (BR-CONTENT-02).
    final raw = sqlite.sqlite3.open(content.path);
    try {
      for (final (i, uid) in <String>['r1', 'r2', 'b1', 'b2'].indexed) {
        raw.execute(
          '''
INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel,
                   german, english, search_key, search_key_alt)
VALUES (?, 'A0.9', 'A1', ?, ?, ?, ?, ?, ?)
''',
          <Object>[uid, 90 + i, i + 1, uid, uid, uid, uid],
        );
      }
    } finally {
      raw.close();
    }
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();

    // A1.1 since the 1st, after a first step finished in August, and planned
    // through today already, so openDay has nothing to add and the rows below
    // are the whole plan.
    await db.customStatement(
      "INSERT INTO enrollments VALUES ('A0.9', '2026-08-25', 7, 127, "
      "'2026-08-31'), ('A1.1', '2026-09-01', 7, 127, NULL)",
    );
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 9, 21),
    );
    await settings.write(SettingKeys.learnerName, 'Maruf');
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, completed_at, skipped) VALUES
  ('$today', 'r1', 'revise', 'A1.1', '2026-09-21T07:00:00', 0),
  ('$today', 'r2', 'revise', 'A1.1', NULL, 0),
  ('$today', '${ContentFixture.haus}', 'new', 'A1.1', NULL, 0),
  ('$today', '${ContentFixture.tuer}', 'new', 'A1.1', NULL, 1),
  ('2026-09-15', 'b1', 'new', 'A1.1', NULL, 0),
  ('2026-09-16', 'b2', 'new', 'A1.1', NULL, 0)
''');

    now = DateTime(2026, 9, 21, 8);
    voiceReady = false;
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => now),
        // The model files live outside the test; whether they are there is
        // the one thing about them Today asks.
        voiceInstalledProvider.overrideWith((ref) async => voiceReady),
      ],
    );
    // Held open, as the screen holds it: an auto-dispose provider nobody
    // listens to would be rebuilt from scratch on every read.
    container.listen(todayViewProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await settings.dispose();
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  test('FR-T1-01 it renders from the persisted plan', () async {
    final view = await container.read(todayViewProvider.future);

    expect(view.date, today);
    expect(view.step, 'A1.1');
    expect(view.revise.total, 2);
    expect(view.newToday.total, 2);
    expect(view.openRevise, <String>['r2']);
    // A skipped card is not waiting, the way BR-PLAN-10 counts it.
    expect(view.openNew, <String>[ContentFixture.haus]);
  });

  test(
    'FR-T1-02 the ring is done over revise + new + grammar + sentences',
    () async {
      final view = await container.read(todayViewProvider.future);

      // r1 done; tuer skipped; haus and r2 open. g1 is the only grammar topic
      // and has never been practised, so nothing is due.
      expect(view.completed, 2);
      expect(view.total, 4);
      expect(view.left, 2);
    },
  );

  test('the backlog count follows the backlog, not the plan at dawn', () async {
    expect((await container.read(todayViewProvider.future)).backlog, 2);

    // A word studied from T4: its own day's row completes.
    await db.customUpdate(
      "UPDATE plan_items SET completed_at = '2026-09-21T08:00:00Z' "
      "WHERE plan_date = '2026-09-15'",
      updates: <drift.TableInfo<drift.Table, Object?>>{db.planItems},
    );
    await pumpEventQueue();

    final view = await container.read(todayViewProvider.future);
    expect(view.backlog, 1);
    expect(view.backlogFrom, '2026-09-16');
    expect(view.backlogTo, '2026-09-16');
  });

  test('BR-PLAN-09 the estimate is for what is left', () async {
    final view = await container.read(todayViewProvider.future);

    // One revision and one new word open: 25 s + 45 s.
    expect(view.estimate, const Duration(seconds: 70));
    expect(view.estimateMinutes, 2);
  });

  test('the ring card and the section cards read the course', () async {
    final view = await container.read(todayViewProvider.future);

    // From the first step's start: a new step does not restart the course.
    expect(view.courseDay, 28, reason: '25 August is day 1');
    expect(view.stepWords.total, 2, reason: "A1.1's two words");
    expect(view.newCategory, 'Wohnen');
    expect(view.backlog, 2);
    expect(view.backlogFrom, '2026-09-15');
    expect(view.backlogTo, '2026-09-16');
    expect(view.grammar?.uid, 'g1');
    expect(view.grammar?.rule, 'The verb is second.');
    expect(view.learnerName, 'Maruf');
    expect(view.hour, 8);
  });

  test('a finished card moves the ring without being asked', () async {
    await container.read(todayViewProvider.future);

    // Through drift, as a rating writes it, so the table's watchers hear.
    await db.customUpdate(
      "UPDATE plan_items SET completed_at = '2026-09-21T08:10:00' "
      "WHERE word_uid = 'r2'",
      updates: <TableInfo<Table, Object?>>{db.planItems},
    );
    await pumpEventQueue();
    final view = await container.read(todayViewProvider.future);

    expect(view.revise.done, 2);
    expect(view.openRevise, isEmpty);
  });

  test(
    'a topic practised in L15 leaves Grammar due and fills the ring',
    () async {
      await db.customUpdate(
        'INSERT INTO grammar_state '
        '(grammar_uid, status, due, stability, reps, last_review) '
        "VALUES ('g1', 'learning', '$today', 1, 1, '2026-09-20T09:00:00Z')",
        updates: <TableInfo<Table, Object?>>{db.grammarState},
      );
      // The day opens with it due.
      container.invalidate(todayPlanProvider);
      var view = await container.read(todayViewProvider.future);
      expect(view.grammarDue, <String>['g1']);
      expect(view.completed, 2);
      expect(view.total, 5);
      final before = view.estimate;

      await container
          .read(grammarRatingServiceProvider)
          .ratePractice('g1', items: 5, correct: 5);
      await pumpEventQueue();
      view = await container.read(todayViewProvider.future);

      expect(view.grammarDue, isEmpty, reason: 'not offered again today');
      expect(view.grammarDone, 1);
      expect(view.completed, 3);
      expect(view.total, 5, reason: 'the ring does not shrink');
      expect(view.estimate, lessThan(before));
    },
  );

  test('a topic falling due after the day opened waits for tomorrow', () async {
    await db.customUpdate(
      'INSERT INTO grammar_state (grammar_uid, status, due, last_review) '
      "VALUES ('g1', 'suspended', '$today', '2026-09-20T09:00:00Z')",
      updates: <TableInfo<Table, Object?>>{db.grammarState},
    );
    container.invalidate(todayPlanProvider);
    expect((await container.read(todayViewProvider.future)).total, 4);

    // Resumed mid-day, the way a resumed word waits for tomorrow's plan.
    await db.customUpdate(
      "UPDATE grammar_state SET status = 'learning' WHERE grammar_uid = 'g1'",
      updates: <TableInfo<Table, Object?>>{db.grammarState},
    );
    await pumpEventQueue();
    final view = await container.read(todayViewProvider.future);

    expect(view.grammarDue, isEmpty);
    expect(view.total, 4);
  });

  group('#80 practice sentences', () {
    setUp(() async {
      // Haus is learned; its two examples are the only candidates, so one
      // sentence — one per headword.
      await db.customStatement(
        "INSERT INTO word_state (word_uid, status, introduced_on) VALUES "
        "('${ContentFixture.haus}', 'learning', '2026-09-10')",
      );
      container.invalidate(todayViewProvider);
    });

    test("FR-T5-01 Today counts the day's sentences, picked once", () async {
      final view = await container.read(todayViewProvider.future);
      expect(view.sentences.total, 1);
      expect(view.sentences.done, 0);

      final logged = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sentence_log WHERE shown_on = '$today'",
          )
          .getSingle();
      expect(logged.read<int>('n'), 1, reason: 'kept for the day');
    });

    test('a rated sentence moves the card, and the estimate', () async {
      final before = await container.read(todayViewProvider.future);
      // BR-PLAN-09: an open sentence is 40 s on top of the 70 s of words.
      expect(before.estimate, const Duration(seconds: 110));

      await db.customUpdate(
        "UPDATE sentence_log SET self_rating = 2 WHERE shown_on = '$today'",
        updates: <TableInfo<Table, Object?>>{db.sentenceLog},
      );
      await pumpEventQueue();
      final after = await container.read(todayViewProvider.future);

      expect(after.sentences.done, 1);
      expect(after.estimate, const Duration(seconds: 70));
    });
  });

  group('#96 all done', () {
    Future<void> finishTheDay() async {
      await db.customUpdate(
        "UPDATE plan_items SET completed_at = '2026-09-21T09:00:00' "
        "WHERE plan_date = '$today' AND completed_at IS NULL AND skipped = 0",
        updates: <TableInfo<Table, Object?>>{db.planItems},
      );
      await pumpEventQueue();
    }

    test('before the day is done there is no Tomorrow', () async {
      final view = await container.read(todayViewProvider.future);
      expect(view.isDone, isFalse);
      expect(view.tomorrow, isNull);
    });

    test('Tomorrow is a dry run of openDay(tomorrow) that writes nothing', () async {
      // Today's recorded study days (#147), which tomorrow's dry run plans
      // past but must not touch: a Monday, as a mask of its own.
      await settings.write(SettingKeys.plannedStudyDays, 99);
      await finishTheDay();
      final view = await container.read(todayViewProvider.future);

      expect(view.isDone, isTrue);
      // A1.1's two words are both planned, so tomorrow runs out of it and
      // starts A1.2 — whose one word is tomorrow's new word.
      expect(view.tomorrow?.newWords, 1);
      expect(view.tomorrow?.category, 'Wohnen');

      final rows = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM plan_items WHERE plan_date > '$today'",
          )
          .getSingle();
      expect(rows.read<int>('n'), 0, reason: 'nothing planned for real');
      final open = await db
          .customSelect(
            'SELECT sublevel_code FROM enrollments WHERE completed_on IS NULL',
          )
          .get();
      expect(open.single.read<String>('sublevel_code'), 'A1.1');
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        today,
        reason: 'planning did not move on',
      );
      expect(settings.read(SettingKeys.plannedStudyDays), 99);
    });

    test('BR-PLAN-01 it knows when tomorrow is a rest day', () async {
      // Tomorrow, the 22nd, is a Tuesday: study every day but Tuesday.
      await db.customStatement(
        "UPDATE enrollments SET study_days_mask = 125 WHERE sublevel_code = 'A1.1'",
      );
      await finishTheDay();
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.tomorrow?.restDay, isTrue);
    });

    test('it counts the minutes studied today', () async {
      await db.customStatement(
        "INSERT INTO daily_stats (day, seconds) VALUES ('$today', 750)",
      );
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);
      expect(view.minutes, 12);
    });
  });

  test(
    'BR-PLAN-08 today turned off in M5 is still a study day (#147)',
    () async {
      // Today planned from scratch, as every morning, at one new word so the
      // fixture's three don't run the step out (no step is every day).
      await db.customStatement(
        "UPDATE enrollments SET daily_new = 1 WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        "DELETE FROM plan_items WHERE plan_date = '$today'",
      );
      await settings.write(
        SettingKeys.lastPlannedDate,
        DateTime.utc(2026, 9, 20),
      );
      container
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);
      final before = await container.read(todayViewProvider.future);
      expect(before.isStudyDay, isTrue);

      // Monday, today, off: M5's writer.
      await container
          .read(setupRepositoryProvider)
          .setStudyDays(126, today: today);
      // #377: the change is kept from tomorrow, the old mask before it.
      expect(
        decodeMaskHistory(settings.read(SettingKeys.studyDaysHistory)),
        <MaskSpan>[(from: '', mask: 127), (from: addDays(today, 1), mask: 126)],
      );
      container
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);

      final after = await container.read(todayViewProvider.future);
      expect(after.step, 'A1.1', reason: 'still the step M5 changed');
      expect(after.isStudyDay, isTrue);
      expect(after.newToday.total, before.newToday.total);
      expect(after.newToday.total, 1);
    },
  );

  test('#377 restart setup keeps the study days it changes, from today '
      'when today is not planned yet', () async {
    await settings.write(
      SettingKeys.lastPlannedDate,
      DateTime.utc(2026, 9, 20),
    );
    await container
        .read(setupRepositoryProvider)
        .commit(
          const SetupChoice(
            step: 'A1.1',
            dailyNew: 5,
            reviseCount: 20,
            studyDaysMask: 0x1F,
            reminderOn: false,
            reminderTime: (hour: 19, minute: 0),
          ),
          today: today,
        );
    expect(
      decodeMaskHistory(settings.read(SettingKeys.studyDaysHistory)),
      <MaskSpan>[(from: '', mask: 127), (from: today, mask: 0x1F)],
    );
  });

  test('#460 at the start the voice is warmed, and today\'s first cards '
      'made: its revisions, then its new words', () async {
    final voice = FakePrefetchTts();
    final start = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        clockProvider.overrideWithValue(() => now),
        voiceInstalledProvider.overrideWith((ref) async => true),
        fakeVoice(voice),
      ],
    );
    addTearDown(start.dispose);

    await warmTodaysVoice(start);
    expect(voice.warms, 1);
    // r2 is open to revise, Haus new; Tür was skipped to the backlog.
    expect(voice.prepared.single, <String>['r2', 'das Haus']);
  });

  group('#97 a rest day', () {
    setUp(() async {
      // Monday the 21st off, and today not planned yet: the rest day opens
      // from scratch, with three words due by tomorrow.
      await db.customStatement(
        "UPDATE enrollments SET study_days_mask = 126 WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        "DELETE FROM plan_items WHERE plan_date = '$today'",
      );
      await settings.write(
        SettingKeys.lastPlannedDate,
        DateTime.utc(2026, 9, 20),
      );
      // Course words: a plan row takes its step from the course, so a uid
      // the course does not have is never planned.
      await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability, reps, last_review) VALUES
  ('${ContentFixture.haus}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.tuer}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.strasse}', 'learning', '2026-09-10', '2026-09-22', 3, 2, '2026-09-19'),
  ('paused', 'suspended', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19')
''');
      // The outer setUp already started a build, which raced these writes;
      // start again from what they left.
      container
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);
    });

    test('BR-PLAN-01 no new words and no backlog growth', () async {
      final view = await container.read(todayViewProvider.future);

      expect(view.isRestDay, isTrue);
      expect(view.newToday.total, 0);
      expect(view.backlog, 2, reason: 'what was waiting still is, no more');
    });

    test('it knows what revising anyway would take off tomorrow', () async {
      final view = await container.read(todayViewProvider.future);

      expect(view.dueTomorrow, 3, reason: 'a suspended word is not due');
      expect(view.revise.open, 3, reason: 'revisions are still picked');
      expect(view.dueTomorrowIfRevised, 0);
    });

    test('#345 tomorrow off too: what is due by the next study day, and '
        'which day that is', () async {
      // Monday and Tuesday off: Wednesday the 23rd, with Straße due on it.
      await db.customStatement(
        "UPDATE enrollments SET study_days_mask = 124 WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        "UPDATE word_state SET due = '2026-09-23' "
        "WHERE word_uid = '${ContentFixture.strasse}'",
      );
      container
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.nextStudyDay, '2026-09-23');
      expect(view.dueTomorrow, 3, reason: 'by Wednesday; by Tuesday it is 2');
    });
  });

  group('FR-T1-06 the contextual card, from what is stored', () {
    test('without the on-device voice, it is offered', () async {
      await container.read(voiceInstalledProvider.future);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual?.kind, ContextualKind.voice);
    });

    test('with it installed, there is nothing to offer', () async {
      voiceReady = true;
      container.invalidate(voiceInstalledProvider);
      await container.read(voiceInstalledProvider.future);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual, isNull);
    });

    test('Today does not wait for the voice check', () async {
      // A check that never answers: the view still comes, without the card.
      final hanging = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => now),
          voiceInstalledProvider.overrideWith(
            (ref) => Completer<bool>().future,
          ),
        ],
      );
      addTearDown(hanging.dispose);
      hanging.listen(todayViewProvider, (_, _) {});

      final view = await hanging.read(todayViewProvider.future);
      expect(view.date, today);
      expect(view.contextual, isNull);
    });

    test('the voice is not installed until its files are there', () async {
      final support = Directory.systemTemp.createTempSync('deutschplan_voice');
      addTearDown(() => support.deleteSync(recursive: true));
      final models = ProviderContainer(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          modelRepositoryProvider.overrideWithValue(
            ModelRepository(settings, support: support),
          ),
        ],
      );
      addTearDown(models.dispose);

      expect(await models.read(voiceInstalledProvider.future), isFalse);
    });

    test('a dismissal in dismissed_cards is honoured', () async {
      await container.read(voiceInstalledProvider.future);
      await settings.write(SettingKeys.dismissedCards, '["voice"]');
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);
      expect(view.contextual, isNull);
    });

    test('a malformed dismissed_cards does not take Today down', () async {
      await container.read(voiceInstalledProvider.future);
      await settings.write(SettingKeys.dismissedCards, '{not json');
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.date, today);
      expect(view.contextual?.kind, ContextualKind.voice);
    });

    test(
      'BR-CONTENT-03 an unseen update comes first, with its counts',
      () async {
        await db.customStatement(
          "INSERT INTO content_updates (version, changed_json, seen) VALUES "
          "('202609201200', '{\"added\":[\"a\",\"b\"],\"removed\":[\"c\"],\"changed\":[]}', 0)",
        );
        container.invalidate(todayViewProvider);
        final view = await container.read(todayViewProvider.future);

        final offer = view.contextual!;
        expect(offer.kind, ContextualKind.contentUpdate);
        expect((offer.added, offer.removed, offer.changed), (2, 1, 0));
        expect(offer.version, '202609201200');
      },
    );
  });

  group('FR-T1-05 midnight', () {
    test('a new date re-plans for it', () async {
      await container.read(todayViewProvider.future);

      now = DateTime(2026, 9, 22, 0, 5);
      container.invalidate(todayProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.date, '2026-09-22');
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        '2026-09-22',
        reason: 'openDay ran for the new day',
      );
    });

    test('the same date plans nothing again', () async {
      var plans = 0;
      container.listen(todayPlanProvider, (_, next) {
        if (next.hasValue && !next.isLoading) plans++;
      });
      await container.read(todayViewProvider.future);
      final before = plans;

      now = DateTime(2026, 9, 21, 23, 55);
      container.invalidate(todayProvider);
      await container.read(todayViewProvider.future);
      await pumpEventQueue();

      expect(plans, before);
    });
  });

  /// Every plan row, for a before and after.
  Future<List<Map<String, Object?>>> planRows() async => <Map<String, Object?>>[
    for (final row
        in await db
            .customSelect(
              'SELECT plan_date, word_uid, kind, completed_at, skipped '
              'FROM plan_items ORDER BY plan_date, kind, word_uid',
            )
            .get())
      row.data,
  ];

  /// Today as the clock now says it is.
  Future<TodayView> at(DateTime then) {
    now = then;
    container.invalidate(todayProvider);
    return container.read(todayViewProvider.future);
  }

  group('Z05 date and time-zone changes never duplicate or drop a day', () {
    test('BR-PLAN-04 the clock back a day, as a zone to the west moves it: '
        'that day reopens as it was, and nothing is planned again', () async {
      // Yesterday as it was left: one revision, done.
      await db.customStatement(
        'INSERT INTO plan_items '
        '(plan_date, word_uid, kind, sublevel_code, completed_at) VALUES '
        "('2026-09-20', '${ContentFixture.strasse}', 'revise', 'A1.2', "
        "'2026-09-20T08:00:00')",
      );
      await container.read(todayViewProvider.future);
      final before = await planRows();

      final yesterday = await at(DateTime(2026, 9, 20, 23, 30));

      expect(yesterday.date, '2026-09-20');
      expect((yesterday.revise.done, yesterday.revise.total), (1, 1));
      expect(yesterday.newToday.total, 0);
      expect(await planRows(), before, reason: 'no row added, none twice');
      expect(
        planDate(settings.read(SettingKeys.lastPlannedDate)!),
        today,
        reason: 'planning never goes backwards (#346)',
      );
    });

    test('BR-PLAN-04 and forward again: the later day, unchanged', () async {
      final first = await container.read(todayViewProvider.future);
      final before = await planRows();

      await at(DateTime(2026, 9, 20, 23, 30));
      final again = await at(DateTime(2026, 9, 21, 0, 30));

      expect(again.date, today);
      expect(again.openRevise, first.openRevise);
      expect(again.openNew, first.openNew);
      expect(
        (again.revise.total, again.newToday.total, again.completed),
        (first.revise.total, first.newToday.total, first.completed),
      );
      expect(await planRows(), before);
    });

    test('BR-PLAN-05 a jump past backlog_catchup_days plans only the window, '
        'each day once', () async {
      // One a day, from forty more A1.1 words: the step outlasts the window.
      await db.customStatement(
        "UPDATE enrollments SET daily_new = 1 WHERE sublevel_code = 'A1.1'",
      );
      for (var i = 1; i <= 40; i++) {
        await db.customStatement(
          'INSERT INTO c.words (uid, sublevel_code, level_code, seq, '
          'seq_in_sublevel, german, english, search_key, search_key_alt) '
          "VALUES (?, 'A1.1', 'A1', ?, ?, ?, ?, ?, ?)",
          <Object>['x$i', 200 + i, 10 + i, 'Wort$i', 'word$i', 'wort$i', 'x$i'],
        );
      }
      await container.read(todayViewProvider.future);

      const back = '2026-11-05';
      final later = await at(DateTime(2026, 11, 5, 9));
      final days = await db
          .customSelect(
            'SELECT plan_date, COUNT(*) AS n, COUNT(DISTINCT word_uid) AS w '
            "FROM plan_items WHERE kind = 'new' AND plan_date > '$today' "
            'GROUP BY plan_date ORDER BY plan_date',
          )
          .get();

      expect(later.date, back);
      expect(later.newToday.total, 1);
      expect(
        <(String, int, int)>[
          for (final row in days)
            (
              row.read<String>('plan_date'),
              row.read<int>('n'),
              row.read<int>('w'),
            ),
        ],
        <(String, int, int)>[
          for (var i = 30; i >= 0; i--) (addDays(back, -i), 1, 1),
        ],
        reason: 'the 30 days before it and the day itself, one word each',
      );

      // Opened again, the same day plans nothing more.
      final before = await planRows();
      container.invalidate(todayPlanProvider);
      await container.read(todayViewProvider.future);
      expect(await planRows(), before);
    });
  });

  group('Z05 BR-COURSE-05 the course finished', () {
    setUp(() async {
      // A1.2, the fixture's last step, finished yesterday after A1.1; today
      // not planned yet, with three words due.
      await db.customStatement(
        "UPDATE enrollments SET completed_on = '2026-09-20' "
        "WHERE sublevel_code = 'A1.1'",
      );
      await db.customStatement(
        "INSERT INTO enrollments VALUES ('A1.2', '2026-09-15', 7, 127, "
        "'2026-09-20')",
      );
      await db.customStatement(
        "DELETE FROM plan_items WHERE plan_date = '$today'",
      );
      await settings.write(
        SettingKeys.lastPlannedDate,
        DateTime.utc(2026, 9, 20),
      );
      await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability, reps, last_review) VALUES
  ('${ContentFixture.haus}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.tuer}', 'learning', '2026-09-10', '2026-09-21', 2, 2, '2026-09-19'),
  ('${ContentFixture.strasse}', 'learning', '2026-09-10', '2026-09-22', 3, 2, '2026-09-19')
''');
      // The voice is in: its card is not what this is about.
      voiceReady = true;
      container
        ..invalidate(voiceInstalledProvider)
        ..invalidate(todayPlanProvider)
        ..invalidate(todayViewProvider);
      await container.read(voiceInstalledProvider.future);
    });

    test('FR-T1-01 Today is revision only, with the completion card', () async {
      final view = await container.read(todayViewProvider.future);

      expect(view.step, isNull);
      expect(view.revise.total, 3, reason: 'revision goes on');
      expect(view.newToday.total, 0);
      expect(view.backlog, 2, reason: 'what was waiting still is, no more');
      expect(view.contextual?.kind, ContextualKind.courseComplete);
    });

    test('BR-CONTENT-03 a content update still shows, ahead of it', () async {
      await db.customStatement(
        "INSERT INTO content_updates (version, changed_json, seen) VALUES "
        "('202609201200', '{\"added\":[],\"removed\":[\"c\"],\"changed\":[]}', 0)",
      );
      container.invalidate(todayViewProvider);
      final view = await container.read(todayViewProvider.future);

      expect(view.contextual?.kind, ContextualKind.contentUpdate);
    });
  });
}
