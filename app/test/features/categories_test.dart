import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/learn/categories_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L5 · Categories — #120.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  late String? went;

  Future<void> pump(
    WidgetTester tester, [
    List<CategoryProgress>? categories,
  ]) async {
    went = null;
    // The artboard's phone, where a long name wraps.
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const CategoriesScreen()),
        GoRoute(
          path: '/learn/categories/:id',
          builder: (_, state) {
            went = state.uri.path;
            return const Scaffold(body: Text('L6'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          categoriesProvider.overrideWith(
            (ref) => Stream.value(categories ?? artboardCategories()),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: routes,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR-L5-01 a card per category: its name, words and bar', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.categoriesLine), findsOneWidget);
    expect(find.text('Wohnen & Haushalt'), findsOneWidget);
    expect(find.text(l10n.categoriesWords(412)), findsOneWidget);
    final bar = tester.widget<DpSegmentedBar>(
      find.descendant(
        of: find.widgetWithText(CategoryCard, 'Wohnen & Haushalt'),
        matching: find.byType(DpSegmentedBar),
      ),
    );
    expect((bar.done, bar.learning, bar.todo), (150, 40, 222));
  });

  testWidgets('two columns, in the order the query gives', (tester) async {
    await pump(tester);
    final wohnen = tester.getRect(
      find.widgetWithText(CategoryCard, 'Wohnen & Haushalt'),
    );
    final arbeit = tester.getRect(
      find.widgetWithText(CategoryCard, 'Arbeit & Beruf'),
    );
    final essen = tester.getRect(
      find.widgetWithText(CategoryCard, 'Essen & Trinken'),
    );
    expect(arbeit.top, wohnen.top);
    expect(arbeit.left, greaterThan(wohnen.right));
    expect(essen.left, wohnen.left);
    expect(essen.top, greaterThan(wohnen.bottom));
  });

  testWidgets('a name that wraps grows its row, and the other card keeps its '
      'text at the bottom', (tester) async {
    CategoryProgress category(int id, String name, int words) =>
        CategoryProgress(
          id: id,
          name: name,
          words: words,
          todo: words,
          learning: 0,
          done: 0,
        );
    await pump(tester, <CategoryProgress>[
      category(1, 'Geld', 30),
      category(2, 'Behörden & Formulare', 20),
      category(3, 'Post', 10),
    ]);
    Rect card(String name) =>
        tester.getRect(find.widgetWithText(CategoryCard, name));
    expect(card('Geld').height, card('Behörden & Formulare').height);
    expect(
      card('Behörden & Formulare').height,
      greaterThan(card('Post').height),
    );
    expect(
      tester.getRect(find.text(l10n.categoriesWords(30))).top,
      tester.getRect(find.text(l10n.categoriesWords(20))).top,
    );
  });

  testWidgets('tile colours cycle through the palette, card by card', (
    tester,
  ) async {
    await pump(tester);
    final tokens = tester.element(find.byType(CategoriesScreen)).tokens;
    final cards = tester
        .widgetList<CategoryCard>(find.byType(CategoryCard))
        .toList();
    expect(cards, hasLength(8));
    for (final (index, card) in cards.indexed) {
      expect(card.colours, categoryColours(tokens, index));
    }
    expect(
      cards.map((card) => card.colours.$1).toSet(),
      hasLength(8),
      reason: 'eight cards, eight colours',
    );
  });

  test('the palette is deterministic and wraps after eight', () {
    final tokens = DpTokens.light();
    expect(categoryColours(tokens, 0), (
      tokens.color.primary,
      tokens.color.onPrimary,
    ));
    expect(categoryColours(tokens, 3), (tokens.color.der, tokens.color.onDer));
    expect(categoryColours(tokens, 8), categoryColours(tokens, 0));
    expect(categoryColours(tokens, 13), categoryColours(tokens, 5));
  });

  testWidgets('a card opens its category', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Reisen & Verkehr'));
    await tester.pumpAndSettle();
    expect(went, '/learn/categories/4');
  });

  testWidgets('a card is a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.widgetWithText(CategoryCard, 'Gesundheit')),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        label:
            'Gesundheit\n${l10n.categoriesWords(276)}\n'
            '64 done, 8 learning, 204 to do',
      ),
    );
    semantics.dispose();
  });
}
