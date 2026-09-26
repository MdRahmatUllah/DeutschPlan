import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/data/repositories/rating_service.dart'
    show CardMode;
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/translation_repository.dart';
import 'package:deutschplan/data/repositories/word_actions.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../db/content_fixture.dart';
import '../services/fake_tts.dart';
import '../core/text_clipping.dart';
import 'word_fixtures.dart';

/// W1 · Word detail (#140, spec key R04): `word-detail.md`.
void main() {
  late AppLocalizations l10n;
  late SettingsRepository settings;
  late FakeTts tts;
  late _Actions actions;
  late List<Uri> opened;
  String? went;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> openSettings(WidgetTester tester, AppDatabase db) async {
    await tester.runAsync(() async {
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
  }

  /// A page with a word to open, as every list row is, and W2 behind
  /// *Compare*.
  ///
  /// The opener sits in a shell with a tab bar, as every list in the app
  /// does, so the sheet has to rise over the bar rather than stop above it.
  GoRouter router(String uid) => GoRouter(
    routes: <RouteBase>[
      ShellRoute(
        builder: (_, _, child) => Scaffold(
          body: child,
          bottomNavigationBar: const SizedBox(height: 80, child: Text('tabs')),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () => WordRoute.open(context, uid),
                        child: const Text('open'),
                      ),
                      // W1 as a page, as a link opens it (#404).
                      GestureDetector(
                        onTap: () => context.push('/word/$uid'),
                        child: const Text('page'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/word/:uid',
        builder: (_, state) =>
            WordDetailScreen(uid: state.pathParameters['uid']!),
      ),
      GoRoute(
        path: '/compare/:uid',
        builder: (_, state) {
          went = state.uri.path;
          return const Scaffold(body: Text('W2'));
        },
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    WordDetail? detail,
    bool missing = false,
    Object? error,
    ReviewHistory history = artboardHistory,
    Size size = const Size(390, 844),
    double ratio = 3,
    ThemeData? theme,
    bool voice = true,
    AdaptiveChrome chrome = AdaptiveChrome.material,
    List<Override> extra = const <Override>[],
    bool page = false,
  }) async {
    actions = _Actions();
    opened = <Uri>[];
    tester.view
      ..physicalSize = size * ratio
      ..devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    went = null;
    tts = FakeTts(voice: voice);
    await openSettings(tester, AppDatabase.memory());
    final uid = detail?.word.uid ?? 'uid-strasse';

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          fakeVoice(tts),
          todayProvider.overrideWithValue('2026-09-21'),
          wordDetailProvider.overrideWith(
            (ref, uid) => error != null
                ? Stream<WordDetail?>.error(error)
                : Stream.value(
                    missing ? null : detail ?? artboardWordDetail(uid: uid),
                  ),
          ),
          wordHistoryProvider.overrideWith((ref, uid) => Stream.value(history)),
          wordActionsProvider.overrideWithValue(actions),
          openWebProvider.overrideWithValue((page) async {
            opened.add(page);
            return true;
          }),
          ...extra,
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: router(uid),
          builder: (context, child) =>
              AdaptiveChromeScope(chrome: chrome, child: child!),
        ),
      ),
    );
    await tester.tap(find.text(page ? 'page' : 'open'));
    await tester.pumpAndSettle();
  }

  testWidgets("#421 W1's page keeps its header colour behind the status "
      'bar when it scrolls', (tester) async {
    await pump(tester, page: true);
    final scaffold = tester.widget<AdaptiveScaffold>(
      find
          .descendant(
            of: find.byType(WordDetailScreen),
            matching: find.byType(AdaptiveScaffold),
          )
          .first,
    );
    expect(
      scaffold.statusBarColour,
      tester.element(find.byType(WordDetailScreen)).tokens.color.die,
      reason: 'die Straße',
    );
  });

  group('R04 the word', () {
    testWidgets('the header: article and headword, speaker, step, status', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('die Straße', findRichText: true), findsOneWidget);
      expect(find.byType(DpSpeakerButton), findsOneWidget);
      expect(find.text('A1.1'), findsOneWidget);
      expect(find.text(l10n.wordStatusDone), findsOneWidget);
    });

    testWidgets('BR-CONTENT-02 a meaning updated this week wears the Updated '
        'chip beside the status, read as "Meaning updated"', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        extra: <Override>[
          recentlyUpdatedProvider.overrideWith(
            (ref) async => <String>{'uid-strasse'},
          ),
        ],
      );
      expect(find.text(l10n.wordUpdated), findsOneWidget);
      // Read as "Meaning updated", once: W1's header merges its texts into
      // one node (checked with a semantics dump), and the chip's label is in it.
      final label = tester.getSemantics(find.byType(UpdatedChip)).label;
      expect(l10n.wordUpdatedSemantic.allMatches(label), hasLength(1));
      semantics.dispose();
      expect(
        tester.getTopLeft(find.text(l10n.wordUpdated)).dx,
        greaterThan(tester.getTopLeft(find.text(l10n.wordStatusDone)).dx),
      );
    });

    testWidgets('BR-CONTENT-02 and no chip for a word the update left alone', (
      tester,
    ) async {
      await pump(
        tester,
        extra: <Override>[
          recentlyUpdatedProvider.overrideWith(
            (ref) async => <String>{'uid-other'},
          ),
        ],
      );
      expect(find.text(l10n.wordStatusDone), findsOneWidget);
      expect(find.text(l10n.wordUpdated), findsNothing);
    });

    testWidgets('the caption, and the meanings in both languages', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Nomen · die Straße, -n · /স্ট্রাসে/'), findsOneWidget);
      expect(find.text('street, road'), findsOneWidget);
      expect(find.text('রাস্তা'), findsOneWidget);
    });

    testWidgets('an English learner reads the English only', (tester) async {
      await pump(
        tester,
        detail: artboardWordDetail(meaning: MeaningLanguage.english),
      );
      expect(find.text('street, road'), findsOneWidget);
      expect(find.text('রাস্তা'), findsNothing);
    });

    testWidgets('every example with its translation', (tester) async {
      await pump(tester);
      expect(find.text(l10n.wordExamples.toUpperCase()), findsOneWidget);
      expect(
        find.text('Die Straße ist wegen Bauarbeiten gesperrt.'),
        findsOneWidget,
      );
      expect(
        find.text('The street is closed because of roadworks.'),
        findsOneWidget,
      );
      expect(find.text('Wir wohnen in einer ruhigen Straße.'), findsOneWidget);
      expect(find.text('We live on a quiet street.'), findsOneWidget);
    });

    testWidgets('collocations and register in the note box', (tester) async {
      await pump(tester);
      expect(
        find.text(
          l10n.studyCollocations(
            'die Straße überqueren · auf der Straße · die Straße entlang',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.studyRegister('Gasse = narrow street · Weg = path, way'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the history caption', (tester) async {
      await pump(tester);
      expect(
        find.text('Next review in 8 days · reviewed 5 times · last: Good'),
        findsOneWidget,
      );
    });

    testWidgets('a word never reviewed has no history caption', (tester) async {
      await pump(tester, history: (reviews: 0, last: null));
      expect(find.textContaining('reviewed'), findsNothing);
    });
  });

  group('R04 sound', () {
    testWidgets('the speaker says the word with its article; a long-press '
        'at 0.75× (FR-T2-09)', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.longPress(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(tts.said, <(String, double)>[
        ('die Straße', 1),
        ('die Straße', 0.75),
      ]);
    });

    testWidgets('FR-W1-04 an example plays, and the sheet stays open', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Wir wohnen in einer ruhigen Straße.'));
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['Wir wohnen in einer ruhigen Straße.']);
      expect(find.byType(WordDetailView), findsOneWidget);
    });

    testWidgets('the speaker is its own button to a screen reader, not the '
        'whole header', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        tester.getSemantics(find.byType(DpSpeakerButton)),
        matchesSemantics(
          label: l10n.wordPronounce('die Straße'),
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('no German voice: the speaker is slashed', (tester) async {
      await pump(tester, voice: false);
      expect(
        tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state,
        DpSpeakerState.unavailable,
      );
    });

    for (final (device, size, ratio) in <(String, Size, double)>[
      ('a phone', const Size(390, 844), 3),
      ('a tablet', const Size(1024, 768), 2),
    ]) {
      testWidgets('on $device, the no-voice toast shows over W1, not under '
          'it', (tester) async {
        await pump(tester, voice: false, size: size, ratio: ratio);
        await tester.tap(find.byType(DpSpeakerButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(l10n.speakerNoVoice).hitTestable(), findsOneWidget);
        // Its own messenger: the page's Scaffold under the sheet gets no
        // copy of it.
        expect(find.text(l10n.speakerNoVoice), findsOneWidget);
      });
    }

    testWidgets('?speak=1 once only, when the word is already loaded', (
      tester,
    ) async {
      tts = FakeTts();
      await openSettings(tester, AppDatabase.memory());
      final words = StreamController<WordDetail?>();
      addTearDown(words.close);
      final container = ProviderContainer(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          fakeVoice(tts),
          todayProvider.overrideWithValue('2026-09-21'),
          wordDetailProvider.overrideWith((ref, uid) => words.stream),
          wordHistoryProvider.overrideWith(
            (ref, uid) => Stream.value(artboardHistory),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Someone else is already watching the word, so it has data when the
      // page subscribes: the listener then fires inside `listenManual`.
      final held = container.listen(
        wordDetailProvider('uid-strasse'),
        (_, _) {},
      );
      addTearDown(held.close);
      words.add(artboardWordDetail());
      await tester.runAsync(pumpEventQueue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const WordDetailScreen(uid: 'uid-strasse', speak: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      words.add(artboardWordDetail(status: WordStatus.learning));
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['die Straße']);
    });

    testWidgets('?speak=1 plays the headword once it has loaded, and once '
        'only', (tester) async {
      tts = FakeTts();
      await openSettings(tester, AppDatabase.memory());
      final words = StreamController<WordDetail?>();
      addTearDown(words.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsProvider.overrideWithValue(settings),
            fakeVoice(tts),
            todayProvider.overrideWithValue('2026-09-21'),
            wordDetailProvider.overrideWith((ref, uid) => words.stream),
            wordHistoryProvider.overrideWith(
              (ref, uid) => Stream.value(artboardHistory),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: const WordDetailScreen(uid: 'uid-strasse', speak: true),
          ),
        ),
      );
      await tester.pump();
      expect(tts.spoken, isEmpty, reason: 'nothing to say yet');

      words.add(artboardWordDetail());
      await tester.pumpAndSettle();
      // The same word again, as a rating re-emits it.
      words.add(artboardWordDetail(status: WordStatus.learning));
      await tester.pumpAndSettle();
      expect(tts.spoken, <String>['die Straße']);
    });
  });

  group('FR-W1-06 Compare', () {
    testWidgets('offered for a headword that names a set, and opens W2', (
      tester,
    ) async {
      await pump(
        tester,
        detail: artboardWordDetail(
          uid: 'uid-circa',
          article: null,
          german: 'circa / etwa / rund',
        ),
      );
      final link = find.text(l10n.wordCompare('circa / etwa / rund'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(went, '/compare/uid-circa');
    });

    testWidgets('not for a single word', (tester) async {
      await pump(tester);
      expect(find.textContaining('Compare'), findsNothing);
    });
  });

  group('R04 the header colours', () {
    DpTokens tokensOf(WidgetTester tester) =>
        tester.element(find.byType(WordDetailView)).tokens;

    testWidgets('on paper, the word takes its gender fill\'s ink', (
      tester,
    ) async {
      await pump(tester);
      final tokens = tokensOf(tester);
      expect(
        tester.widget<DpHeadword>(find.byType(DpHeadword)).colour,
        tokens.color.onPrimary,
      );
      final header = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byType(DpHeadword),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((header.decoration as BoxDecoration).color, tokens.color.die);
    });

    testWidgets('der on Cobalt reads in white', (tester) async {
      await pump(
        tester,
        detail: artboardWordDetail(article: 'der', german: 'Weg'),
      );
      expect(
        tester.widget<DpHeadword>(find.byType(DpHeadword)).colour,
        tokensOf(tester).color.onDer,
      );
    });

    testWidgets('a word with no article sits on Oat', (tester) async {
      await pump(tester, detail: artboardWordDetail(article: null));
      final header = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byType(DpHeadword),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (header.decoration as BoxDecoration).color,
        tokensOf(tester).surface.muted,
      );
    });

    testWidgets('under glass, the article keeps its own colour', (
      tester,
    ) async {
      await pump(tester, theme: AppTheme.glass());
      expect(tester.widget<DpHeadword>(find.byType(DpHeadword)).colour, null);
    });
  });

  group('R04 presentation', () {
    double top(WidgetTester tester) =>
        tester.getTopLeft(find.byType(WordDetailView)).dy;

    testWidgets('a phone: a sheet at the large detent, down to medium, and '
        'closed below it', (tester) async {
      await pump(tester);
      // Measured against the whole screen: the sheet is over the tab bar.
      expect(top(tester), closeTo(844 * (1 - WordDetailView.large), 1));
      expect(tester.getRect(find.byType(WordDetailView)).bottom, 844);

      await tester.timedDrag(
        find.text('die Straße', findRichText: true),
        const Offset(0, 250),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(top(tester), closeTo(844 * (1 - WordDetailView.medium), 1));

      await tester.timedDrag(
        find.text('die Straße', findRichText: true),
        const Offset(0, 300),
        const Duration(milliseconds: 800),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'the opener is back');
    });

    testWidgets('on iOS too, dragged below medium it closes', (tester) async {
      await pump(tester, chrome: AdaptiveChrome.cupertino);
      await tester.timedDrag(
        find.text('die Straße', findRichText: true),
        const Offset(0, 600),
        const Duration(milliseconds: 1200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
    });

    testWidgets('a tablet: a pane along the right edge; a tap beside it '
        'closes it', (tester) async {
      await pump(tester, size: const Size(1024, 768), ratio: 2);
      final pane = tester.getRect(find.byType(WordDetailView));
      expect(pane.right, 1024);
      expect(pane.width, 420);
      expect(pane.height, 768);

      await tester.tapAt(const Offset(100, 384));
      await tester.pumpAndSettle();
      expect(find.byType(WordDetailView), findsNothing);
    });
  });

  group('#141 W1 actions', () {
    Finder action(String label) => find.widgetWithText(DpButton, label);

    Future<void> tapAction(WidgetTester tester, String label) async {
      await tester.ensureVisible(action(label));
      await tester.pumpAndSettle();
      await tester.tap(action(label));
      await tester.pumpAndSettle();
    }

    testWidgets("FR-W1-02 a Done word's row, as the artboard draws it", (
      tester,
    ) async {
      await pump(tester);
      expect(action(l10n.wordMarkKnown), findsOneWidget);
      expect(action(l10n.wordSuspend), findsOneWidget);
      expect(action(l10n.wordReset), findsOneWidget);
      expect(action(l10n.wordCopy), findsOneWidget);
      expect(action(l10n.wordAddToday), findsNothing, reason: 'To do only');
      expect(action(l10n.wordResume), findsNothing);
      expect(action(l10n.wordTranslate), findsNothing, reason: 'mt is off');
      expect(find.text('Duden'), findsOneWidget);
      expect(find.text('Linguee'), findsNothing, reason: "R1's, not W1's");
    });

    testWidgets("FR-W1-01 a To-do word offers Add to today; FR-W1-04 its "
        'snackbar undoes it', (tester) async {
      await pump(tester, detail: artboardWordDetail(status: WordStatus.todo));
      await tapAction(tester, l10n.wordAddToday);
      expect(actions.calls, <String>['addToToday uid-strasse A1.1 2026-09-21']);
      expect(
        find.text(l10n.wordAddedToday('die Straße')).hitTestable(),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(actions.undone, <String>['addToToday']);
    });

    testWidgets("FR-W1-01 an action and its Undo each re-read Today's plan, "
        'which is read once when the day opens', (tester) async {
      var reads = 0;
      await pump(
        tester,
        extra: <Override>[
          todayPlanProvider.overrideWith((ref) async {
            reads++;
            return const DailyPlan(
              date: '2026-09-21',
              revise: <String>[],
              newToday: <String>[],
              grammarDue: <String>[],
              backlog: <String>[],
              activeStep: 'A1.1',
              isStudyDay: true,
            );
          }),
        ],
      );
      final today = ProviderScope.containerOf(
        tester.element(find.byType(WordDetailView)),
      ).listen(todayPlanProvider.future, (_, _) {});
      addTearDown(today.close);
      await tester.pump();
      expect(reads, 1);

      await tapAction(tester, l10n.wordMarkKnown);
      expect(reads, 2);
      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(reads, 3);
    });

    testWidgets('FR-W1-02 Mark known, with its Undo', (tester) async {
      await pump(tester);
      await tapAction(tester, l10n.wordMarkKnown);
      expect(actions.calls, <String>['markKnown uid-strasse 2026-09-21']);
      expect(
        find.text(l10n.wordMarkedKnown('die Straße')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.undo));
      await tester.pumpAndSettle();
      expect(actions.undone, <String>['markKnown']);
    });

    testWidgets('BR-STATUS-03 Suspend; a suspended word offers Resume', (
      tester,
    ) async {
      await pump(tester);
      await tapAction(tester, l10n.wordSuspend);
      expect(actions.calls, <String>['suspend uid-strasse 2026-09-21']);

      await pump(
        tester,
        detail: artboardWordDetail(status: WordStatus.suspended),
      );
      expect(
        action(l10n.wordMarkKnown),
        findsNothing,
        reason: 'rating it would resume it unasked',
      );
      await tapAction(tester, l10n.wordResume);
      expect(actions.calls, <String>['resume uid-strasse']);
    });

    testWidgets('FR-W1-02 Reset asks first: keeping it changes nothing', (
      tester,
    ) async {
      await pump(tester);
      await tapAction(tester, l10n.wordReset);
      expect(find.text(l10n.wordResetTitle('die Straße')), findsOneWidget);
      await tester.tap(find.text(l10n.wordResetCancel));
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty);

      await tapAction(tester, l10n.wordReset);
      await tester.tap(find.text(l10n.wordResetConfirm));
      await tester.pumpAndSettle();
      expect(actions.calls, <String>['reset uid-strasse 2026-09-21']);
      expect(
        find.text(l10n.wordWasReset('die Straße')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('FR-W1-03 the card toggle writes the mode; the chosen one '
        'is inert', (tester) async {
      await pump(tester);
      Finder chip(String label) =>
          find.byWidgetPredicate((w) => w is DpChip && w.label == label);
      await tester.ensureVisible(chip(l10n.wordPlainCard));
      await tester.tap(chip(l10n.wordPlainCard));
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty, reason: 'already plain');

      await tester.tap(chip(l10n.wordClozeCard));
      await tester.pumpAndSettle();
      expect(actions.calls, <String>['setCardMode uid-strasse cloze']);
      expect(
        find.text(l10n.wordNowCloze('die Straße')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('FR-W1-04 a double tap acts once', (tester) async {
      await pump(tester);
      await tester.ensureVisible(action(l10n.wordMarkKnown));
      await tester.pumpAndSettle();
      actions.hold = true;
      await tester.tap(action(l10n.wordMarkKnown));
      await tester.pump();
      await tester.tap(action(l10n.wordMarkKnown), warnIfMissed: false);
      await tester.pump();
      actions.release();
      await tester.pumpAndSettle();
      expect(actions.calls, <String>['markKnown uid-strasse 2026-09-21']);
    });

    testWidgets('Copy copies the word with its article', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester);
      await tapAction(tester, l10n.wordCopy);
      expect(copied, <String>['die Straße']);
      expect(
        find.text(l10n.wordCopied('die Straße')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('the web chips open the headword', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.text('DWDS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DWDS'));
      await tester.pump();
      expect(opened, <Uri>[
        SearchRepository.webLinks('Straße')[WebSource.dwds]!,
      ]);
    });

    testWidgets('FR-W1-05 with translation on, Translate puts each '
        'example in the meaning language under it', (tester) async {
      final asked = <(String, String)>[];
      await pump(
        tester,
        detail: artboardWordDetail(translate: true),
        extra: <Override>[
          translationRepositoryProvider.overrideWithValue(
            _Translations((text, to) {
              asked.add((text, to));
              return 'অনুবাদ';
            }),
          ),
        ],
      );
      await tapAction(tester, l10n.wordTranslate);
      expect(asked, <(String, String)>[
        ('Die Straße ist wegen Bauarbeiten gesperrt.', 'bn'),
        ('Wir wohnen in einer ruhigen Straße.', 'bn'),
      ]);
      expect(find.text('অনুবাদ'), findsNWidgets(2));
    });

    testWidgets('FR-W1-05 an English learner is not offered Translate: the '
        'examples come in English already', (tester) async {
      await pump(
        tester,
        detail: artboardWordDetail(
          translate: true,
          meaning: MeaningLanguage.english,
        ),
      );
      expect(action(l10n.wordTranslate), findsNothing);
    });
  });

  group('R04 states', () {
    testWidgets('a word the course does not have says so', (tester) async {
      await pump(tester, missing: true);
      expect(find.text(l10n.wordNotFound), findsOneWidget);
    });

    testWidgets('a failed query: the error panel and Retry', (tester) async {
      await pump(tester, error: StateError('disk'));
      expect(find.text(l10n.wordLoadFailed), findsOneWidget);
      expect(find.byType(DpErrorPanel), findsOneWidget);
    });
  });

  group('R04 historyCaption', () {
    WordWithState word({String? due, WordStatus status = WordStatus.done}) {
      final base = artboardWordDetail(status: status).word;
      return WordWithState(
        word: base.word,
        state: base.state!.copyWith(due: Value(due)),
        status: status,
      );
    }

    const today = '2026-09-21';
    const history = (reviews: 5, last: Rating.good);

    test('due today, or overdue', () {
      expect(
        historyCaption(word(due: today), history, today, l10n),
        'Due today · reviewed 5 times · last: Good',
      );
      expect(
        historyCaption(word(due: '2026-09-19'), history, today, l10n),
        startsWith('Due today'),
      );
    });

    test('tomorrow', () {
      expect(
        historyCaption(word(due: '2026-09-22'), history, today, l10n),
        startsWith('Next review tomorrow'),
      );
    });

    test('BR-STATUS-03 suspended: no next review', () {
      expect(
        historyCaption(
          word(due: '2026-09-29', status: WordStatus.suspended),
          (reviews: 1, last: Rating.again),
          today,
          l10n,
        ),
        'reviewed once · last: Again',
      );
    });

    test('never reviewed: nothing', () {
      expect(
        historyCaption(
          word(due: '2026-09-29'),
          (reviews: 0, last: null),
          today,
          l10n,
        ),
        isNull,
      );
    });
  });

  group('R04 over the database', () {
    testWidgets('the course\'s examples and tip; the status follows a '
        'rating while the sheet is open', (tester) async {
      final directory = Directory.systemTemp.createTempSync('deutschplan_w1');
      final content = ContentFixture.write('${directory.path}/content.db').file;
      final db = AppDatabase.memory();
      await tester.runAsync(
        () => db.customStatement(
          "ATTACH DATABASE '${ContentDao.attachPath(content)}' AS c",
        ),
      );
      await openSettings(tester, db);
      tts = FakeTts();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            settingsProvider.overrideWithValue(settings),
            fakeVoice(tts),
            todayProvider.overrideWithValue('2026-09-21'),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            routerConfig: router(ContentFixture.strasse),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('open'));
      await settle();
      expect(find.text('Die Straße ist lang.'), findsOneWidget);
      expect(find.text('The street is long.'), findsOneWidget);
      expect(
        find.text(
          l10n.studyTip(
            tipText((
              en: 'Straße is die, not der.',
              bn: 'Straße হলো die।',
            ), settings.read(SettingKeys.meaningLanguage)),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.wordStatusToDo), findsOneWidget);

      await tester.runAsync(
        () => db
            .into(db.wordState)
            .insert(
              WordStateCompanion.insert(
                wordUid: ContentFixture.strasse,
                status: const Value('learning'),
                introducedOn: const Value('2026-09-21'),
                reps: const Value(1),
                stability: const Value(1),
                due: const Value('2026-09-22'),
              ),
            ),
      );
      await settle();
      expect(find.text(l10n.wordStatusLearning), findsOneWidget);
    });
  });

  testWidgets('#404 at 200 % text the back row keeps its label whole, in '
      'either chrome', (tester) async {
    textAt(tester, 2);
    for (final chrome in AdaptiveChrome.values) {
      await pump(tester, chrome: chrome, page: true);
      expectNothingClipped(tester, within: find.byType(AdaptiveBackButton));
    }
  });
}

/// W1's actions, recorded; each undo records its name.
class _Actions implements WordActions {
  final List<String> calls = <String>[];
  final List<String> undone = <String>[];

  /// While set, an action waits for [release]: a second tap lands mid-action.
  bool hold = false;
  Completer<void>? _gate;

  void release() => _gate?.complete();

  Future<Undo> _record(String call) async {
    calls.add(call);
    if (hold) {
      _gate = Completer<void>();
      await _gate!.future;
    }
    final name = call.split(' ').first;
    return () async => undone.add(name);
  }

  @override
  Future<Undo> addToToday(
    String uid, {
    required String today,
    required String step,
  }) => _record('addToToday $uid $step $today');

  @override
  Future<Undo> markKnown(String uid, {required String today}) =>
      _record('markKnown $uid $today');

  @override
  Future<Undo> suspend(String uid, {required String today}) =>
      _record('suspend $uid $today');

  @override
  Future<Undo> resume(String uid) => _record('resume $uid');

  @override
  Future<Undo> reset(String uid, {required String today}) =>
      _record('reset $uid $today');

  @override
  Future<Undo> setCardMode(String uid, CardMode mode) =>
      _record('setCardMode $uid ${mode.name}');
}

class _Translations implements TranslationRepository {
  _Translations(this.answer);

  final String Function(String text, String to) answer;

  @override
  Future<String?> translate(
    String text, {
    required String from,
    required String to,
  }) async => answer(text, to);
}
