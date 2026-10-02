import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/features/documents/my_documents_screen.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart' show supportedLocales;

import '../features/my_documents_fixtures.dart';
import 'golden_harness.dart';

/// D3 · My documents (#1295): the MyDocuments and MyDocumentsEmpty artboards
/// (#1222), and FR-D3-02's confirm.
void main() {
  goldenTest(
    'my_documents',
    overrides: myDocumentsStub(),
    builder: (_) => const MyDocumentsScreen(),
  );

  goldenTest(
    'my_documents_empty',
    overrides: myDocumentsStub(FakeMyDocuments(const [])),
    builder: (_) => const MyDocumentsScreen(),
  );

  goldenTest(
    'my_documents_delete',
    textAudit: false,
    overrides: myDocumentsStub(),
    builder: (_) => const MyDocumentsScreen(),
    act: (tester) async {
      final l10n = await AppLocalizations.delegate.load(supportedLocales.first);
      await tester.tap(
        find.bySemanticsLabel(l10n.myDocumentsOptions('Mietvertrag')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.myDocumentsDelete));
      await tester.pumpAndSettle();
    },
  );
}
