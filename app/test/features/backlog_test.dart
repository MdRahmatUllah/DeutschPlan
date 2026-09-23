import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/features/backlog/backlog_screen.dart';
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
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';

/// T4 · Backlog — #108.
void main() {
  const today = '2026-09-21'; // a Monday
  const haus = ContentFixture.haus;
  const tuer = ContentFixture.tuer;
  const strasse = ContentFixture.strasse;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;
  late List<String> spoken;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Tuesday's Haus, and Tür skipped; Wednesday's Straße. Then rows that are
  /// not backlog: an old one done, an old revision, and today's.
  Future<void> open() async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_backlog');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code, skipped,
  completed_at) VALUES
  ('2026-09-15', '$haus', 'new', 'A1.1', 0, NULL),
  ('2026-09-15', '$tuer', 'new', 'A1.1', 1, NULL),
  ('2026-09-16', '$strasse', 'new', 'A1.2', 0, NULL),
  ('2026-09-10', '$haus', 'new', 'A1.1', 0, '2026-09-10T08:00:00Z'),
  ('2026-09-16', '$tuer', 'revise', 'A1.1', 0, NULL),
  ('$today', '$strasse', 'new', 'A1.2', 0, NULL)
''');
    settings = SettingsRepository(db);
    await settings.load();
  }

  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
    systemTtsProvider.overrideWithValue(_Tts(spoken)),
    clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
  ];

  GoRouter router() => GoRouter(
    initialLocation: '/today/backlog',
    routes: <RouteBase>[
      GoRoute(
        path: '/today',
        builder: (_, _) => const Text('T1 today'),
        routes: <RouteBase>[
          GoRoute(path: 'backlog', builder: (_, _) => const BacklogScreen()),
        ],
      ),
      GoRoute(
        path: '/study',
        builder: (_, state) {
          final args = state.extra! as SessionArgs;
          final block = args.blocks.single;
          return Text(
            'T2 ${args.planDate} ${block.kind.name} '
            '${block.uids.join(',')}',
          );
        },
      ),
      GoRoute(
        path: '/word/:uid',
        builder: (_, state) => Text('W1 ${state.pathParameters['uid']}'),
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    spoken = <String>[];
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
        child: AdaptiveChromeScope(
          chrome: chrome,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: router(),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  /// Lets a write land and the backlog stream answer.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Future<Map<String, Object?>> row(String date, String uid) async =>
      (await db
              .customSelect(
                'SELECT completed_at, skipped FROM plan_items '
                "WHERE plan_date = '$date' AND word_uid = '$uid' AND kind = 'new'",
              )
              .getSingle())
          .data;

  Finder word(String german) => find.text(german, findRichText: true);

  group('FR-T4-01 the rows', () {
    testWidgets('uncompleted new rows from before today, newest day first', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(l10n.backlogCount(3)), findsOneWidget);
      final wed = find.text(l10n.backlogDay('Wed 16 Sep', 1).toUpperCase());
      final tue = find.text(l10n.backlogDay('Tue 15 Sep', 2).toUpperCase());
      expect(wed, findsOneWidget);
      expect(tue, findsOneWidget);
      expect(tester.getTopLeft(wed).dy, lessThan(tester.getTopLeft(tue).dy));

      // Straße under Wednesday; Haus and the skipped Tür under Tuesday.
      final y = tester.getTopLeft(tue).dy;
      expect(tester.getTopLeft(word('die Straße')).dy, lessThan(y));
      expect(tester.getTopLeft(word('das Haus')).dy, greaterThan(y));
      expect(tester.getTopLeft(word('die Tür')).dy, greaterThan(y));
      // Done, a revision and today's are not backlog.
      expect(word('die Straße'), findsOneWidget);
      expect(word('das Haus'), findsOneWidget);
    });

    testWidgets('the header says where they come from, without pressure', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(l10n.backlogIntroTwo('Tue', 'Wed')), findsOneWidget);
    });

    testWidgets('each row: its meaning and its status', (tester) async {
      await pump(tester);
      expect(find.text('house'), findsOneWidget);
      expect(find.text(l10n.wordStatusToDo), findsNWidgets(3));
    });

    testWidgets('its speaker plays the word with its article', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel(l10n.summaryPlay('das Haus')));
      await tester.pump();
      expect(spoken, <String>['das Haus']);
    });

    testWidgets('a tap opens the word', (tester) async {
      await pump(tester);
      await tester.tap(word('das Haus'));
      await tester.pumpAndSettle();
      expect(find.text('W1 $haus'), findsOneWidget);
    });
  });

  group('FR-T4-02 studying them', () {
    testWidgets('Study all: every word, as one Backlog block', (tester) async {
      await pump(tester);
      await tester.tap(find.text(l10n.backlogStudyAll(3)));
      await tester.pumpAndSettle();
      expect(
        find.text('T2 $today backlog $strasse,$haus,$tuer'),
        findsOneWidget,
      );
    });

    testWidgets("Study this day: that day's words only", (tester) async {
      await pump(tester);
      await tester.tap(find.text(l10n.backlogStudyDay).last);
      await tester.pumpAndSettle();
      expect(find.text('T2 $today backlog $haus,$tuer'), findsOneWidget);
    });

    group('the session', () {
      late ProviderContainer container;
      const args = SessionArgs(
        planDate: today,
        blocks: <SessionBlock>[
          SessionBlock(SessionBlockKind.backlog, <String>[haus, strasse]),
        ],
      );

      setUp(() async {
        spoken = <String>[];
        await open();
        container = ProviderContainer(overrides: overrides());
      });
      tearDown(() async {
        container.dispose();
        await settings.dispose();
        await db.close();
      });

      test('holds exactly those words, each with its own day', () async {
        final session = await container.read(studySessionProvider(args).future);
        expect(session.items, const <StudyItem>[
          StudyItem(SessionBlockKind.backlog, haus),
          StudyItem(SessionBlockKind.backlog, strasse),
        ]);
        expect(session.items.map((i) => i.planDate), <String>[
          '2026-09-15',
          '2026-09-16',
        ]);
      });

      test("a rating completes the word's own day, not today's", () async {
        await container.read(studySessionProvider(args).future);
        await container
            .read(studySessionProvider(args).notifier)
            .rate(Rating.good);
        expect((await row('2026-09-15', haus))['completed_at'], isNotNull);
        final stats = await db
            .customSelect('SELECT new_done FROM daily_stats')
            .getSingle();
        expect(stats.data['new_done'], 1);
      });

      test('and so does I know it', () async {
        await container.read(studySessionProvider(args).future);
        final notifier = container.read(studySessionProvider(args).notifier)
          ..advance(CardOutcome.good);
        await notifier.knewIt();
        expect((await row('2026-09-16', strasse))['completed_at'], isNotNull);
        expect((await row(today, strasse))['completed_at'], isNull);
      });

      test('a word no longer in the backlog is not asked', () async {
        await db.customStatement(
          "UPDATE plan_items SET completed_at = '2026-09-20T08:00:00Z' "
          "WHERE plan_date = '2026-09-15' AND word_uid = '$haus'",
        );
        final session = await container.read(studySessionProvider(args).future);
        expect(session.items.map((i) => i.uid), <String>[strasse]);
      });
    });
  });

  group('FR-T4-03 the pause switch', () {
    testWidgets('writes pause_new_when_backlog', (tester) async {
      await pump(tester);
      expect(settings.read(SettingKeys.pauseNewWhenBacklog), isFalse);
      await tester.tap(find.byType(AdaptiveSwitch));
      await settle(tester);
      expect(settings.read(SettingKeys.pauseNewWhenBacklog), isTrue);
      expect(
        tester.widget<AdaptiveSwitch>(find.byType(AdaptiveSwitch)).value,
        isTrue,
      );
    });
  });

  group('FR-T4-04 row actions', () {
    Future<void> longPress(WidgetTester tester, String label) async {
      await tester.longPress(word('das Haus'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DpButton, label));
      await settle(tester);
    }

    testWidgets('Mark known rates it Easy and it leaves the list', (
      tester,
    ) async {
      await pump(tester);
      await longPress(tester, l10n.backlogMarkKnown);

      expect(word('das Haus'), findsNothing);
      final log = await tester.runAsync(
        () => db
            .customSelect('SELECT word_uid, rating, source FROM review_log')
            .get(),
      );
      expect(log!.single.data, <String, Object?>{
        'word_uid': haus,
        'rating': 4,
        'source': 'known',
      });
      expect(
        (await tester.runAsync(() => row('2026-09-15', haus)))!['completed_at'],
        isNotNull,
      );
      expect(find.text(l10n.studyKnown('das Haus')), findsOneWidget);

      await tester.tap(find.text(l10n.undo));
      await settle(tester);
      expect(word('das Haus'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Suspend keeps it here, marked suspended', (tester) async {
      await pump(tester);
      await longPress(tester, l10n.backlogSuspend);
      expect(word('das Haus'), findsOneWidget);
      expect(find.text(l10n.wordStatusSuspended), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('Remove from course suspends it and completes its row', (
      tester,
    ) async {
      await pump(tester);
      await longPress(tester, l10n.backlogRemove);
      expect(word('das Haus'), findsNothing);
      final status = await tester.runAsync(
        () => db
            .customSelect(
              "SELECT status FROM word_state WHERE word_uid = '$haus'",
            )
            .getSingle(),
      );
      expect(status!.data['status'], 'suspended');

      await tester.tap(find.text(l10n.undo));
      await settle(tester);
      expect(word('das Haus'), findsOneWidget);
      expect(find.text(l10n.wordStatusSuspended), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('on iOS a trailing swipe uncovers them', (tester) async {
      await pump(tester, chrome: AdaptiveChrome.cupertino);
      await tester.drag(word('das Haus'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      // Every row has its own strip; Haus's is the one uncovered.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: word('das Haus'),
            matching: find.byType(BacklogRow),
          ),
          matching: find.text(l10n.backlogSuspend),
        ),
      );
      await settle(tester);
      expect(find.text(l10n.wordStatusSuspended), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  for (final chrome in AdaptiveChrome.values) {
    testWidgets('FR-T4-05 no overdue red anywhere (${chrome.name})', (
      tester,
    ) async {
      await pump(tester, chrome: chrome);
      final red = <Color>{DpPalette.light.again, DpPalette.light.wrongText};
      final seen = <Color>{
        for (final box in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        ))
          ?(box.decoration as BoxDecoration?)?.color,
        // The iOS action strip draws its colours as Container fills.
        for (final box in tester.widgetList<Container>(find.byType(Container)))
          ?box.color,
        for (final box in tester.widgetList<ColoredBox>(
          find.byType(ColoredBox),
        ))
          box.color,
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          ?text.style?.color,
      };
      expect(seen.intersection(red), isEmpty);
    });
  }

  testWidgets('a backlog session: its label, the New chip, I know it and no '
      'Skip', (tester) async {
    spoken = <String>[];
    await tester.runAsync(open);
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.runAsync(
      () => settings.write(SettingKeys.autoplayHeadword, false),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const StudyScreen(
            args: SessionArgs(
              planDate: today,
              blocks: <SessionBlock>[
                SessionBlock(SessionBlockKind.backlog, <String>[haus, tuer]),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.pump(StudyScreen.bannerTime);
    await tester.pumpAndSettle();

    expect(find.text(l10n.studyBlockBacklog(1, 2)), findsOneWidget);
    expect(find.text(l10n.studyNewChip), findsOneWidget);
    expect(find.text(l10n.studyKnowIt), findsOneWidget);
    // Already in the backlog: nowhere to skip it to.
    expect(find.text(l10n.studySkip), findsNothing);
  });
}

class _Tts implements TtsEngine {
  _Tts(this.spoken);

  final List<String> spoken;

  @override
  Future<bool> speak(String text, {double rate = 1}) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}
