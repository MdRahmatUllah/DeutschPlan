@TestOn('vm')
library;

import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'content_fixture.dart';

/// Installing the course: copy the asset, attach it, replace it on update.
///
/// The asset bundle is mocked so the real path runs — `rootBundle.load`, a
/// file on disk, and an ATTACH against it. The failure modes worth testing
/// here are the ones that leave the connection in a state the app cannot
/// recover from without a restart.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory support;
  late AppDatabase db;
  late ContentDao dao;
  late Uint8List assetBytes;

  /// Serves [assetBytes] for `assets/db/content.db`, and nothing else.
  void mockAsset() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final key = const StringCodec().decodeMessage(message);
          if (key == ContentDao.asset) {
            return ByteData.view(assetBytes.buffer);
          }
          return null;
        });
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    support = Directory.systemTemp.createTempSync('deutschplan_install');
    PathProviderPlatform.instance = _TempPaths(support.path);

    // A real content.db, read back as bytes — the same thing the bundle would
    // hand over.
    final built = ContentFixture.write('${support.path}/asset.db').file;
    assetBytes = built.readAsBytesSync();
    built.deleteSync();

    mockAsset();

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    dao = ContentDao(db);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await db.close();
    try {
      support.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases the file a moment later.
    }
  });

  test('the first run copies the asset and attaches it', () async {
    expect((await dao.installedFile()).existsSync(), isFalse);

    expect(await dao.attach(), ContentFixture.version);
    expect((await dao.installedFile()).existsSync(), isTrue);
    expect((await dao.wordsForStep('A1.1').get()), hasLength(2));
  });

  test('a second run reuses the installed copy', () async {
    await dao.attach();
    await dao.detach();

    // Take the asset away: a second attach must not need it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);

    expect(await dao.attach(), ContentFixture.version);
  });

  test('the bundled version can be probed without installing it', () async {
    expect(await dao.bundledVersion(), ContentFixture.version);
    expect(
      (await dao.installedFile()).existsSync(),
      isFalse,
      reason: 'probing must not install anything',
    );
  });

  test('a failed probe does not leave the schema attached', () async {
    // The failure this guards is precise: the file has to be a *valid*
    // database that the SELECT then fails on. A truncated one throws at the
    // ATTACH, which leaves nothing attached and proves nothing. An empty but
    // well-formed database attaches and has no `meta` table — and if the
    // probe stayed attached, every later call would fail with "database probe
    // is already in use" and the app would stop noticing content updates for
    // the rest of the session.
    final empty = File('${support.path}/empty.db');
    sqlite3.open(empty.path)
      ..execute('CREATE TABLE placeholder (x INTEGER)')
      ..close();
    assetBytes = empty.readAsBytesSync();

    await expectLater(dao.bundledVersion(), throwsA(anything));

    // The real asset again — the next probe has to work.
    assetBytes = ContentFixture.write('${support.path}/again.db').file
        .readAsBytesSync();
    expect(await dao.bundledVersion(), ContentFixture.version);
  });

  group('replacing the installed copy', () {
    test('the course is readable afterwards', () async {
      await dao.attach();
      await dao.replaceWithBundled();
      expect(await dao.wordsForStep('A1.1').get(), hasLength(2));
    });

    test('it leaves no half-written file behind', () async {
      await dao.attach();
      await dao.replaceWithBundled();

      final leftovers = support.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.new'),
      );
      expect(leftovers, isEmpty);
    });

    test('a failed copy leaves the old course attached and readable', () async {
      await dao.attach();

      // The asset disappears mid-update. The old copy must survive: stale
      // content is a better failure than a screen that errors until restart.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (_) async => null);

      await expectLater(dao.replaceWithBundled(), throwsA(anything));

      expect(
        await dao.wordsForStep('A1.1').get(),
        hasLength(2),
        reason: 'the course was detached and never came back',
      );
    });
  });
}

class _TempPaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
