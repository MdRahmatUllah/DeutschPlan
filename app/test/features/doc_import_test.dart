import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/features/documents/doc_import_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/services/shared_text.dart';

/// D1 · Learn from a document (#1227): `doc-import.md`, text in, pasted or
/// shared.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const letter =
      'Nebenkosten 2025\n\nSehr geehrte Frau Okafor, die Abrechnung ist da.';

  /// D1 over R1, with D2's route as a page that says which document.
  Future<GoRouter> pump(
    WidgetTester tester, {
    required FakeDocuments docs,
    String? clipboard = letter,
    SharedText? shared,
    String? arrival,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => <String, Object?>{'value': clipboard != null},
        'Clipboard.getData' =>
          clipboard == null ? null : <String, Object?>{'text': clipboard},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final router = GoRouter(
      initialLocation: arrival == null
          ? '/search/import'
          : '/search/import?arrival=$arrival',
      routes: <RouteBase>[
        GoRoute(
          path: '/search',
          builder: (_, _) => const Text('R1'),
          routes: <RouteBase>[
            GoRoute(
              path: 'import',
              builder: (_, state) => DocImportScreen(
                arrival: state.uri.queryParameters['arrival'],
              ),
            ),
            GoRoute(
              path: 'document/:id',
              builder: (_, state) => Text('D2 ${state.pathParameters['id']}'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          documentRepositoryProvider.overrideWithValue(docs),
          sharedTextProvider.overrideWithValue(shared ?? FakeShared(null)),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 2, 9)),
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
    return router;
  }

  testWidgets('FR-D1-01 Paste shows the clipboard in a box to edit, and Find '
      'my words saves the clean text, named by its first line, then opens D2', (
    tester,
  ) async {
    final docs = FakeDocuments();
    final router = await pump(tester, docs: docs);

    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    final box = tester.widget<TextField>(find.byType(TextField));
    expect(box.controller!.text, letter);

    await tester.enterText(find.byType(TextField), '$letter Ver-\nwaltung.');
    await tester.tap(find.text(l10n.docImportFind));
    await tester.pumpAndSettle();

    expect(docs.checked.single, contains('Verwaltung'), reason: 'cleaned');
    final saved = docs.saved.single;
    expect(saved.title, 'Nebenkosten 2025');
    expect(saved.source, 'paste');
    expect(saved.body, docs.checked.single);
    expect(router.state.uri.path, '/search/document/7');
    expect(find.text('D2 7'), findsOneWidget);
  });

  testWidgets('an empty clipboard: Paste text is off, and says why', (
    tester,
  ) async {
    final docs = FakeDocuments();
    await pump(tester, docs: docs, clipboard: null);

    expect(find.text(l10n.docImportPasteEmpty), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text(l10n.docImportPaste)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    semantics.dispose();
    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('FR-D1-02 a text over 20,000 characters is cut at a sentence '
      'end, with a note', (tester) async {
    final long = 'Das ist ein Satz. ' * 1200; // 21,600 characters
    final docs = FakeDocuments();
    await pump(tester, docs: docs, clipboard: long);

    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    expect(find.text(l10n.docImportCut(docMaxChars)), findsOneWidget);

    await tester.tap(find.text(l10n.docImportFind));
    await tester.pump();
    expect(
      find.text(l10n.docImportCut(docMaxChars)),
      findsOneWidget,
      reason: 'the toast',
    );
    await tester.pumpAndSettle();
    final body = docs.saved.single.body;
    expect(body.length, lessThanOrEqualTo(docMaxChars));
    expect(body, endsWith('Satz.'));
  });

  testWidgets('FR-D1-04 a text that isn\'t German warns before anything is '
      'saved: Continue anyway saves it, Cancel saves nothing', (tester) async {
    final docs = FakeDocuments(share: 0.1);
    final router = await pump(tester, docs: docs);
    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docImportFind));
    await tester.pumpAndSettle();

    expect(find.text(l10n.docImportNotGerman), findsOneWidget);
    expect(docs.saved, isEmpty);
    await tester.tap(find.text(l10n.docImportCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.docImportPaste), findsOneWidget);
    expect(docs.saved, isEmpty);

    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docImportFind));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docImportContinueAnyway));
    await tester.pumpAndSettle();
    expect(docs.saved, hasLength(1));
    expect(router.state.uri.path, '/search/document/7');
  });

  testWidgets('FR-D1-05 Cancel while it reads saves nothing, even when the '
      'reading ends after', (tester) async {
    final check = Completer<double>();
    final docs = FakeDocuments(pending: check);
    await pump(tester, docs: docs);
    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docImportFind));
    await tester.pump();

    expect(find.text(l10n.docImportFinding), findsOneWidget);
    expect(find.text(l10n.docImportPasted), findsOneWidget);
    await tester.tap(find.text(l10n.docImportCancel));
    await tester.pump();
    check.complete(0.9);
    await tester.pumpAndSettle();

    expect(docs.saved, isEmpty);
    expect(find.text(l10n.docImportPaste), findsOneWidget);
  });

  testWidgets('FR-D1-01 "Share → Sogda": the shared text goes straight to '
      'processing, saved as shared; a share with no text leaves the choices', (
    tester,
  ) async {
    final docs = FakeDocuments();
    final shared = FakeShared('Liebe Anna, wie geht es dir?');
    final router = await pump(tester, docs: docs, shared: shared, arrival: '1');

    expect(docs.saved.single.source, 'share');
    expect(docs.saved.single.title, 'Liebe Anna, wie geht es dir?');
    expect(router.state.uri.path, '/search/document/7');

    final none = FakeDocuments();
    await pump(tester, docs: none, shared: FakeShared(null), arrival: '2');
    expect(find.text(l10n.docImportPaste), findsOneWidget);
    expect(none.checked, isEmpty);
  });

  testWidgets('a text with no line of words is named by its day', (
    tester,
  ) async {
    final docs = FakeDocuments(share: 0.9);
    await pump(tester, docs: docs, shared: FakeShared('…'), arrival: '1');
    expect(docs.saved.single.title, l10n.docImportUntitled('Oct 2'));
  });

  testWidgets('a reading that fails says so, and Try again reads it again', (
    tester,
  ) async {
    final docs = FakeDocuments(fail: 1);
    await pump(tester, docs: docs);
    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.docImportFind));
    await tester.pumpAndSettle();

    expect(find.text(l10n.docImportFailed), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(docs.saved, hasLength(1));
  });

  testWidgets('back from the box returns to the choices, not to R1', (
    tester,
  ) async {
    await pump(tester, docs: FakeDocuments());
    await tester.tap(find.text(l10n.docImportPaste));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.docImportPaste), findsOneWidget);
    expect(find.text('R1'), findsNothing);
  });
}

/// What D1 saved, and the texts it checked for German.
class FakeDocuments extends Fake implements DocumentRepository {
  FakeDocuments({this.share = 0.9, this.pending, this.fail = 0});

  final double share;
  final Completer<double>? pending;

  /// How many checks fail before one answers.
  int fail;

  final List<String> checked = <String>[];
  final List<({String title, String source, String body})> saved =
      <({String title, String source, String body})>[];

  @override
  Future<double> germanShareOf(String body) async {
    checked.add(body);
    if (fail > 0) {
      fail--;
      throw StateError('the isolate died');
    }
    return pending?.future ?? share;
  }

  @override
  Future<int> create({
    required String title,
    required String source,
    required String body,
    int pageCount = 1,
  }) async {
    saved.add((title: title, source: source, body: body));
    return 7;
  }
}

class FakeShared implements SharedText {
  FakeShared(this._text);

  String? _text;

  @override
  Future<String?> take() async {
    final text = _text;
    _text = null;
    return text;
  }
}
