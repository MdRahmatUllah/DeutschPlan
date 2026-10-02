import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/documents/ocr.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/features/documents/doc_import_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sogda/services/page_photos.dart';
import 'package:sogda/services/shared_text.dart';

import 'settings_fixtures.dart';

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
    PagePhotos? photos,
    StubSettings? settings,
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
          pagePhotosProvider.overrideWithValue(photos ?? FakePhotos()),
          settingsProvider.overrideWithValue(settings ?? StubSettings()),
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

  group('#1229 photos', () {
    const sharp = 0.95;
    OcrPage page(String text, [double confidence = sharp]) =>
        OcrPage(<List<OcrWord>>[
          for (final line in text.split('\n'))
            <OcrWord>[
              for (final word in line.split(' '))
                (text: word, confidence: confidence),
            ],
        ]);

    testWidgets('FR-D1-01 Take photos, a page at a time, then Done: each read '
        'on the phone, saved as photo with its page count and its photos '
        '(BR-DOC-05)', (tester) async {
      final docs = FakeDocuments();
      final photos = FakePhotos(
        taken: <String>['p1.jpg', 'p2.jpg'],
        pages: <String, OcrPage>{
          'p1.jpg': page(
            'Sehr geehrte Frau Okafor,\ndie Abrechnung der Ver-\nwaltung',
          ),
          'p2.jpg': page('ist da.'),
        },
      );
      final router = await pump(tester, docs: docs, photos: photos);

      await tester.tap(find.text(l10n.docImportTakePhotos));
      await tester.pumpAndSettle();
      expect(find.text(l10n.docImportPage(1)), findsOneWidget);
      await tester.tap(find.text(l10n.docImportAddPage));
      await tester.pumpAndSettle();
      expect(find.text(l10n.docImportPage(2)), findsOneWidget);
      expect(find.text(l10n.docImportPhotos(2)), findsOneWidget);
      await tester.tap(find.text(l10n.docImportDone));
      await tester.pumpAndSettle();

      expect(photos.readPaths, <String>['p1.jpg', 'p2.jpg']);
      final saved = docs.saved.single;
      expect(saved.source, 'photo');
      expect(saved.pageCount, 2);
      expect(
        saved.body,
        'Sehr geehrte Frau Okafor,\ndie Abrechnung der Verwaltung\n\nist da.',
        reason: 'cleaned, a page a paragraph',
      );
      expect(docs.images, <int, List<String>>{
        7: <String>['p1.jpg', 'p2.jpg'],
      });
      expect(router.state.uri.path, '/search/document/7');
    });

    testWidgets('BR-DOC-05 with Save original images off, the photos go', (
      tester,
    ) async {
      final docs = FakeDocuments();
      final settings = StubSettings()..put(SettingKeys.docSaveImages, false);
      await pump(
        tester,
        docs: docs,
        settings: settings,
        photos: FakePhotos(
          chosen: <String>['g1.jpg'],
          pages: <String, OcrPage>{'g1.jpg': page('Die Miete ist da.')},
        ),
      );
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pumpAndSettle();
      expect(docs.saved.single.source, 'photo');
      expect(docs.images, isEmpty);
    });

    testWidgets('FR-D1-03 a hard page opens Check the text, its unsure words '
        'marked; the learner\'s edit is what is read', (tester) async {
      final docs = FakeDocuments();
      await pump(
        tester,
        docs: docs,
        photos: FakePhotos(
          chosen: <String>['g1.jpg', 'g2.jpg'],
          pages: <String, OcrPage>{
            'g1.jpg': page('Am Dienstag kommt'),
            'g2.jpg': OcrPage(<List<OcrWord>>[
              <OcrWord>[
                (text: 'der', confidence: 0.9),
                (text: 'Hausmelster.', confidence: 0.3),
                (text: 'Er', confidence: 0.4),
              ],
            ]),
          },
        ),
      );
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pumpAndSettle();

      expect(find.text(l10n.docImportCheckTitle), findsOneWidget);
      expect(find.text(l10n.docImportCheckIntro(2)), findsOneWidget);
      expect(find.text(l10n.docImportCheckCount(2)), findsOneWidget);
      expect(docs.saved, isEmpty, reason: 'nothing saved before the check');

      await tester.enterText(find.byType(TextField), 'der Hausmeister. Er');
      await tester.pump();
      expect(find.text(l10n.docImportCheckCount(1)), findsOneWidget);
      await tester.tap(find.text(l10n.docImportContinue));
      await tester.pumpAndSettle();
      expect(
        docs.saved.single.body,
        'Am Dienstag kommt\n\nder Hausmeister. Er',
      );
    });

    testWidgets('Take again photographs the hard page again and reads it', (
      tester,
    ) async {
      final docs = FakeDocuments();
      final photos = FakePhotos(
        chosen: <String>['g1.jpg'],
        taken: <String>['again.jpg'],
        pages: <String, OcrPage>{
          'g1.jpg': page('Hausmelster', 0.2),
          'again.jpg': page('Der Hausmeister kommt.'),
        },
      );
      await pump(tester, docs: docs, photos: photos);
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.docImportTakeAgain));
      await tester.pumpAndSettle();

      expect(photos.readPaths, <String>['g1.jpg', 'again.jpg']);
      expect(docs.saved.single.body, 'Der Hausmeister kommt.');
      expect(docs.images[7], <String>['again.jpg']);
    });

    testWidgets('FR-D1-02 more than 30 images: the first 30 are read, and the '
        'learner told', (tester) async {
      final chosen = <String>[for (var i = 1; i <= 32; i++) 'g$i.jpg'];
      final photos = FakePhotos(
        chosen: chosen,
        pages: <String, OcrPage>{for (final c in chosen) c: page('Seite.')},
      );
      final docs = FakeDocuments();
      await pump(tester, docs: docs, photos: photos);
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pump();
      expect(
        find.text(l10n.docImportTooManyPages(docMaxPages)),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(photos.readPaths, hasLength(30));
      expect(docs.saved.single.pageCount, 30);
    });

    testWidgets('photos with no text say so, and nothing is saved', (
      tester,
    ) async {
      final docs = FakeDocuments();
      await pump(
        tester,
        docs: docs,
        photos: FakePhotos(
          chosen: <String>['dark.jpg'],
          pages: <String, OcrPage>{
            'dark.jpg': const OcrPage(<List<OcrWord>>[]),
          },
        ),
      );
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pumpAndSettle();
      expect(find.text(l10n.docImportNoText), findsOneWidget);
      expect(docs.saved, isEmpty);
    });

    testWidgets('FR-D1-05 Cancel while a photo is read saves nothing', (
      tester,
    ) async {
      final slow = Completer<OcrPage>();
      final docs = FakeDocuments();
      await pump(
        tester,
        docs: docs,
        photos: FakePhotos(chosen: <String>['g1.jpg'], pending: slow),
      );
      await tester.tap(find.text(l10n.docImportChooseImages));
      await tester.pump();
      expect(find.text(l10n.docImportReadingPage(1, 1)), findsOneWidget);
      await tester.tap(find.text(l10n.docImportCancel));
      await tester.pump();
      slow.complete(page('Die Miete.'));
      await tester.pumpAndSettle();
      expect(docs.saved, isEmpty);
      expect(find.text(l10n.docImportTakePhotos), findsOneWidget);
    });

    testWidgets('backing out of the camera before a photo stays on the '
        'choices', (tester) async {
      await pump(tester, docs: FakeDocuments(), photos: FakePhotos());
      await tester.tap(find.text(l10n.docImportTakePhotos));
      await tester.pumpAndSettle();
      expect(find.text(l10n.docImportTakePhotos), findsOneWidget);
      expect(find.text(l10n.docImportDone), findsNothing);
    });
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
  final List<({String title, String source, String body, int pageCount})>
  saved = <({String title, String source, String body, int pageCount})>[];

  /// The photos kept, by document.
  final Map<int, List<String>> images = <int, List<String>>{};

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
    saved.add((title: title, source: source, body: body, pageCount: pageCount));
    return 7;
  }

  @override
  Future<void> saveImages(
    int id,
    List<String> photos, {
    Directory? support,
  }) async => images[id] = photos;
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

/// The camera hands out [taken] in turn (null once they run out), the
/// gallery [chosen], and OCR reads each as [pages] says.
class FakePhotos implements PagePhotos {
  FakePhotos({
    List<String> taken = const <String>[],
    this.chosen = const <String>[],
    this.pages = const <String, OcrPage>{},
    this.pending,
  }) : _taken = <String>[...taken];

  final List<String> _taken;
  final List<String> chosen;
  final Map<String, OcrPage> pages;
  final Completer<OcrPage>? pending;

  /// The photos read, in order.
  final List<String> readPaths = <String>[];

  @override
  Future<String?> take() async => _taken.isEmpty ? null : _taken.removeAt(0);

  @override
  Future<List<String>> choose() async => chosen;

  @override
  Future<OcrPage> read(String path) async {
    readPaths.add(path);
    return pending?.future ?? pages[path] ?? const OcrPage(<List<OcrWord>>[]);
  }
}
