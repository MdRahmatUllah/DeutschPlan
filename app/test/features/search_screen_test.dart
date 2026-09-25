import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/search/search_screen.dart';
import 'package:deutschplan/features/words/word_detail_screen.dart';
import 'package:deutschplan/features/words/word_row.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/app_router.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';
import '../db/content_fixture.dart';
import '../services/fake_tts.dart';
import 'search_fixtures.dart';
import 'today_fixtures.dart';

/// R1 · Search results (#137, spec key R01): `search.md` and the engine's
/// `03-domain/search.md`.
void main() {
  late AppLocalizations l10n;
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeTts tts;
  late List<Uri> opened;
  GoRouter? router;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  /// R1 over the content fixture: das Haus, die Tür (A1.1), die Straße
  /// (A1.2), and their sentences.
  ///
  /// [routed] puts it under the app's router at `/search`, for what goes
  /// through the route.
  Future<void> pump(
    WidgetTester tester, {
    String? step,
    bool routed = false,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tts = FakeTts();
    opened = <Uri>[];
    await tester.runAsync(() async {
      db = AppDatabase.memory();
      final directory = Directory.systemTemp.createTempSync('dp_search');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      settings = SettingsRepository(db);
      await settings.load();
    });
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(tts),
          todayProvider.overrideWithValue('2026-09-21'),
          openWebProvider.overrideWithValue((page) async {
            opened.add(page);
            return true;
          }),
          ...extra,
        ],
        child: routed
            ? MaterialApp.router(
                routerConfig: router = buildRouter(
                  initialLocation: SearchRoute(step: step).location,
                ),
                theme: AppTheme.light(),
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: supportedLocales,
              )
            : MaterialApp(
                theme: AppTheme.light(),
                localizationsDelegates: appLocalizationsDelegates,
                supportedLocales: supportedLocales,
                home: SearchScreen(step: step),
              ),
      ),
    );
    await tester.pumpAndSettle();
    if (routed) addTearDown(router!.dispose);
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(SearchScreen.debounce);
    await settle(tester);
  }

  Finder heading(String text) => find.text(text.toUpperCase());

  group('FR-R1-01 results', () {
    testWidgets('wait 120 ms after the last keystroke', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Haus');
      await tester.pump(const Duration(milliseconds: 100));
      // The database gets real time to answer, but the clock stands still:
      // settling would run it past the 120 ms.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pump();
      expect(heading(l10n.searchExact(1)), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
      await settle(tester);
      expect(heading(l10n.searchExact(1)), findsOneWidget);
      expect(find.text('das Haus', findRichText: true), findsOneWidget);
    });

    testWidgets('BR-SEARCH-03 "strase" finds die Straße under Similar words', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'strase');
      expect(heading(l10n.searchSimilar(1)), findsOneWidget);
      expect(heading(l10n.searchExact(1)), findsNothing);
      expect(
        tester.getTopLeft(find.text('die Straße', findRichText: true)).dy,
        greaterThan(tester.getTopLeft(heading(l10n.searchSimilar(1))).dy),
      );
    });

    testWidgets('BR-SEARCH-01 the groups in tier order, with their counts', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Haus');
      final exact = tester.getTopLeft(heading(l10n.searchExact(1))).dy;
      final sentences = tester.getTopLeft(heading(l10n.searchSentences(2))).dy;
      expect(exact, lessThan(sentences));
    });

    testWidgets('a sentence marks the word it matched, and names its word '
        'and step', (tester) async {
      await pump(tester);
      await type(tester, 'offen');
      expect(heading(l10n.searchSentences(1)), findsOneWidget);
      expect(find.text('die Tür · A1.1'), findsOneWidget);

      final tokens = tester.element(find.byType(SearchScreen)).tokens;
      final sentence = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == 'Die Tür ist offen.',
        ),
      );
      final marked = <String>[];
      sentence.text.visitChildren((span) {
        if (span is TextSpan &&
            span.style?.backgroundColor == tokens.color.accent) {
          marked.add(span.text!);
        }
        return true;
      });
      expect(marked, <String>['offen']);
    });

    testWidgets(
      'BR-SEARCH-02 a word typed with its umlaut finds its sentences',
      (tester) async {
        await pump(tester);
        await type(tester, 'Tür');
        expect(
          find.text('Die Tür ist offen.', findRichText: true),
          findsWidgets,
        );
      },
    );

    testWidgets('FR-R1-01 a row opens W1 over the results', (tester) async {
      await pump(tester);
      await type(tester, 'Haus');
      await tester.tap(find.text('das Haus', findRichText: true));
      await settle(tester);
      expect(
        tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
        ContentFixture.haus,
      );
    });

    testWidgets('FR-R1-01 the last results stay up while the next query '
        'loads', (tester) async {
      await pump(
        tester,
        extra: <Override>[
          searchResultsProvider.overrideWith(
            (ref, args) => args.$1 == 'strase'
                ? Stream.value(artboardSearch())
                : const Stream<SearchView>.empty(),
          ),
        ],
      );
      await type(tester, 'strase');
      await type(tester, 'strasse');
      expect(heading(l10n.searchExact(1)), findsOneWidget);
    });

    testWidgets('FR-R1-01 clearing empties the field and the results', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Haus');
      await tester.tap(find.bySemanticsLabel(l10n.searchClear));
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(heading(l10n.searchExact(1)), findsNothing);
    });
  });

  testWidgets('FR-R1-01 a failed search says so, and Retry asks again', (
    tester,
  ) async {
    var fail = true;
    await pump(
      tester,
      extra: <Override>[
        searchResultsProvider.overrideWith(
          (ref, query) => fail
              ? Stream<SearchView>.error(StateError('disk'))
              : Stream.value(artboardSearch()),
        ),
      ],
    );
    await type(tester, 'strase');
    expect(find.text(l10n.searchFailed), findsOneWidget);

    fail = false;
    await tester.tap(find.text(l10n.retry));
    await settle(tester);
    expect(find.text(l10n.searchFailed), findsNothing);
    expect(heading(l10n.searchExact(1)), findsOneWidget);
  });

  testWidgets(
    'BR-SEARCH-01 each group heading is a heading to a screen reader',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await type(tester, 'Haus');
      expect(
        tester.getSemantics(heading(l10n.searchExact(1))),
        matchesSemantics(
          label: l10n.searchExact(1).toUpperCase(),
          isHeader: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets('FR-R1-02 the search key opens the first exact match', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Haus');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await settle(tester);
    expect(
      tester.widget<WordDetailView>(find.byType(WordDetailView)).uid,
      ContentFixture.haus,
    );
  });

  testWidgets('FR-R1-03 the play icon pronounces without opening the row', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'Haus');
    await tester.tap(find.byType(WordPlayButton));
    await tester.pump();
    expect(tts.spoken, <String>['das Haus']);
    await settle(tester);
    expect(find.byType(WordDetailView), findsNothing);
  });

  testWidgets('FR-R1-05 a fresh open puts the cursor in the field', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('FR-R1-05 coming back to the tab keeps the query and the '
      'results', (tester) async {
    final router = buildRouter(guards: RouteGuards.permissive());
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...todayStub(),
          searchResultsProvider.overrideWith(
            (ref, query) => Stream.value(artboardSearch()),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.tabSearch).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'strase');
    await tester.pump(SearchScreen.debounce);
    await tester.pumpAndSettle();
    expect(heading(l10n.searchExact(1)), findsOneWidget);

    await tester.tap(find.text(l10n.tabToday).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.tabSearch).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'strase',
    );
    expect(heading(l10n.searchExact(1)), findsOneWidget);
  });

  testWidgets('FR-R1-06 a web chip opens its page for the query', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, 'Haus');
    await tester.tap(find.bySemanticsLabel(l10n.searchOpenWeb('Duden')));
    await tester.pump();
    expect(opened, <Uri>[SearchRepository.webLinks('Haus')[WebSource.duden]!]);
  });

  group('#138 idle', () {
    Finder recentChip(String term) => find.byWidgetPredicate(
      (w) => w is DpChip && w.kind == DpChipKind.filter && w.label == term,
    );

    List<String> stored() {
      final raw = settings.read(SettingKeys.recentSearches);
      return raw == null
          ? const <String>[]
          : <String>[for (final t in jsonDecode(raw) as List<Object?>) '$t'];
    }

    Future<void> addWord(
      WidgetTester tester, {
      required String german,
      required String meaning,
      String? article,
      String? where,
      int seen = 1,
      String at = '2026-09-20T10:00:00Z',
    }) async {
      await tester.runAsync(
        () => db
            .into(db.customWords)
            .insert(
              CustomWordsCompanion.insert(
                createdAt: at,
                german: german,
                meaning: meaning,
                article: Value(article),
                whereSeen: Value(where),
                timesSeen: Value(seen),
              ),
            ),
      );
      await settle(tester);
    }

    testWidgets('nothing yet: no headings, only the way to add a word', (
      tester,
    ) async {
      await pump(tester);
      expect(heading(l10n.searchRecent), findsNothing);
      expect(heading(l10n.searchMyWords(0)), findsNothing);
      expect(find.text(l10n.searchAddWord), findsOneWidget);
    });

    testWidgets('FR-R1-04 a submitted search is remembered, and kept in '
        'recent_searches', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Haus');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      await settle(tester);
      expect(stored(), <String>['Haus']);
    });

    testWidgets('FR-R1-04 opening a result remembers the search; typing '
        'alone does not', (tester) async {
      await pump(tester);
      await type(tester, 'offen');
      expect(stored(), isEmpty, reason: 'a pause in typing is not a search');
      await tester.tap(find.text('Die Tür ist offen.', findRichText: true));
      await settle(tester);
      expect(stored(), <String>['offen']);
    });

    testWidgets('FR-R1-04 a word row and a web chip remember it too', (
      tester,
    ) async {
      await pump(tester);
      await type(tester, 'Haus');
      await tester.tap(find.bySemanticsLabel(l10n.searchOpenWeb('Duden')));
      await tester.pump();
      expect(stored(), <String>['Haus']);

      await type(tester, 'Tür');
      await tester.tap(find.text('die Tür', findRichText: true).first);
      await settle(tester);
      expect(stored(), <String>['Tür', 'Haus']);
    });

    testWidgets('FR-R1-04 the last ten, newest first; the same search again '
        'moves up', (tester) async {
      await pump(tester);
      final recent = ProviderScope.containerOf(
        tester.element(find.byType(SearchScreen)),
      ).read(recentSearchesProvider.notifier);
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await recent.remember('Wort$i');
        }
        await recent.remember('wort5');
      });
      await tester.pumpAndSettle();
      expect(stored(), hasLength(10));
      expect(stored().first, 'wort5');
      expect(stored().where((t) => t.toLowerCase() == 'wort5'), hasLength(1));
      expect(stored(), isNot(contains('Wort0')), reason: 'the oldest go');
      expect(recentChip('wort5'), findsOneWidget);
    });

    testWidgets('FR-R1-04 a recent chip searches it again, and Clear '
        'forgets them all', (tester) async {
      await pump(tester);
      final recent = ProviderScope.containerOf(
        tester.element(find.byType(SearchScreen)),
      ).read(recentSearchesProvider.notifier);
      await tester.runAsync(() async {
        await recent.remember('Haus');
        await recent.remember('Tür');
      });
      await tester.pumpAndSettle();
      expect(heading(l10n.searchRecent), findsOneWidget);

      await tester.tap(recentChip('Haus'));
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Haus',
      );
      expect(heading(l10n.searchExact(1)), findsOneWidget);
      expect(stored().first, 'Haus', reason: 'searched again, so newest');

      await tester.tap(find.bySemanticsLabel(l10n.searchClear));
      await settle(tester);
      await tester.tap(find.text(l10n.searchClearRecent));
      await settle(tester);
      expect(heading(l10n.searchRecent), findsNothing);
      expect(settings.read(SettingKeys.recentSearches), isNull);
    });

    testWidgets('FR-R1-04 Clear is a button of its own to a screen reader, '
        'not part of the heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final recent = ProviderScope.containerOf(
        tester.element(find.byType(SearchScreen)),
      ).read(recentSearchesProvider.notifier);
      await tester.runAsync(() => recent.remember('Haus'));
      await tester.pumpAndSettle();
      final clear = tester
          .getSemantics(find.text(l10n.searchClearRecent))
          .getSemanticsData();
      expect(clear.label, l10n.searchClearRecentLabel);
      expect(clear.flagsCollection.isButton, isTrue);
      expect(
        tester
            .getSemantics(heading(l10n.searchRecent))
            .getSemanticsData()
            .label,
        isNot(contains(l10n.searchClearRecentLabel)),
      );
      semantics.dispose();
    });

    testWidgets('My words: the meaning, where it was seen, the count from '
        'the second time; newest first', (tester) async {
      await pump(tester);
      await addWord(
        tester,
        german: 'Quittung',
        article: 'die',
        meaning: 'receipt',
        where: 'Bäckerei',
      );
      await addWord(
        tester,
        german: 'Pfandflasche',
        article: 'das',
        meaning: 'deposit bottle',
        where: 'Rewe receipt',
        seen: 3,
        at: '2026-09-21T10:00:00Z',
      );
      expect(heading(l10n.searchMyWords(2)), findsOneWidget);
      expect(
        find.text('deposit bottle · Rewe receipt · ${l10n.searchSeen(3)}'),
        findsOneWidget,
      );
      expect(find.text('receipt · Bäckerei'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('das Pfandflasche', findRichText: true)).dy,
        lessThan(
          tester.getTopLeft(find.text('die Quittung', findRichText: true)).dy,
        ),
      );
    });

    testWidgets('#314 at 200 % text the headings and their notes fit, and '
        'nothing is cut', (tester) async {
      textAt(tester, 2);
      await pump(tester);
      final recent = ProviderScope.containerOf(
        tester.element(find.byType(SearchScreen)),
      ).read(recentSearchesProvider.notifier);
      await tester.runAsync(() => recent.remember('Haus'));
      await addWord(
        tester,
        german: 'Pfandflasche',
        article: 'das',
        meaning: 'deposit bottle',
        where: 'Rewe receipt',
        seen: 3,
      );
      expect(tester.takeException(), isNull, reason: 'a row overflowed');
      expectNothingClipped(tester, within: find.byType(ListView).last);
      // The note gives way too: the heading keeps a line of its own rather
      // than being squeezed into a word a line.
      final line = tester
          .renderObject<RenderParagraph>(
            find.text(l10n.searchMyWords(1).toUpperCase()),
          )
          .getMaxIntrinsicHeight(double.infinity);
      expect(
        tester.getSize(find.text(l10n.searchMyWords(1).toUpperCase())).height,
        line,
      );
    });

    testWidgets('a word of my own opens it in R2; Add a word I found opens '
        'R2 empty', (tester) async {
      await pump(tester, routed: true);
      await addWord(tester, german: 'ausschließlich', meaning: 'exclusively');
      await tester.tap(find.text('ausschließlich', findRichText: true));
      await settle(tester);
      expect(router!.state.uri.path, startsWith('/search/add/'));

      router!.go('/search');
      await settle(tester);
      await tester.tap(find.text(l10n.searchAddWord));
      await settle(tester);
      expect(router!.state.uri.path, '/search/add');
    });
  });

  group('FR-R1-07 filter chips', () {
    List<Override> many(int count, {String Function(int)? step}) => <Override>[
      searchResultsProvider.overrideWith(
        (ref, query) => Stream.value(
          SearchView(
            words: <SearchRow>[
              for (var i = 0; i < count; i++)
                searchRow(
                  'w$i',
                  article: 'das',
                  german: 'Wort$i',
                  meaning: 'word $i',
                  tier: SearchTier.startsWith,
                  step: step?.call(i) ?? (i.isEven ? 'A1.1' : 'A2.1'),
                  status: i < 3 ? WordStatus.done : WordStatus.todo,
                ),
            ],
            sentences: const <SentenceHit>[],
          ),
        ),
      ),
    ];

    Finder chip(String label) => find.byWidgetPredicate(
      (w) => w is DpChip && w.kind == DpChipKind.filter && w.label == label,
    );

    testWidgets('none for ten results', (tester) async {
      await pump(tester, extra: many(10));
      await type(tester, 'wort');
      expect(chip(l10n.wordStatusDone), findsNothing);
    });

    testWidgets('past ten: status and step chips, and a tap filters', (
      tester,
    ) async {
      await pump(tester, extra: many(11));
      await type(tester, 'wort');
      expect(chip(l10n.wordStatusDone), findsOneWidget);
      expect(chip('A1.1'), findsOneWidget);
      expect(chip('A2.1'), findsOneWidget);

      await tester.tap(chip(l10n.wordStatusDone));
      await tester.pumpAndSettle();
      expect(find.byType(WordRow), findsNWidgets(3));

      await tester.tap(chip('A2.1'));
      await tester.pumpAndSettle();
      // Done and A2.1: Wort1 only.
      expect(find.byType(WordRow), findsOneWidget);
      expect(find.text('das Wort1', findRichText: true), findsOneWidget);

      // A new search, submitted, starts unfiltered.
      await tester.enterText(find.byType(TextField), 'worte');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(tester.widget<DpChip>(chip(l10n.wordStatusDone)).selected, false);
      expect(tester.widget<DpChip>(chip('A2.1')).selected, false);
    });

    testWidgets('results in one step get no step chip', (tester) async {
      await pump(tester, extra: many(11, step: (_) => 'A1.1'));
      await type(tester, 'wort');
      expect(chip(l10n.wordStatusDone), findsOneWidget);
      expect(chip('A1.1'), findsNothing);
    });
  });

  testWidgets("FR-R1-07 L2's step keeps the results to it, until its chip "
      'goes; a second trip brings it back', (tester) async {
    await pump(tester, step: 'A1.2', routed: true);
    await type(tester, 'ist');
    expect(heading(l10n.searchSentences(1)), findsOneWidget);
    expect(find.text('die Straße · A1.2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(l10n.searchRemoveStep('A1.2')));
    await settle(tester);
    expect(heading(l10n.searchSentences(3)), findsOneWidget);
    expect(router!.state.uri.queryParameters, isEmpty);

    router!.go(const SearchRoute(step: 'A1.2').location);
    await settle(tester);
    expect(find.bySemanticsLabel(l10n.searchRemoveStep('A1.2')), findsOne);
    expect(heading(l10n.searchSentences(1)), findsOneWidget);
  });
}
