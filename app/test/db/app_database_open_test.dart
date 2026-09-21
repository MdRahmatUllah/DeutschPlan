@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
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
    storage = Directory.systemTemp.createTempSync('deutschplan_support');
    // A different directory, or the assertion below that the file landed in
    // app-support rather than documents would pass either way.
    documents = Directory.systemTemp.createTempSync('deutschplan_documents');
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
