import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/main.dart' show deleteOldDocuments;

class _Documents extends DocumentRepository {
  _Documents(AppDatabase db) : super(db, () => DateTime(2026, 10, 2));

  final List<int> asked = <int>[];

  @override
  Future<int> deleteOlderThan(int days, {Directory? support}) async {
    asked.add(days);
    return 0;
  }
}

/// #1296 FR-D3-03: what main runs at launch for documents.
void main() {
  test('#1296 FR-D3-03 at launch, documents older than M3\'s *Delete '
      'documents after* are deleted', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    final documents = _Documents(db);
    final container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWithValue(settings),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
    addTearDown(container.dispose);

    await deleteOldDocuments(container);
    await settings.write(SettingKeys.docAutodeleteDays, 90);
    await deleteOldDocuments(container);
    expect(documents.asked, <int>[0, 90], reason: 'never by default');
  });
}
