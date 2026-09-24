@TestOn('vm')
library;

import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The core providers — #71.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
  ];

  ProviderContainer container({List<Override> extra = const <Override>[]}) {
    final result = ProviderContainer(
      overrides: <Override>[...overrides(), ...extra],
    );
    addTearDown(result.dispose);
    return result;
  }

  group('the ones bootstrap supplies', () {
    test('refuse to be read without an override', () {
      final bare = ProviderContainer();
      addTearDown(bare.dispose);

      // Not a null and not a second database: two `AppDatabase`s over one
      // file is how a learner loses a rating to a race, and an unloaded
      // `SettingsRepository` answers every read with a default.
      //
      // Asserted on the message rather than on the type: Riverpod 3 wraps
      // whatever a provider throws in a `ProviderException`, and what has to
      // survive that is the sentence telling the next person what to do.
      expect(
        () => bare.read(appDatabaseProvider),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'message',
            contains('must be overridden'),
          ),
        ),
      );
      expect(
        () => bare.read(settingsProvider),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'message',
            contains('answers every read with a default'),
          ),
        ),
      );
    });

    test('hand back exactly what bootstrap opened', () {
      final ref = container();
      expect(identical(ref.read(appDatabaseProvider), db), isTrue);
      expect(identical(ref.read(settingsProvider), settings), isTrue);
    });
  });

  group('the clock', () {
    test('is the real one by default', () {
      final ref = container();
      final now = ref.read(clockProvider)();
      expect(
        now.difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 5)),
      );
    });

    test('is overridable', () {
      final fixed = DateTime(2026, 3, 4, 9);
      final ref = container(
        extra: <Override>[clockProvider.overrideWithValue(() => fixed)],
      );

      expect(ref.read(clockProvider)(), fixed);
    });

    test('is what `today` is built from', () {
      // A second clock would mean two answers to "is this due", and only one
      // of them would move when a test moved the date.
      final ref = container(
        extra: <Override>[
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 4)),
        ],
      );

      expect(ref.read(todayProvider), '2026-03-04');
    });

    test('`today` pads the way plan_date is stored', () {
      final ref = container(
        extra: <Override>[
          clockProvider.overrideWithValue(() => DateTime(2026, 1, 5)),
        ],
      );

      expect(ref.read(todayProvider), '2026-01-05');
    });

    test('`today` is a local day, not a UTC one', () {
      // `plan_items.plan_date` and `word_state.due` are local days, because
      // a study day is a local day. Late on the 4th is still the 4th.
      final ref = container(
        extra: <Override>[
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 4, 23, 30)),
        ],
      );

      expect(ref.read(todayProvider), '2026-03-04');
    });
  });

  group('the theme notifier', () {
    test('follows the setting', () async {
      final ref = container();
      expect(ref.read(themeProvider), DpMode.light);

      await ref.read(themeProvider.notifier).choose(ThemeModeSetting.dark);
      expect(ref.read(themeProvider), DpMode.dark);
    });

    test('choosing writes the setting through, not around it', () async {
      // `state-management.md`: actions are notifier methods; widgets never
      // write to repositories. The proof is that the table changed too.
      final ref = container();
      await ref.read(themeProvider.notifier).choose(ThemeModeSetting.glass);

      expect(settings.read(SettingKeys.themeMode), ThemeModeSetting.glass);
      expect(ref.read(themeProvider), DpMode.glass);
    });

    test('follows the platform only when the learner asked it to', () async {
      final ref = container();
      final theme = ref.read(themeProvider.notifier);

      // The default is `system`.
      theme.platformBrightnessChanged(Brightness.dark);
      expect(ref.read(themeProvider), DpMode.dark);

      await theme.choose(ThemeModeSetting.light);
      theme.platformBrightnessChanged(Brightness.dark);
      expect(
        ref.read(themeProvider),
        DpMode.light,
        reason: 'the platform overrode an explicit choice',
      );
    });

    test('a system change does not rebuild an explicit choice', () async {
      // The outcome would be the same either way — `build` re-reads the
      // setting and resolves to the same mode — so what the guard buys is
      // *not rebuilding*. Every frame-consumer of the theme would otherwise
      // be invalidated each time the system flipped, for no change at all.
      final ref = container();
      await ref.read(themeProvider.notifier).choose(ThemeModeSetting.light);

      var rebuilds = 0;
      ref.listen(themeProvider, (_, _) => rebuilds++);

      ref
          .read(themeProvider.notifier)
          .platformBrightnessChanged(Brightness.dark);
      ref
          .read(themeProvider.notifier)
          .platformBrightnessChanged(Brightness.light);

      // `invalidateSelf` rebuilds on the next microtask, so a synchronous
      // assertion here would read zero whatever happened.
      await _settle();

      expect(rebuilds, 0);
      expect(ref.read(themeProvider), DpMode.light);
    });

    test('and one that is following does rebuild', () async {
      final ref = container();
      expect(ref.read(themeProvider), DpMode.light);

      var rebuilds = 0;
      ref.listen(themeProvider, (_, _) => rebuilds++);

      ref
          .read(themeProvider.notifier)
          .platformBrightnessChanged(Brightness.dark);
      await _settle();

      expect(rebuilds, 1);
      expect(ref.read(themeProvider), DpMode.dark);
    });

    test('glass is chosen, never inferred', () async {
      final ref = container();
      await ref.read(themeProvider.notifier).choose(ThemeModeSetting.glass);

      ref
          .read(themeProvider.notifier)
          .platformBrightnessChanged(Brightness.dark);
      expect(ref.read(themeProvider), DpMode.glass);
    });
  });

  group('#342 the plan engine', () {
    test('a setting it holds rebuilds it, from any writer', () async {
      final c = container();
      c.listen(planEngineProvider, (_, _) {}); // as Today's tab keeps it
      final writes = <Future<void> Function()>[
        () => settings.write(SettingKeys.pauseNewWhenBacklog, true),
        () => settings.write(SettingKeys.reviseCount, 12),
        () => settings.write(SettingKeys.autoAdvance, false),
        () => settings.write(SettingKeys.backlogCatchupDays, 10),
      ];
      for (final write in writes) {
        final before = c.read(planEngineProvider);
        await write();
        await pumpEventQueue();
        expect(c.read(planEngineProvider), isNot(same(before)));
      }
    });

    test('one it does not hold leaves it be', () async {
      final c = container();
      c.listen(planEngineProvider, (_, _) {});
      final before = c.read(planEngineProvider);
      await settings.write(SettingKeys.learnerName, 'Rahim');
      await pumpEventQueue();
      expect(c.read(planEngineProvider), same(before));
    });
  });

  group('the repositories', () {
    test('are built over the database bootstrap opened', () {
      final ref = container();

      // Each one exists and does not throw. The point is the wiring: a
      // repository built over a second database would read an empty file.
      expect(ref.read(wordRepositoryProvider), isNotNull);
      expect(ref.read(planRepositoryProvider), isNotNull);
      expect(ref.read(examRepositoryProvider), isNotNull);
      expect(ref.read(grammarRepositoryProvider), isNotNull);
      expect(ref.read(backupRepositoryProvider), isNotNull);
      expect(ref.read(contentDaoProvider), isNotNull);
      expect(ref.read(searchRepositoryProvider), isNotNull);
    });

    test('a write through one is visible through another', () async {
      // The strongest version of "same database": two repositories, one row.
      final ref = container();
      await ref
          .read(examRepositoryProvider)
          .begin(
            sublevelCode: 'A1.1',
            seed: 1,
            startedAt: '2026-03-04T09:00:00Z',
            questions: const <ExamQuestion>[
              ExamQuestion(ord: 1, section: 'vocabulary', prompt: 'das Haus'),
            ],
          );

      final row = await ref
          .read(appDatabaseProvider)
          .customSelect('SELECT COUNT(*) AS n FROM exam_attempts')
          .getSingle();
      expect(row.read<int>('n'), 1);
    });
  });

  group('AsyncValue.error renders the shared ErrorPanel', () {
    testWidgets('and offers Retry', (tester) async {
      // `state-management.md`: "`AsyncValue.error` renders the shared
      // `ErrorPanel` with Retry." Every screen uses the one panel so a
      // failure looks the same everywhere and Retry always exists.
      var retried = 0;
      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) =>
                    const AsyncValue<int>.error('nope', StackTrace.empty).when(
                      data: (value) => Text('$value'),
                      loading: () => const CircularProgressIndicator(),
                      error: (error, stack) => DpErrorPanel(
                        message: 'Something went wrong.',
                        retryLabel: l10n.retry,
                        onRetry: () => retried++,
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DpErrorPanel), findsOneWidget);
      expect(find.text(l10n.retry), findsOneWidget);

      await tester.tap(find.text(l10n.retry));
      expect(retried, 1);
    });

    test('the panel never shows a raw exception', () {
      // A learner cannot act on a stack trace. `detail` is documented as
      // "never a raw exception string"; this is the reminder in test form.
      const panel = DpErrorPanel(message: 'x', retryLabel: 'Retry');
      expect(panel.detail, isNull);
    });
  });
}

/// Lets a `invalidateSelf` rebuild reach its listeners.
///
/// Riverpod schedules the rebuild rather than running it inline, so the
/// zero-rebuild assertion above would pass without this whatever happened.
Future<void> _settle() => Future<void>.delayed(Duration.zero);
