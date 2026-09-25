import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/word_of_day.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/services/widget_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;

import '../db/content_fixture.dart';
import '../features/today_fixtures.dart';

/// The native widgets' store without a phone: every snapshot saved.
class FakeWidgets implements WidgetStore {
  final List<String> saved = <String>[];

  /// A store that can't be written, as a phone without the plugin.
  bool fails = false;

  Map<String, Object?> get last =>
      jsonDecode(saved.last) as Map<String, Object?>;

  @override
  Future<void> save(String snapshot) async {
    if (fails) throw StateError('no widget store');
    saved.add(snapshot);
  }
}

/// #159: the home-screen widget's snapshot, and the word of the day.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('FR-X1-03 the word of the day', () {
    const words = <String>['uid-a', 'uid-b', 'uid-c', 'uid-d', 'uid-e'];

    test('the same all day, whatever order the words come in', () {
      final pick = wordOfDay(words, '2026-09-21');
      expect(wordOfDay(words.reversed.toList(), '2026-09-21'), pick);
      expect(words, contains(pick));
    });

    test('another on another day', () {
      final week = <String?>{
        for (var day = 21; day <= 27; day++) wordOfDay(words, '2026-09-$day'),
      };
      expect(week.length, greaterThan(1));
    });

    test('none without a candidate', () {
      expect(wordOfDay(const <String>[], '2026-09-21'), isNull);
    });
  });

  group('FR-X1-01 the snapshot', () {
    const word = (
      uid: 'uid-wohnung',
      article: 'die',
      german: 'Wohnung',
      meaning: 'flat, apartment',
    );

    test("today's ring, the step, the minutes and the word", () {
      final snapshot = widgetSnapshot(en, artboardToday(), word)
        ..remove('copy');
      expect(snapshot, <String, Object?>{
        'date': '2026-09-21',
        'step': 'A2.1',
        'remaining': 8,
        'total': 20,
        'minutes': 6,
        'done': false,
        'wordOfDay': <String, Object?>{
          'uid': 'uid-wohnung',
          'article': 'die',
          'german': 'Wohnung',
          'meaning': 'flat, apartment',
        },
        'tomorrow': null,
      });
    });

    test('a done day: the Lime check, and tomorrow', () {
      final snapshot = widgetSnapshot(en, artboardDone(), null);
      expect(snapshot['done'], isTrue);
      expect(snapshot['remaining'], 0);
      expect(snapshot['wordOfDay'], isNull);
      expect(snapshot['tomorrow'], <String, Object?>{
        'revise': 12,
        'newWords': 7,
        'minutes': 13,
      });
      expect(
        (snapshot['copy']! as Map<String, String>)['tomorrow'],
        'Tomorrow · 12 revisions · 7 new',
      );
    });

    test("#160 the widget's words, in the learner's language", () {
      final copy =
          widgetSnapshot(en, artboardToday(), word)['copy']!
              as Map<String, String>;
      expect(copy, <String, String>{
        'app': 'DeutschPlan',
        'left': '8 left',
        'leftStep': '8 left · A2.1',
        'progress': '12/20',
        'minutes': '≈ 6 min',
        'wordOfDay': 'Wort des Tages',
        'pronounce': 'Pronounce',
        'done': 'Done for today',
      });

      final bn = lookupAppLocalizations(const Locale('bn'));
      final bangla =
          widgetSnapshot(bn, artboardToday(), word)['copy']!
              as Map<String, String>;
      expect(bangla['left'], bn.widgetLeft(8));
      expect(bangla['pronounce'], bn.widgetPronounce);
    });
  });

  group('against a database', () {
    late Directory directory;
    late AppDatabase db;
    late SettingsRepository settings;
    late ProviderContainer container;
    late FakeWidgets widgets;

    const today = '2026-09-21';

    // Through drift, so the streams hear it as a rating would be heard.
    Future<void> state(String uid, String due, {String status = 'learning'}) =>
        db.customInsert(
          'INSERT INTO word_state (word_uid, status, stability, due, reps, '
          "introduced_on) VALUES ('$uid', '$status', 3, '$due', 2, "
          "'2026-09-01')",
          updates: {db.wordState},
        );

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_widget');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      db = AppDatabase.memory();
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      widgets = FakeWidgets();
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          todayProvider.overrideWithValue(today),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 8)),
          todayViewProvider.overrideWith((ref) async => artboardToday()),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
      directory.deleteSync(recursive: true);
    });

    Future<WidgetWord?> word() async {
      final listening = container.listen(widgetWordProvider.future, (_, _) {});
      addTearDown(listening.close);
      return listening.read();
    }

    test(
      'FR-X1-03 a learned word due within three days is a candidate',
      () async {
        await state(ContentFixture.haus, '2026-09-24');
        expect((await word())?.uid, ContentFixture.haus);
      },
    );

    test(
      'FR-X1-03 never a word due later, a To-do word or a suspended one',
      () async {
        await state(ContentFixture.haus, '2026-09-25');
        await db.customStatement(
          'INSERT INTO word_state (word_uid, status, due) '
          "VALUES ('${ContentFixture.tuer}', 'todo', '2026-09-21')",
        );
        await state(ContentFixture.strasse, '2026-09-21', status: 'suspended');
        expect(await word(), isNull);
      },
    );

    test('its meaning in the learner’s language', () async {
      await state(ContentFixture.haus, '2026-09-21');
      // As M3 changes it.
      final languages = container.read(languagesProvider.notifier);
      await languages.setMeaning(MeaningLanguage.english);
      expect((await word())?.meaning, 'house');
      expect((await word())?.german, 'Haus');
      expect((await word())?.article, 'das');

      await languages.setMeaning(MeaningLanguage.bangla);
      expect((await word())?.meaning, 'বাড়ি');

      await languages.setMeaning(MeaningLanguage.both);
      expect((await word())?.meaning, 'house · বাড়ি');
    });

    test('a background refresh saves it', () async {
      await state(ContentFixture.haus, '2026-09-22');
      await refreshWidget(container, widgets);
      expect(widgets.last['remaining'], 8);
      expect(
        (widgets.last['wordOfDay']! as Map<String, Object?>)['uid'],
        ContentFixture.haus,
      );
    });

    test('a store that fails costs the refresh, not its task', () async {
      widgets.fails = true;
      await expectLater(refreshWidget(container, widgets), completes);
    });

    test(
      'FR-X1-01 in the app: saved at once, and again as the word moves',
      () async {
        final following = followWidget(container, widgets);
        addTearDown(following.close);
        await pumpEventQueue();
        expect(widgets.saved, hasLength(1));
        expect(widgets.last['wordOfDay'], isNull);

        await state(ContentFixture.haus, '2026-09-21');
        await pumpEventQueue();
        expect(widgets.saved, hasLength(2));
        expect(
          (widgets.last['wordOfDay']! as Map<String, Object?>)['uid'],
          ContentFixture.haus,
        );
      },
    );

    test(
      '#365 a change of meaning language reaches the widget at once',
      () async {
        await state(ContentFixture.haus, '2026-09-21');
        final following = followWidget(container, widgets);
        addTearDown(following.close);
        await pumpEventQueue();
        String meaning() =>
            (widgets.last['wordOfDay']! as Map<String, Object?>)['meaning']!
                as String;
        expect(meaning(), 'house · বাড়ি');

        await container
            .read(languagesProvider.notifier)
            .setMeaning(MeaningLanguage.english);
        await pumpEventQueue();
        expect(meaning(), 'house');
      },
    );

    test("#160 and its words follow the app's language", () async {
      final following = followWidget(container, widgets);
      addTearDown(following.close);
      await pumpEventQueue();
      String left() =>
          (widgets.last['copy']! as Map<String, Object?>)['left']! as String;
      expect(left(), '8 left');

      await container.read(languagesProvider.notifier).setUi(UiLanguage.bangla);
      await pumpEventQueue();
      expect(left(), lookupAppLocalizations(const Locale('bn')).widgetLeft(8));
    });
  });

  group('#365 an app open across midnight', () {
    late Directory directory;
    late AppDatabase db;
    late SettingsRepository settings;
    late ProviderContainer container;
    late FakeWidgets widgets;
    late DateTime now;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('deutschplan_midnight');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      db = AppDatabase.memory();
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
      widgets = FakeWidgets();
      now = DateTime(2026, 9, 21, 23, 59);
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          clockProvider.overrideWithValue(() => now),
          // Today's view of whatever day todayProvider says, as T1's is.
          todayViewProvider.overrideWith(
            (ref) async => TodayView(
              date: ref.watch(todayProvider),
              hour: 0,
              revise: BlockProgress.none,
              newToday: BlockProgress.none,
              openRevise: const <String>[],
              openNew: const <String>[],
              grammarDue: const <String>[],
              backlog: 0,
              streak: 0,
              estimate: Duration.zero,
              courseDay: 1,
              stepWords: (done: 0, learning: 0, todo: 0, total: 0),
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
      directory.deleteSync(recursive: true);
    });

    test("never writes yesterday's date over the new day's", () async {
      final following = followWidget(container, widgets);
      addTearDown(following.close);
      await pumpEventQueue();
      expect(widgets.last['date'], '2026-09-21');

      now = DateTime(2026, 9, 22, 0, 1);
      // Any change after midnight: a word coming due.
      await db.customInsert(
        'INSERT INTO word_state (word_uid, status, stability, due, reps, '
        "introduced_on) VALUES ('${ContentFixture.haus}', 'learning', 3, "
        "'2026-09-22', 2, '2026-09-01')",
        updates: {db.wordState},
      );
      await pumpEventQueue();

      expect(widgets.last['date'], '2026-09-22');
      expect(<Object?>[
        for (final json in widgets.saved.skip(1)) jsonDecode(json),
      ], everyElement(containsPair('date', '2026-09-22')));
    });
  });
}
