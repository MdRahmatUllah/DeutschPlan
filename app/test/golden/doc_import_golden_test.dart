import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/domain/documents/ocr.dart';
import 'package:sogda/features/documents/doc_import_screen.dart';

import '../features/doc_import_test.dart'
    show FakeDocuments, FakePhotos, FakeShared;
import 'golden_harness.dart';

/// D1 · Learn from a document (#1227, #1229): the DocImport,
/// DocImportProcessing and DocImportCorrect artboards (PDFs are #1228's).
void main() {
  const letter =
      'Nebenkosten 2025\n\nSehr geehrte Frau Okafor,\n\nanbei erhalten Sie die '
      'Abrechnung der Betriebskosten für das Jahr 2025. Bitte überweisen Sie '
      'den Betrag bis zum 15. November.';

  /// The clipboard holds [letter].
  void clipboard(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.hasStrings' => <String, Object?>{'value': true},
          'Clipboard.getData' => <String, Object?>{'text': letter},
          _ => null,
        };
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  goldenTest('doc_import', builder: (_) => const DocImportScreen());

  goldenTest(
    'doc_import_paste',
    builder: (_) => const DocImportScreen(),
    act: (tester) async {
      clipboard(tester);
      await tester.tap(find.text(tester.l10n.docImportPaste));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    },
  );

  goldenTest(
    'doc_import_processing',
    textAudit: false,
    overrides: [
      documentRepositoryProvider.overrideWithValue(
        FakeDocuments(pending: Completer<double>()),
      ),
    ],
    builder: (_) => const DocImportScreen(),
    act: (tester) async {
      clipboard(tester);
      await tester.tap(find.text(tester.l10n.docImportPaste));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tester.l10n.docImportFind));
      await tester.pumpAndSettle();
    },
  );

  // #1386: photos shared, still being copied.
  goldenTest(
    'doc_import_receiving',
    overrides: [
      sharedTextProvider.overrideWithValue(
        FakeShared(null, coming: 34, copied: Completer<void>()),
      ),
    ],
    builder: (_) => const DocImportScreen(arrival: '1'),
  );

  goldenTest(
    'doc_import_camera',
    textAudit: false,
    overrides: [
      // A camera that never runs out: the harness shares one override
      // across its six goldens.
      pagePhotosProvider.overrideWithValue(_Camera()),
    ],
    builder: (_) => const DocImportScreen(),
    act: (tester) async {
      await tester.tap(find.text(tester.l10n.docImportTakePhotos));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tester.l10n.docImportAddPage));
      await tester.pumpAndSettle();
    },
  );

  // The DocImportCorrect artboard: photo 2's two unsure words.
  OcrWord w(String text, [double confidence = 0.72]) =>
      (text: text, confidence: confidence);
  goldenTest(
    'doc_import_check',
    overrides: [
      pagePhotosProvider.overrideWithValue(
        FakePhotos(
          chosen: <String>['p1.jpg', 'p2.jpg'],
          pages: <String, OcrPage>{
            'p1.jpg': OcrPage(<List<OcrWord>>[
              <OcrWord>[w('Hausverwaltung', 0.95), w('Becker', 0.95)],
            ]),
            'p2.jpg': OcrPage(<List<OcrWord>>[
              <OcrWord>[
                w('Am'),
                w('Dienstag'),
                w('kommt'),
                w('der'),
                w('Hausmelster.', 0.05),
                w('Er'),
                w('will'),
                w('die'),
              ],
              <OcrWord>[
                w('Heizkörper'),
                w('kontrollieren'),
                w('und'),
                w('den'),
                w('Wasserzahler', 0.05),
                w('ablesen.'),
                w('Bitte'),
                w('seien'),
                w('Sie'),
                w('zwischen'),
                w('9'),
                w('und'),
              ],
              <OcrWord>[w('12'), w('Uhr'), w('erreichbar.')],
            ]),
          },
        ),
      ),
    ],
    builder: (_) => const DocImportScreen(),
    act: (tester) async {
      await tester.tap(find.text(tester.l10n.docImportChooseImages));
      await tester.pumpAndSettle();
    },
  );
}

class _Camera extends FakePhotos {
  @override
  Future<String?> take() async => 'page.jpg';
}
