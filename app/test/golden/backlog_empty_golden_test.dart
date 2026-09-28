// The ProviderScope below is the only one in the tree — the harness has none —
// so there is no parent scope for the lint's dependency list to describe.
// ignore_for_file: riverpod_lint/scoped_providers_should_specify_dependencies

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/backlog/backlog_screen.dart';

import 'golden_harness.dart';

/// T4 · Backlog empty — #109. The artboard: the tray with its Lime tick,
/// "Nothing waiting. Nice." and *Back to Today*.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUpAll(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });
  tearDownAll(() async {
    await settings.dispose();
    await db.close();
  });

  goldenTest(
    'backlog_empty',
    builder: (context) => ProviderScope(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        backlogProvider.overrideWith(_Empty.new),
      ],
      child: const BacklogScreen(),
    ),
  );
}

class _Empty extends Backlog {
  @override
  Stream<List<BacklogWord>> build() => Stream.value(const <BacklogWord>[]);
}
