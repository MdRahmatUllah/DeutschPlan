// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/features/me/export_import_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/export_import_test.dart' show FakeBackupFiles;
import '../features/settings_fixtures.dart';
import 'golden_harness.dart';

/// The ExportImport artboard's file: 2,104 word states, last active on
/// 20 September, in A2.1; and what else it holds (#396).
class _ArtboardBackups extends Fake implements BackupRepository {
  @override
  BackupPreview preview(String json) => const BackupPreview(
    schemaVersion: 2,
    contentVersion: null,
    exportedAt: '2026-09-20T12:00:00Z',
    rowCounts: <String, int>{
      'word_state': 2104,
      'review_log': 5321,
      'custom_words': 3,
    },
    wordStates: 2104,
    lastActive: '2026-09-20T09:00:00Z',
    activeStep: 'A2.1',
    planDays: 30,
  );
}

/// M6 · Export / import — #148. The artboard: a 1.8 MB export never taken,
/// and deutschplan-2026-09-20.json chosen, with Merge.
void main() {
  Widget screen(BuildContext context) => ProviderScope(
    overrides: <Override>[
      settingsProvider.overrideWithValue(StubSettings()),
      exportSizeProvider.overrideWith((ref) async => 1887437),
      backupRepositoryProvider.overrideWithValue(_ArtboardBackups()),
      backupFilesProvider.overrideWithValue(
        FakeBackupFiles()
          ..picked = (name: 'deutschplan-2026-09-20.json', json: '{}'),
      ),
    ],
    child: const ExportImportScreen(),
  );

  Future<void> chosen(WidgetTester tester) =>
      tester.tap(find.text('Choose a file'));

  goldenTest('export_import', builder: screen, act: chosen);
  goldenTest(
    'export_import_ios',
    modes: const <GoldenMode>[GoldenMode.light],
    devices: const <GoldenDevice>[GoldenDevice.phone],
    chrome: AdaptiveChrome.cupertino,
    builder: screen,
    act: chosen,
  );
}
