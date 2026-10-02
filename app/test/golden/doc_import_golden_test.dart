import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/features/documents/doc_import_screen.dart';

import '../features/doc_import_test.dart' show FakeDocuments;
import 'golden_harness.dart';

/// D1 · Learn from a document (#1227): the DocImport and DocImportProcessing
/// artboards, with text's way in (photos and PDFs are #1228 and #1229).
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
    textAudit: false,
    builder: (_) => const DocImportScreen(),
    act: (tester) async {
      clipboard(tester);
      await tester.tap(find.text('Paste text'));
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
      await tester.tap(find.text('Paste text'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find my words'));
      await tester.pumpAndSettle();
    },
  );
}
