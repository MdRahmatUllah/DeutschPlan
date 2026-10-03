import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/features/documents/my_documents_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

import 'my_documents_fixtures.dart';

/// D3 · My documents (#1295): `my-documents.md`.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// D3 over R1, with D1, D2 and M3 as pages that say what they are.
  Future<GoRouter> pump(WidgetTester tester, List<Override> overrides) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/search/documents',
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (_, _) => const Text('R1'),
          routes: <RouteBase>[
            GoRoute(
              path: 'documents',
              builder: (_, _) => const MyDocumentsScreen(),
            ),
            GoRoute(
              path: 'document/:id',
              builder: (_, state) => Text('D2 ${state.pathParameters['id']}'),
            ),
            GoRoute(path: 'import', builder: (_, _) => const Text('D1')),
          ],
        ),
        GoRoute(path: '/me/settings', builder: (_, _) => const Text('M3')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> openMenu(WidgetTester tester, String title) async {
    await tester.tap(find.bySemanticsLabel(l10n.myDocumentsOptions(title)));
    await tester.pumpAndSettle();
  }

  testWidgets('FR-D3-01 every kept document, newest first, with its source, '
      'its day and the words added from it', (tester) async {
    await pump(tester, myDocumentsStub());

    final titles = <String>[
      'Nebenkosten 2025',
      'Termin beim Bürgeramt',
      'Mietvertrag',
      'Elternbrief Schule',
    ];
    final tops = <double>[
      for (final title in titles) tester.getTopLeft(find.text(title)).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));
    for (final line in <String>[
      '2 Oct · ${l10n.myDocumentsPhotos(4)} · ${l10n.myDocumentsAdded(5)}',
      '28 Sep · ${l10n.myDocumentsText} · ${l10n.myDocumentsAdded(3)}',
      '20 Sep · ${l10n.myDocumentsPdf(6)} · ${l10n.myDocumentsAdded(12)}',
      '12 Sep · ${l10n.myDocumentsPhotos(1)} · ${l10n.myDocumentsNoneAdded}',
    ]) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text(l10n.myDocumentsStorage(4, 18)), findsOneWidget);
    // A PDF's icon is D1's Choose a PDF's (agent-3 on #1299).
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });

  test('#1358 FR-D3-01 a row with no word added says so, in every language, '
      'never that the document has nothing new', () async {
    const nothingNew = <String>[
      'nothing new',
      'nic nowego',
      'ничего нового',
      'নতুন কিছু নেই',
    ];
    for (final locale in supportedLocales) {
      final words = await AppLocalizations.delegate.load(locale);
      expect(nothingNew, isNot(contains(words.myDocumentsNoneAdded)));
    }
    expect(l10n.myDocumentsNoneAdded, 'no words added yet');
  });

  testWidgets('with no photo kept, the storage line counts documents alone '
      '(agent-3 on #1299)', (tester) async {
    await pump(tester, myDocumentsStub(FakeMyDocuments()..bytes = 0));
    expect(find.text(l10n.myDocumentsStorageNone(4)), findsOneWidget);
    expect(find.text(l10n.myDocumentsStorage(4, 0)), findsNothing);
  });

  testWidgets('FR-D3-01 a row opens D2 on its document', (tester) async {
    final router = await pump(tester, myDocumentsStub());

    await tester.tap(find.text('Mietvertrag'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/search/document/2');
    expect(find.text('D2 2'), findsOneWidget);
  });

  testWidgets('New document opens D1; Settings opens M3', (tester) async {
    final router = await pump(tester, myDocumentsStub());

    await tester.tap(find.text(l10n.myDocumentsNew));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/search/import');

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.meSettings));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/me/settings');
  });

  testWidgets('FR-D3-02 BR-DOC-05 Delete asks first: Keep keeps it, Delete '
      'removes it and says so', (tester) async {
    final documents = FakeMyDocuments();
    await pump(tester, myDocumentsStub(documents));

    await openMenu(tester, 'Mietvertrag');
    await tester.tap(find.text(l10n.myDocumentsDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.myDocumentsDeleteTitle('Mietvertrag')), findsOne);
    expect(find.text(l10n.myDocumentsDeleteBody), findsOneWidget);
    await tester.tap(find.text(l10n.myDocumentsDeleteKeep));
    await tester.pumpAndSettle();
    expect(documents.deleted, isEmpty);
    expect(find.text('Mietvertrag'), findsOneWidget);

    await openMenu(tester, 'Mietvertrag');
    await tester.tap(find.text(l10n.myDocumentsDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.myDocumentsDelete).last);
    await tester.pumpAndSettle();

    expect(documents.deleted, <int>[2]);
    expect(find.text('Mietvertrag'), findsNothing);
    expect(find.text(l10n.myDocumentsDeleted('Mietvertrag')), findsOneWidget);
    // The photos went with it: the storage line is read again.
    expect(find.text(l10n.myDocumentsStorageNone(3)), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Rename keeps what was typed; a blank one keeps the title', (
    tester,
  ) async {
    await pump(tester, myDocumentsStub());

    await openMenu(tester, 'Mietvertrag');
    await tester.tap(find.text(l10n.myDocumentsRename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text(l10n.meNameSave));
    await tester.pumpAndSettle();
    expect(find.text('Mietvertrag'), findsOneWidget);

    await openMenu(tester, 'Mietvertrag');
    await tester.tap(find.text(l10n.myDocumentsRename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Mietvertrag 2026 ');
    await tester.tap(find.text(l10n.meNameSave));
    await tester.pumpAndSettle();

    expect(find.text('Mietvertrag 2026'), findsOneWidget);
    expect(find.text('Mietvertrag'), findsNothing);
  });

  testWidgets('empty: what to bring, and New document opens D1', (
    tester,
  ) async {
    final router = await pump(
      tester,
      myDocumentsStub(FakeMyDocuments(const [])),
    );

    expect(find.text(l10n.myDocumentsEmptyTitle), findsOneWidget);
    expect(find.text(l10n.myDocumentsEmptyBody), findsOneWidget);
    expect(find.text(l10n.myDocumentsStorage(0, 0)), findsNothing);
    await tester.tap(find.text(l10n.myDocumentsNew));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/search/import');
  });

  testWidgets('a row and its menu are a button each, named', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, myDocumentsStub());

    expect(
      tester.getSemantics(
        find.bySemanticsLabel(l10n.myDocumentsOptions('Mietvertrag')),
      ),
      matchesSemantics(
        label: l10n.myDocumentsOptions('Mietvertrag'),
        isButton: true,
        hasTapAction: true,
      ),
    );
    final row = tester.getSemantics(
      find.ancestor(
        of: find.text('Mietvertrag'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.button ?? false),
        ),
      ),
    );
    expect(row.label, contains('Mietvertrag'));
    expect(row.label, contains(l10n.myDocumentsAdded(12)));
    semantics.dispose();
  });

  testWidgets('with one document, its menu is the ⋮ alone, not the card '
      '(agent-3 on #1299)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      myDocumentsStub(FakeMyDocuments(artboardDocuments().take(1).toList())),
    );
    final menu = tester.getSemantics(
      find.bySemanticsLabel(l10n.myDocumentsOptions('Nebenkosten 2025')),
    );
    expect(menu.rect.size, const Size(48, 48));
    semantics.dispose();
  });
}
