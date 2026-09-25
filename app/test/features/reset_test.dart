import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/me/reset_flow.dart';
import 'package:deutschplan/features/me/settings_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';

/// The recordings, deleted without a disk: `reset_repository_test.dart`
/// deletes real ones, and file I/O never finishes in a widget test's clock.
class _Recordings extends Fake implements ModelRepository {
  final List<Iterable<int>?> deleted = <Iterable<int>?>[];

  /// A file the system holds: the delete throws.
  bool held = false;

  @override
  Future<void> deleteRecordings([Iterable<int>? attempts]) async {
    if (held) throw const FileSystemException('held');
    deleted.add(attempts);
  }
}

/// M7 · Reset — #149 (`reset.md`, the ResetDialog artboard).
void main() {
  late AppLocalizations l10n;
  late Directory directory;
  late AppDatabase db;
  late SettingsRepository settings;
  late String went;
  late _Recordings recordings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('deutschplan_reset_ui');
    final content = ContentFixture.write('${directory.path}/content.db').file;
    db = AppDatabase.memory();
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
    );
    settings = SettingsRepository(db);
    await settings.load();
    went = '';
    recordings = _Recordings();
    // A1.1, the current step, with a word learning.
    await db.customStatement(
      'INSERT INTO enrollments '
      '(sublevel_code, started_on, daily_new, study_days_mask) '
      "VALUES ('A1.1', '2026-09-01', 7, 127)",
    );
    await db.customStatement(
      'INSERT INTO word_state (word_uid, status, reps, introduced_on) '
      "VALUES ('${ContentFixture.haus}', 'learning', 2, '2026-09-01')",
    );
  });

  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 9000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    Widget away(GoRouterState state) {
      went = state.uri.toString();
      return const SizedBox();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          todayProvider.overrideWithValue('2026-09-25'),
          learnedStabilitiesProvider.overrideWith((ref) async => <double>[]),
          translationModelProvider.overrideWith((ref) async => null),
          modelRepositoryProvider.overrideWithValue(recordings),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/me/settings',
            routes: <RouteBase>[
              GoRoute(
                path: '/me',
                builder: (_, _) => const SizedBox(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const SettingsScreen(),
                  ),
                  GoRoute(path: 'export', builder: (_, state) => away(state)),
                ],
              ),
              GoRoute(
                path: '/onboarding/:page',
                builder: (_, state) => away(state),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Finder confirm() =>
      find.widgetWithText(TextButton, l10n.resetEverythingConfirm);

  testWidgets('FR-M7-03 Export first opens Export / import before anything '
      'is reset', (tester) async {
    await pump(tester);
    await tap(tester, l10n.settingsReset);
    await tap(tester, l10n.resetExportFirst);
    expect(went, '/me/export');
    expect(await count('word_state'), 1);
  });

  testWidgets('FR-M7-02 Reset stays off until the field says RESET exactly', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.settingsReset);
    await tap(tester, l10n.resetEverything);
    expect(find.text(l10n.resetEverythingMessage), findsOneWidget);

    bool on() => tester.widget<TextButton>(confirm()).onPressed != null;
    expect(on(), isFalse);
    for (final almost in <String>['RES', 'reset', 'RESET ', 'Reset']) {
      await tester.enterText(find.byType(TextField), almost);
      await tester.pump();
      expect(on(), isFalse, reason: almost);
    }
    await tester.enterText(find.byType(TextField), resetWord);
    await tester.pump();
    expect(on(), isTrue);

    await tap(tester, l10n.resetCancel);
    expect(await count('word_state'), 1, reason: 'Cancel resets nothing');
  });

  testWidgets('FR-M7-02 everything reset: onboarding next, the theme and the '
      'language kept', (tester) async {
    await settings.write(SettingKeys.themeMode, ThemeModeSetting.dark);
    await settings.write(SettingKeys.uiLanguage, UiLanguage.bangla);
    await pump(tester);
    // The widget test runs in English whatever the setting says.
    await tap(tester, l10n.settingsReset);
    await tap(tester, l10n.resetEverything);
    await tester.enterText(find.byType(TextField), resetWord);
    await tester.pump();
    await tester.tap(confirm());
    await tester.pumpAndSettle();

    expect(went, '/onboarding/1');
    expect(recordings.deleted, <Iterable<int>?>[null], reason: 'all of them');
    expect(await count('word_state'), 0);
    expect(await count('enrollments'), 0);
    expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.dark);
    expect(settings.read(SettingKeys.uiLanguage), UiLanguage.bangla);
  });

  testWidgets('FR-M7-01 one step: picked, confirmed, reset; M3 stays', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, l10n.settingsReset);
    await tap(tester, l10n.resetOneStep);
    expect(find.text(l10n.resetPickStep), findsOneWidget);
    expect(find.text(l10n.learnCurrent), findsOneWidget);
    await tap(tester, 'A1.1');

    expect(
      find.text('${l10n.resetStepMessage} ${l10n.resetStepCurrent('A1.1')}'),
      findsOneWidget,
    );
    await tap(tester, l10n.resetStepConfirm);

    expect(await count('word_state'), 0);
    expect(recordings.deleted, hasLength(1), reason: "its mocks' only");
    expect(recordings.deleted.single, isEmpty);
    expect(find.text(l10n.resetStepDone('A1.1')), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(went, isEmpty);
  });

  testWidgets('FR-M7-01 a recording that will not go does not undo the reset: '
      'done, not "nothing was changed"', (tester) async {
    await pump(tester);
    recordings.held = true;
    await tap(tester, l10n.settingsReset);
    await tap(tester, l10n.resetOneStep);
    await tap(tester, 'A1.1');
    await tap(tester, l10n.resetStepConfirm);

    expect(await count('word_state'), 0);
    expect(find.text(l10n.resetStepDone('A1.1')), findsOneWidget);
    expect(find.text(l10n.resetFailed), findsNothing);
  });
}
