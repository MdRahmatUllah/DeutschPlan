import 'dart:io';

import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/features/study/study_summary.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../db/content_fixture.dart';

/// T2 · the study session's shell — #100.
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

  /// A database with the course attached and today's plan: Straße to revise,
  /// Haus and Tür new.
  Future<void> open() async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_study');
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
  }

  final spoken = <String>[];
  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
    systemTtsProvider.overrideWithValue(_Tts(spoken)),
  ];

  const args = SessionArgs(
    planDate: today,
    // Out of order on purpose: the session puts them in BR-PLAN-02's.
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.grammar, <String>['g1']),
      SessionBlock(SessionBlockKind.newWords, <String>[haus, tuer]),
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
    ],
  );

  group('the queue', () {
    late ProviderContainer container;

    setUp(() async {
      await open();
      container = ProviderContainer(overrides: overrides());
    });

    tearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
    });

    test('is built in the fixed order Revise → New → Grammar', () async {
      final session = await container.read(studySessionProvider(args).future);
      expect(session.items, const <StudyItem>[
        StudyItem(SessionBlockKind.revise, strasse),
        StudyItem(SessionBlockKind.newWords, haus),
        StudyItem(SessionBlockKind.newWords, tuer),
        StudyItem(SessionBlockKind.grammar, 'g1'),
      ]);
    });

    test('resumes at the first open card after a crash', () async {
      // Straße was rated and Haus skipped before the app died: the session
      // built again from the same args starts at Tür.
      await db.customStatement(
        "UPDATE plan_items SET completed_at = '2026-09-21T08:00:00Z' "
        "WHERE word_uid = '$strasse'",
      );
      await db.customStatement(
        "UPDATE plan_items SET skipped = 1 WHERE word_uid = '$haus'",
      );
      final session = await container.read(studySessionProvider(args).future);
      expect(session.current, const StudyItem(SessionBlockKind.newWords, tuer));
      expect(session.left, 2);
    });

    test('keeps the place and the results in the notifier', () async {
      await container.read(studySessionProvider(args).future);
      final notifier = container.read(studySessionProvider(args).notifier)
        ..advance(CardOutcome.good);
      notifier.advance(CardOutcome.skipped);

      final session = container.read(studySessionProvider(args)).value!;
      expect(session.position, 2);
      expect(session.results, <int, CardOutcome>{
        0: CardOutcome.good,
        1: CardOutcome.skipped,
      });
      expect(session.place, (
        kind: SessionBlockKind.newWords,
        index: 2,
        size: 2,
      ));
    });

    test('and they outlive the screen, being kept alive', () async {
      final sub = container.listen(studySessionProvider(args), (_, _) {});
      await container.read(studySessionProvider(args).future);
      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.easy);
      sub.close();
      await pumpEventQueue();

      expect(container.read(studySessionProvider(args)).value?.position, 1);
    });

    test('the blocks, for the progress strip', () async {
      await container.read(studySessionProvider(args).future);
      container.read(studySessionProvider(args).notifier)
        ..advance(CardOutcome.good)
        ..advance(CardOutcome.good);
      final blocks = container.read(studySessionProvider(args)).value!.blocks;
      expect(blocks, <StudyBlock>[
        (kind: SessionBlockKind.revise, size: 1, done: 1),
        (kind: SessionBlockKind.newWords, size: 2, done: 1),
        (kind: SessionBlockKind.grammar, size: 1, done: 0),
      ]);
    });
  });

  group('the screen', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      ThemeData? theme,
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
          overrides: overrides(),
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
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
      return ProviderScope.containerOf(
        tester.element(find.byType(StudyScreen)),
      );
    }

    testWidgets("under glass the aurora leads with the word's gender", (
      tester,
    ) async {
      // The aurora drifts forever unless motion is reduced.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester, theme: AppTheme.glass());
      await tester.pump();
      // Straße, the first card, is feminine.
      expect(
        tester.widget<AuroraBackdrop>(find.byType(AuroraBackdrop)).leading,
        tester.element(find.byType(StudyScreen)).tokens.color.die,
      );
    });

    testWidgets('no rating bar before the card is turned over', (tester) async {
      final container = await pump(tester);
      expect(find.byType(DpRatingBar), findsNothing);
      expect(find.text(l10n.studyShowMeaning), findsOneWidget);

      await tester.tap(find.text(l10n.studyShowMeaning));
      await tester.pump();

      expect(
        container.read(studySessionProvider(args)).value?.revealed,
        isTrue,
      );
      expect(find.text(l10n.studyShowMeaning), findsNothing);
    });

    testWidgets('FR-T2-01 a tap on the card turns it over too', (tester) async {
      final container = await pump(tester);
      expect(find.byType(StudyBack), findsNothing);

      await tester.tap(find.textContaining('Nomen'));
      await tester.pumpAndSettle();

      expect(
        container.read(studySessionProvider(args)).value?.revealed,
        isTrue,
      );
      // Straße's back: its meaning and its example.
      expect(find.byType(StudyBack), findsOneWidget);
      expect(find.text('Die Straße ist lang.'), findsOneWidget);
    });

    testWidgets('each card starts face down again', (tester) async {
      final container = await pump(tester);
      final notifier = container.read(studySessionProvider(args).notifier)
        ..reveal()
        ..advance(CardOutcome.good);
      await tester.pumpAndSettle();
      expect(notifier.state.value?.revealed, isFalse);
      expect(find.text(l10n.studyShowMeaning), findsOneWidget);
    });

    testWidgets('autoplay_headword plays each new card as it comes', (
      tester,
    ) async {
      spoken.clear();
      final container = await pump(tester);
      await tester.pump();
      expect(spoken, <String>['die Straße']);

      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pump();
      await tester.pump();
      expect(spoken, <String>['die Straße', 'das Haus']);
    });

    testWidgets('shows the block and the place in it', (tester) async {
      await pump(tester);
      expect(find.text(l10n.studyBlockRevise(1, 1)), findsOneWidget);
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
    });

    testWidgets('FR-T2-06 a block starting plays its banner for a second', (
      tester,
    ) async {
      final container = await pump(tester);
      // The first block's banner has come and gone by now.
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();

      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final banner = find.text(l10n.studyBannerNewCategory('Wohnen'));
      expect(banner, findsOneWidget);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(of: banner, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        1,
      );

      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(of: banner, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        0,
      );
    });

    testWidgets('and a card inside a block does not', (tester) async {
      final container = await pump(tester);
      final notifier = container.read(studySessionProvider(args).notifier)
        // Into New: its banner plays, then goes.
        ..advance(CardOutcome.good);
      await tester.pump(StudyScreen.bannerTime);
      await tester.pumpAndSettle();

      // The second new word is inside the block: nothing plays.
      notifier.advance(CardOutcome.good);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final banner = find.text(l10n.studyBannerNewCategory('Wohnen'));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(of: banner, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        0,
      );
    });

    testWidgets('FR-T2-07 closing never prompts, and clears the session', (
      tester,
    ) async {
      final container = await pump(tester);
      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pump();

      await tester.tap(find.bySemanticsLabel(l10n.studyClose));
      await tester.pumpAndSettle();

      expect(find.byType(StudyScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // Cleared: opened again, it starts from what is still open.
      final again = await tester.runAsync(
        () => container.read(studySessionProvider(args).future),
      );
      expect(again?.position, 0);
    });

    testWidgets("and so does Android's back", (tester) async {
      final container = await pump(tester);
      container
          .read(studySessionProvider(args).notifier)
          .advance(CardOutcome.good);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(StudyScreen), findsNothing);
      final again = await tester.runAsync(
        () => container.read(studySessionProvider(args).future),
      );
      expect(again?.position, 0, reason: 'cleared, not kept');
    });

    testWidgets('the last card done brings up the summary over it (#107)', (
      tester,
    ) async {
      final container = await pump(tester);
      final notifier = container.read(studySessionProvider(args).notifier);
      for (var i = 0; i < 4; i++) {
        notifier.advance(CardOutcome.good);
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(find.byType(StudySummarySheet), findsOneWidget);
    });

    testWidgets('the menu: auto-play and speech speed are settings', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel(l10n.studyMenu));
      await tester.pumpAndSettle();

      expect(find.text(l10n.studyMenuWordDetails), findsOneWidget);
      expect(find.text(l10n.studyMenuReport), findsOneWidget);

      await tester.tap(find.byType(AdaptiveSwitch));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.autoplayHeadword), isFalse);

      await tester.tap(find.text('0.75×'));
      await tester.pumpAndSettle();
      expect(settings.read(SettingKeys.ttsSpeed), 0.75);
    });
  });

  test('a report is a pre-filled issue on the project', () {
    final uri = StudyMenu.reportUri(
      const StudyItem(SessionBlockKind.newWords, 'uid-haus'),
    );
    expect(uri.host, 'github.com');
    expect(uri.path, '/MdRahmatUllah/DeutschPlan/issues/new');
    expect(uri.queryParameters['title'], contains('uid-haus'));
    expect(uri.queryParameters['body'], contains('uid-haus'));
  });

  group('the way in', () {
    // The page's own route transitions are in the tree too.
    Finder inside(Type type) => find.descendant(
      of: find.byType(StudyTransition),
      matching: find.byType(type),
    );

    Future<void> transition(
      WidgetTester tester, {
      required AdaptiveChrome chrome,
      Rect? origin,
      bool still = false,
    }) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        value: 0.5,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              disableAnimations: still,
            ),
            child: AdaptiveChromeScope(
              chrome: chrome,
              child: StudyTransition(
                animation: controller,
                origin: origin,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Android grows out of the tapped card', (tester) async {
      const card = Rect.fromLTWH(16, 400, 368, 66);
      await transition(tester, chrome: AdaptiveChrome.material, origin: card);
      final clip = tester.widget<ClipRRect>(inside(ClipRRect)).clipper!;
      final rect = clip.getClip(const Size(400, 800)).outerRect;
      // Halfway: larger than the card, smaller than the screen, around it.
      expect(rect.width, greaterThan(card.width));
      expect(rect.height, greaterThan(card.height));
      expect(rect.height, lessThan(800));
    });

    testWidgets('iOS slides up', (tester) async {
      await transition(tester, chrome: AdaptiveChrome.cupertino);
      expect(inside(SlideTransition), findsOneWidget);
    });

    testWidgets('reduce motion cross-fades', (tester) async {
      await transition(
        tester,
        chrome: AdaptiveChrome.material,
        origin: Rect.zero,
        still: true,
      );
      expect(inside(FadeTransition), findsOneWidget);
      expect(inside(ClipRRect), findsNothing);
    });
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
