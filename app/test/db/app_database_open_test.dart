@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// `AppDatabase.open()` is the constructor that ships, and it is the one with
/// the parts that cannot fail in a unit test elsewhere: the storage directory,
/// the background isolate, and `configureConnection` being handed across the
/// isolate boundary.
///
/// That last one is why `configureConnection` is a top-level function. A
/// closure or an instance method would not survive the trip, and the failure
/// would be a database opened without WAL and without foreign keys — silent,
/// on a device. One assertion on `journal_mode` covers all three, because the
/// pragma can only be `wal` if the file was reached, the isolate started, and
/// the callback ran there.
void main() {
  late Directory storage;
  late Directory documents;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    storage = Directory.systemTemp.createTempSync('sogda_support');
    // A different directory, or the assertion below that the file landed in
    // app-support rather than documents would pass either way.
    documents = Directory.systemTemp.createTempSync('sogda_documents');
    PathProviderPlatform.instance = _TempPathProvider(
      support: storage.path,
      documents: documents.path,
    );
  });

  tearDown(() {
    // On Windows the drift isolate releases the file a moment after close(),
    // so a failed delete here is housekeeping, not a test result. The OS
    // clears its own temp directory.
    for (final dir in <Directory>[storage, documents]) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the OS.
      }
    }
  });

  test('opens in app-support storage, on an isolate, configured', () async {
    final db = AppDatabase.open(name: 'user_test');

    final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
    expect(mode.read<String>('journal_mode'), 'wal');

    final keys = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(keys.read<int>('foreign_keys'), 1);

    // The schema was created, so the include and the migration ran too.
    expect(await db.fileSchemaVersion(), db.schemaVersion);

    await db.close();

    expect(
      File('${storage.path}/user_test.sqlite').existsSync(),
      isTrue,
      reason:
          'drift defaults to the documents directory; user.db is ours, not '
          'something the learner browses',
    );
    expect(File('${documents.path}/user_test.sqlite').existsSync(), isFalse);
  });

  test('#621 an app transaction that reads, then writes, survives the '
      'background connection committing in between', () async {
    // `DriftPlanStore.atomically`'s claim: drift's native transactions are
    // BEGIN IMMEDIATE, so the app's holds the write lock from its first
    // read, and the background write (#158) waits under busy_timeout. A
    // deferred BEGIN would let it commit under the app's read snapshot, and
    // the app's write would fail with SQLITE_BUSY_SNAPSHOT.
    final app = AppDatabase.open(name: 'user_test');
    final background = AppDatabase.open(name: 'user_test', shared: false);
    Future<void> put(AppDatabase db, String key) => db.customStatement(
      "INSERT INTO settings (\"key\", value) VALUES ('$key', '1')",
    );
    Future<int> rows(AppDatabase db) async =>
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM settings')
                .getSingle())
            .read<int>('n');
    final before = await rows(app);
    await rows(background); // both connections open and migrated

    late Future<void> backgroundWrite;
    await app.transaction(() async {
      await rows(app);
      backgroundWrite = background.transaction(() => put(background, 'bg'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await put(app, 'app');
    });
    await backgroundWrite;

    expect(await rows(app), before + 2);
    await background.close();
    await app.close();
  });
}

/// Points `getApplicationSupportDirectory()` at a temp directory.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider({required this.support, required this.documents});

  final String support;
  final String documents;

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getTemporaryPath() async => support;
}
