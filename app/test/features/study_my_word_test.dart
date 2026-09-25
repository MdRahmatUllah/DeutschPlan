import 'dart:io';

import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';
import '../services/fake_tts.dart';

/// T2 serving a word of the learner's own (#363, FR-R2-03): `custom:1` in
/// today's Revise block, added to revision and not yet reviewed.
void main() {
  const today = '2026-09-21';
  const uid = 'custom:1';

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const args = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[uid]),
      // A second card, so rating the first does not end the session.
      SessionBlock(SessionBlockKind.newWords, <String>[ContentFixture.haus]),
    ],
  );

  /// [router]: in a GoRouter whose R2 edit page says which word it opened.
  Future<void> pump(WidgetTester tester, {bool router = false}) async {
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = Directory.systemTemp.createTempSync('dp_my_word');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      await db.customStatement('''
INSERT INTO custom_words (id, created_at, article, german, meaning, example)
VALUES (1, '2026-09-20T10:00:00Z', 'das', 'Pfand', 'deposit',
  'Ich bekomme das Pfand zurück.')
''');
      await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due)
VALUES ('$uid', 'learning', '$today', '$today')
''');
      await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code)
VALUES ('$today', '$uid', 'revise', 'A1.1'),
  ('$today', '${ContentFixture.haus}', 'new', 'A1.1')
''');
      settings = SettingsRepository(db);
      await settings.load();
      await settings.write(SettingKeys.autoplayHeadword, false);
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(FakeTts()),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
        ],
        child: router
            ? MaterialApp.router(
                theme: AppTheme.light(),
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: supportedLocales,
                routerConfig: GoRouter(
                  routes: <RouteBase>[
                    GoRoute(
                      path: '/',
                      builder: (_, _) => const StudyScreen(args: args),
                    ),
                    GoRoute(
                      path: const EditCustomWordRoute(id: 1).location,
                      builder: (_, _) => const Text('R2 · 1'),
                    ),
                  ],
                ),
              )
            : MaterialApp(
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
  }

  testWidgets('the card shows the headword, says it is my word, and turns '
      'over to the meaning and my example', (tester) async {
    await pump(tester);
    expect(find.text('das Pfand', findRichText: true), findsWidgets);
    expect(find.widgetWithText(DpChip, l10n.searchMyWord), findsOneWidget);

    await tester.tap(find.text(l10n.studyShowMeaning));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('deposit'), findsOneWidget);
    expect(
      find.text('Ich bekomme das Pfand zurück.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('rating it schedules it and completes its plan row', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.studyShowMeaning));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.ratingGood));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final state = await tester.runAsync(
      () => (db.select(
        db.wordState,
      )..where((t) => t.wordUid.equals(uid))).getSingle(),
    );
    expect(state!.reps, 1);
    expect(state.due!.compareTo(today), greaterThan(0));
    final row = await tester.runAsync(
      () => (db.select(
        db.planItems,
      )..where((t) => t.wordUid.equals(uid))).getSingle(),
    );
    expect(row!.completedAt, isNotNull);
  });

  testWidgets('its Word details open it in R2, where it was written', (
    tester,
  ) async {
    await pump(tester, router: true);
    await tester.tap(find.bySemanticsLabel(l10n.studyMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.studyMenuWordDetails));
    await tester.pumpAndSettle();
    expect(find.text('R2 · 1'), findsOneWidget);
  });
}
