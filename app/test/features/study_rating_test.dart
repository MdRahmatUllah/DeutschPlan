import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/features/study/study_rating.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';

/// T2 · the rating bar, its interval previews and undo — #105.
void main() {
  const today = '2026-09-21';
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;
  const strasse = ContentFixture.strasse;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;
  var now = DateTime(2026, 9, 21, 9);

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Straße to revise — met twice already — and Haus and Tür new.
  Future<void> open() async {
    now = DateTime(2026, 9, 21, 9);
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_rate');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) VALUES
  ('$today', '$strasse', 'revise', 'A1.2'),
  ('$today', '$haus', 'new', 'A1.1'),
  ('$today', '$tuer', 'new', 'A1.1')
''');
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability,
  difficulty, reps, lapses, fsrs_state, last_review, card_mode)
VALUES ('$strasse', 'learning', '2026-09-10', '2026-09-21', 4.5, 5.2, 2, 0,
  2, '2026-09-15T08:00:00.000Z', 'plain')
''');
    settings = SettingsRepository(db);
    await settings.load();
    await settings.write(SettingKeys.autoplayHeadword, false);
  }

  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
    systemTtsProvider.overrideWithValue(_SilentTts()),
    clockProvider.overrideWithValue(() => now),
  ];

  const args = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
      SessionBlock(SessionBlockKind.newWords, <String>[haus, tuer]),
    ],
  );

  RatingService service() => RatingService(
    db,
    settings,
    PlanRepository(db),
    WordRepository(db, settings),
    () => now,
  );

  Future<Map<String, Object?>?> state(String uid) async =>
      (await db
              .customSelect("SELECT * FROM word_state WHERE word_uid = '$uid'")
              .getSingleOrNull())
          ?.data;

  Future<List<Map<String, Object?>>> log() async => <Map<String, Object?>>[
    for (final r
        in await db
            .customSelect(
              'SELECT word_uid, rating, source, scheduled_days FROM review_log',
            )
            .get())
      r.data,
  ];

  group('FR-T2-05 the previews', () {
    setUp(open);
    tearDown(() async {
      await settings.dispose();
      await db.close();
    });

    for (final uid in <String>[strasse, haus]) {
      test(
        'equal what the scheduler writes, for every rating ($uid)',
        () async {
          final preview = await service().preview(uid);
          for (final rating in Rating.values) {
            await service().rate(uid, rating, source: ReviewSource.daily);
            final written = (await log()).single['scheduled_days'];
            expect(written, preview[rating], reason: rating.name);
            await service().undo();
          }
        },
      );
    }

    test('lengthen from Again to Easy', () async {
      final preview = await service().preview(strasse);
      expect(
        preview[Rating.again]! <= preview[Rating.hard]! &&
            preview[Rating.hard]! <= preview[Rating.good]! &&
            preview[Rating.good]! <= preview[Rating.easy]!,
        isTrue,
        reason: '$preview',
      );
    });
  });

  group('FR-T2-02 a rating', () {
    late ProviderContainer container;
    late StudySession notifier;

    setUp(() async {
      await open();
      container = ProviderContainer(overrides: overrides());
      await container.read(studySessionProvider(args).future);
      notifier = container.read(studySessionProvider(args).notifier);
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
    });

    StudySessionState session() =>
        container.read(studySessionProvider(args)).value!;

    test('writes one review, completes the row, and moves on', () async {
      now = now.add(const Duration(seconds: 12));
      await notifier.rate(Rating.good);

      final rows = await log();
      expect(rows, hasLength(1));
      expect(rows.single['word_uid'], strasse);
      expect(rows.single['rating'], 3);
      expect(rows.single['source'], 'daily');
      final plan = await db
          .customSelect(
            "SELECT completed_at FROM plan_items WHERE word_uid = '$strasse'",
          )
          .getSingle();
      expect(plan.data['completed_at'], isNotNull);
      final stats = await db
          .customSelect('SELECT reviews_done, seconds FROM daily_stats')
          .getSingle();
      expect(stats.data, <String, Object?>{'reviews_done': 1, 'seconds': 12});
      expect(session().current?.uid, haus);
      expect(session().results[0], CardOutcome.good);
    });

    test('a new word counts as new, not as a review', () async {
      notifier.advance(CardOutcome.good);
      await notifier.rate(Rating.hard);
      expect((await log()).single['rating'], 2);
      final stats = await db
          .customSelect('SELECT new_done, reviews_done FROM daily_stats')
          .getSingle();
      expect(stats.data, <String, Object?>{'new_done': 1, 'reviews_done': 0});
      expect(session().results[1], CardOutcome.hard);
    });

    test("each card's time starts when it comes up", () async {
      now = now.add(const Duration(seconds: 12));
      await notifier.rate(Rating.good);
      now = now.add(const Duration(seconds: 5));
      await notifier.rate(Rating.again);
      final stats = await db
          .customSelect('SELECT seconds FROM daily_stats')
          .getSingle();
      expect(stats.data['seconds'], 17);
    });

    test('its time is capped, so an idle phone is not a long card', () async {
      now = now.add(const Duration(hours: 1));
      await notifier.rate(Rating.again);
      final stats = await db
          .customSelect('SELECT seconds FROM daily_stats')
          .getSingle();
      expect(stats.data['seconds'], 300);
    });

    test('Undo restores word_state exactly and deletes the log row', () async {
      final before = await state(strasse);
      await notifier.rate(Rating.easy);
      expect(await state(strasse), isNot(before));

      await notifier.undo();
      expect(await state(strasse), before);
      expect(await log(), isEmpty);
      final plan = await db
          .customSelect(
            "SELECT completed_at FROM plan_items WHERE word_uid = '$strasse'",
          )
          .getSingle();
      expect(plan.data['completed_at'], isNull);
      expect(session().current?.uid, strasse);
      expect(session().results, isEmpty);
    });

    test('and a first rating undone leaves no word_state at all', () async {
      notifier.advance(CardOutcome.good);
      await notifier.rate(Rating.good);
      await notifier.undo();
      expect(await state(haus), isNull);
    });
  });

  group('the bar', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      List<Override> extra = const <Override>[],
    }) async {
      await tester.runAsync(open);
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[...overrides(), ...extra],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const StudyScreen(args: args),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(StudyScreen)),
      );
    }

    Future<void> reveal(WidgetTester tester) async {
      await tester.tap(find.text(l10n.studyShowMeaning));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('turned over: the prompt, and each rating with its interval', (
      tester,
    ) async {
      await pump(tester);
      await reveal(tester);

      expect(find.text(l10n.studyRatePrompt), findsOneWidget);
      final preview = (await tester.runAsync(
        () => service().preview(strasse),
      ))!;
      for (final rating in Rating.values) {
        expect(
          find.text(l10n.studyIntervalDays(preview[rating]!)),
          findsWidgets,
          reason: rating.name,
        );
      }
      expect(
        tester.widget<DpRatingBar>(find.byType(DpRatingBar)).enabled,
        isTrue,
      );
    });

    testWidgets('the previews are computed once per card, not per frame', (
      tester,
    ) async {
      var calls = 0;
      await pump(
        tester,
        extra: <Override>[
          studyIntervalsProvider(strasse).overrideWith((ref) async {
            calls++;
            return <Rating, int>{
              Rating.again: 1,
              Rating.hard: 3,
              Rating.good: 8,
              Rating.easy: 21,
            };
          }),
        ],
      );
      await reveal(tester);
      for (var i = 0; i < 5; i++) {
        tester.element(find.byType(StudyScreen)).markNeedsBuild();
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(calls, 1);

      // Each button carries its own interval.
      final semantics = tester.ensureSemantics();
      for (final (label, days) in <(String, int)>[
        (l10n.ratingAgain, 1),
        (l10n.ratingHard, 3),
        (l10n.ratingGood, 8),
        (l10n.ratingEasy, 21),
      ]) {
        expect(
          find.bySemanticsLabel('$label, ${l10n.studyIntervalDays(days)}'),
          findsOneWidget,
        );
      }
      semantics.dispose();
    });

    testWidgets('held until the previews exist', (tester) async {
      await pump(
        tester,
        extra: <Override>[
          studyIntervalsProvider(strasse)
              .overrideWith((ref) => Completer<Map<Rating, int>>().future),
        ],
      );
      await tester.tap(find.text(l10n.studyShowMeaning));
      await tester.pump();
      expect(
        tester.widget<DpRatingBar>(find.byType(DpRatingBar)).enabled,
        isFalse,
      );
    });

    testWidgets('FR-T2-02 Good moves on, and its Undo brings the card back', (
      tester,
    ) async {
      final container = await pump(tester);
      await reveal(tester);

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.ratingGood));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(
        find.text(l10n.studyRated('die Straße', l10n.ratingGood)),
        findsOneWidget,
      );
      expect(
        container.read(studySessionProvider(args)).value?.current?.uid,
        haus,
      );
      // The next card comes face down.
      expect(find.byType(DpRatingBar), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.undo));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        container.read(studySessionProvider(args)).value?.current?.uid,
        strasse,
      );
      expect(await tester.runAsync(log), isEmpty);
    });
  });
}

class _SilentTts implements TtsEngine {
  @override
  Future<bool> speak(String text, {double rate = 1}) async => true;

  @override
  Future<void> stop() async {}
}
