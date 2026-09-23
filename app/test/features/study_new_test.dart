import 'dart:io';

import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_card.dart';
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

/// T2 · StudyNew — #103.
void main() {
  const today = '2026-09-21';
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;
  const strasse = ContentFixture.strasse;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Straße to revise, Haus and Tür new.
  Future<void> open() async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_new');
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
    settings = SettingsRepository(db);
    await settings.load();
    await settings.write(SettingKeys.autoplayHeadword, false);
  }

  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
    systemTtsProvider.overrideWithValue(_SilentTts()),
    clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
  ];

  const args = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
      SessionBlock(SessionBlockKind.newWords, <String>[haus, tuer]),
    ],
  );

  Future<Map<String, Object?>> row(String uid) async =>
      (await db
              .customSelect(
                'SELECT completed_at, skipped FROM plan_items '
                "WHERE word_uid = '$uid'",
              )
              .getSingle())
          .data;

  Future<List<Map<String, Object?>>> log() async => <Map<String, Object?>>[
    for (final r
        in await db
            .customSelect('SELECT word_uid, rating, source FROM review_log')
            .get())
      r.data,
  ];

  group('the writes', () {
    late ProviderContainer container;
    late StudySession notifier;

    setUp(() async {
      await open();
      container = ProviderContainer(overrides: overrides());
      await container.read(studySessionProvider(args).future);
      notifier = container.read(studySessionProvider(args).notifier)
        // Past Straße, to Haus.
        ..advance(CardOutcome.good);
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
    });

    StudySessionState session() =>
        container.read(studySessionProvider(args)).value!;

    test(
      'FR-T2-04 BR-STATUS-04 I know it rates Easy and completes the row',
      () async {
        await notifier.knewIt();

        expect(await log(), <Map<String, Object?>>[
          <String, Object?>{'word_uid': haus, 'rating': 4, 'source': 'known'},
        ]);
        expect((await row(haus))['completed_at'], isNotNull);
        expect(session().current?.uid, tuer);
        expect(session().results[1], CardOutcome.knewIt);
      },
    );

    test('FR-T2-03 BR-PLAN-06 Skip leaves the row open and skipped', () async {
      await notifier.skip();

      expect(await row(haus), <String, Object?>{
        'completed_at': null,
        'skipped': 1,
      });
      expect(await log(), isEmpty);
      expect(session().current?.uid, tuer);
      expect(session().results[1], CardOutcome.skipped);
    });

    test('FR-T2-03 and it waits in the backlog from the next day', () async {
      await notifier.skip();
      final repo = PlanRepository(db);

      expect(await repo.watchBacklog(today).first, isEmpty);
      expect(
        (await repo.watchBacklog('2026-09-22').first).map((r) => r.wordUid),
        contains(haus),
      );
    });

    test('a session built again does not ask the skipped word', () async {
      await notifier.skip();
      container.invalidate(studySessionProvider(args));
      final again = await container.read(studySessionProvider(args).future);
      expect(again.items.map((i) => i.uid), isNot(contains(haus)));
    });

    test("the skip's Undo takes it back and asks the word again", () async {
      await notifier.skip();
      await notifier.undo();

      expect(await row(haus), <String, Object?>{
        'completed_at': null,
        'skipped': 0,
      });
      expect(session().current?.uid, haus);
      expect(session().results.containsKey(1), isFalse);
    });

    test("I know it's Undo restores the word as it was", () async {
      await notifier.knewIt();
      await notifier.undo();

      expect(await log(), isEmpty);
      expect(
        await db
            .customSelect("SELECT 1 FROM word_state WHERE word_uid = '$haus'")
            .get(),
        isEmpty,
      );
      expect((await row(haus))['completed_at'], isNull);
      expect(session().current?.uid, haus);
    });

    test('a double tap rates once', () async {
      await Future.wait(<Future<void>>[notifier.knewIt(), notifier.knewIt()]);
      expect(await log(), hasLength(1));
      expect(session().current?.uid, tuer);
    });
  });

  group('the screen', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      await tester.runAsync(open);
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
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

    Future<void> toNew(WidgetTester tester, ProviderContainer container) async {
      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pumpAndSettle();
    }

    testWidgets('a revision has no New chip and no new-word buttons', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10n.studyNewChip), findsNothing);
      expect(find.byType(StudyNewActions), findsNothing);
      expect(find.text(l10n.studyHint), findsOneWidget);
    });

    testWidgets('a new word has both, above Show meaning', (tester) async {
      final container = await pump(tester);
      await toNew(tester, container);

      final chip = find.widgetWithText(DpChip, l10n.studyNewChip);
      expect(chip, findsOneWidget);
      expect(tester.widget<DpChip>(chip).selected, isTrue);
      expect(find.text(l10n.studyKnowIt), findsOneWidget);
      expect(find.text(l10n.studySkip), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(l10n.studySkip)).dy,
        lessThan(tester.getTopLeft(find.text(l10n.studyShowMeaning)).dy),
      );
      // They take the hint's place.
      expect(find.text(l10n.studyHint), findsNothing);
    });

    testWidgets('turned over, the buttons go', (tester) async {
      final container = await pump(tester);
      await toNew(tester, container);
      await tester.tap(find.text(l10n.studyShowMeaning));
      await tester.pumpAndSettle();
      expect(find.byType(StudyNewActions), findsNothing);
    });

    testWidgets('FR-T2-03 Skip says where the word went, and Undo brings it '
        'back', (tester) async {
      final container = await pump(tester);
      await toNew(tester, container);

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.studySkip));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(l10n.studySkipped('das Haus')), findsOneWidget);
      // Clear of the thumb zone, as the artboard floats it.
      expect(
        tester.getBottomLeft(find.text(l10n.studySkipped('das Haus'))).dy,
        lessThan(tester.getTopLeft(find.text(l10n.studyShowMeaning)).dy),
      );
      expect(
        container.read(studySessionProvider(args)).value?.current?.uid,
        tuer,
      );

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.undo));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        container.read(studySessionProvider(args)).value?.current?.uid,
        haus,
      );
      expect((await tester.runAsync(() => row(haus)))!['skipped'], 0);
    });

    testWidgets('closing the session takes its undo bar with it', (
      tester,
    ) async {
      await tester.runAsync(open);
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StudyScreen(args: args),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudyScreen)),
      );
      await toNew(tester, container);
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.studySkip));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(l10n.studySkipped('das Haus')), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(l10n.studyClose));
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsNothing);
      expect(find.text(l10n.undo), findsNothing);
    });

    testWidgets('FR-T2-04 I know it moves on, with its own Undo', (
      tester,
    ) async {
      final container = await pump(tester);
      await toNew(tester, container);

      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.studyKnowIt));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(l10n.studyKnown('das Haus')), findsOneWidget);
      expect(
        container.read(studySessionProvider(args)).value?.current?.uid,
        tuer,
      );
    });

    testWidgets("the banner takes its block's colour: Sun for New", (
      tester,
    ) async {
      final container = await pump(tester);
      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final banner = find.text(l10n.studyBannerNewCategory('Wohnen'));
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: banner, matching: find.byType(DecoratedBox)).first,
      );
      final context = tester.element(banner);
      expect(
        (box.decoration as BoxDecoration).color,
        context.tokens.color.accent,
      );
      // Full width, as the artboard's strip: 16 px in from each side.
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: banner, matching: find.byType(DecoratedBox))
                  .first,
            )
            .width,
        tester.getSize(find.byType(StudyScreen)).width - 32,
      );
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
    });

    testWidgets('and Lagoon for Revise', (tester) async {
      await tester.runAsync(open);
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const StudyScreen(args: args),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final banner = find.text(l10n.studyBannerRevise);
      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: banner, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        tester.element(banner).tokens.color.primary,
      );
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
    });
  });
}

class _SilentTts implements TtsEngine {
  @override
  Future<bool> speak(String text, {double rate = 1}) async => true;

  @override
  Future<void> stop() async {}
}
