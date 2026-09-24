import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/features/learn/grammar_library_screen.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'today_fixtures.dart';

/// L3 · Grammar library — #117.
void main() {
  const today = '2026-09-21';
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  group('FR-L3-02 the filters read grammar_state', () {
    final topics = artboardLibrary();
    int count(LibraryFilter filter) =>
        topics.where((topic) => inFilter(filter, topic, today)).length;

    test('All · 182, Not learned yet · 145, Due · 2', () {
      expect(count(LibraryFilter.all), 182);
      expect(count(LibraryFilter.notLearned), 145);
      expect(count(LibraryFilter.due), 2);
    });
  });

  late String? went;
  late GoRouter routes;

  Future<void> pump(WidgetTester tester) async {
    went = null;
    routes = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const GrammarLibraryScreen()),
        GoRoute(
          path: '/learn/grammar/:uid',
          builder: (_, state) {
            went = state.uri.path;
            return const Scaffold(body: Text('L4'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: todayStub(),
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

  /// The band pinned at the top of the list.
  String pinned(WidgetTester tester) {
    final list = tester.getRect(find.byType(CustomScrollView));
    final bands = tester
        .widgetList<LevelBand>(find.byType(LevelBand))
        .where(
          (band) =>
              (tester.getRect(find.byWidget(band)).top - list.top).abs() < 1,
        );
    return bands.single.code;
  }

  testWidgets('the chips carry live counts', (tester) async {
    await pump(tester);
    expect(find.text(l10n.libraryAll(182)), findsOneWidget);
    expect(find.text(l10n.libraryNotLearned(145)), findsOneWidget);
    expect(find.text(l10n.libraryDue(2)), findsOneWidget);
  });

  testWidgets('FR-L3-01 grouped by level: A1 · Anfänger first', (tester) async {
    await pump(tester);
    expect(find.text('A1 · ANFÄNGER'), findsOneWidget);
    expect(find.text('A2 · GRUNDSTUFE'), findsOneWidget);
    expect(pinned(tester), 'A1');
  });

  testWidgets('Due leaves the two due, under their own levels', (tester) async {
    await pump(tester);
    await tester.tap(find.text(l10n.libraryDue(2)));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryRow), findsNWidgets(2));
    expect(find.text('A1 · ANFÄNGER'), findsNothing);
    expect(find.text('A2 · GRUNDSTUFE'), findsOneWidget);
    // The counts stay the course's, whatever is shown.
    expect(find.text(l10n.libraryAll(182)), findsOneWidget);
  });

  testWidgets('Not learned yet starts at Dativ nach Präpositionen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l10n.libraryNotLearned(145)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<LibraryRow>(find.byType(LibraryRow))
          .first
          .topic
          .topic
          .topic,
      'Dativ nach Präpositionen',
    );
  });

  testWidgets('a band stays at the top while its level scrolls under it', (
    tester,
  ) async {
    await pump(tester);
    // Into A2's rows: A1's band has gone and A2's holds the top.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(pinned(tester), 'A2');
    // A fast fling far down: whichever level is under the top, its band.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      4000,
    );
    await tester.pumpAndSettle();
    final top = tester.getRect(find.byType(CustomScrollView)).top;
    final first = tester
        .widgetList<LibraryRow>(find.byType(LibraryRow))
        .where((row) => tester.getRect(find.byWidget(row)).bottom > top + 40)
        .first;
    expect(pinned(tester), first.topic.topic.levelCode);
  });

  testWidgets('a topic opens L4 over the library, and back returns', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Perfekt mit haben'));
    await tester.pumpAndSettle();
    expect(went, '/learn/grammar/lib2');
    routes.pop();
    await tester.pumpAndSettle();
    expect(find.byType(GrammarLibraryScreen), findsOneWidget);
  });
}
