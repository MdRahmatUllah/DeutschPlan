@TestOn('vm')
library;

import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
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

    support = tempDir('sogda_install');
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
  });

  test('the first run copies the asset and attaches it', () async {
    expect((await dao.installedFile()).existsSync(), isFalse);

    expect(await dao.attach(), ContentFixture.version);
    expect((await dao.installedFile()).existsSync(), isTrue);
    expect(
      (await dao
          .customSelect("SELECT uid FROM words WHERE sublevel_code = 'A1.1'")
          .get()),
      hasLength(2),
    );
  });

  test('#804 a first-run copy cut short is copied again through .new, and '
      'none is left', () async {
    // What a first run killed mid-copy leaves: a partial `.new`, no course.
    final installed = await dao.installedFile();
    final partial = File('${installed.path}.new')
      ..writeAsBytesSync(assetBytes.sublist(0, assetBytes.length ~/ 3));

    expect(await dao.attach(), ContentFixture.version);
    expect(partial.existsSync(), isFalse);
    expect(ContentDao.readable(installed), isTrue);
  });

  test('#804 a first-run copy that fails leaves no .new behind', () async {
    // The rename fails: a folder stands where the course goes. The copy
    // landed in `.new`, and it goes.
    final installed = await dao.installedFile();
    Directory(installed.path).createSync(recursive: true);

    await expectLater(dao.attach(), throwsA(anything));
    expect(File('${installed.path}.new').existsSync(), isFalse);
  });

  test(
    '#885 a course without a column this build reads does not fit it',
    () async {
      await dao.attach();
      expect(await dao.fitsBuild(), isTrue);
      await dao.detach();

      sqlite3.open((await dao.installedFile()).path)
        ..execute('ALTER TABLE words DROP COLUMN kind')
        ..close();
      await dao.attach();
      expect(await dao.fitsBuild(), isFalse);
    },
  );

  test('#885 fitsBuild checks every table content_schema.drift declares', () {
    final declared = <String>{
      for (final match in RegExp(
        r'^CREATE (?:VIRTUAL )?TABLE (\w+)',
        multiLine: true,
      ).allMatches(File('lib/data/db/content_schema.drift').readAsStringSync()))
        match.group(1)!,
    };
    expect(declared, hasLength(greaterThan(10)));
    expect(<String>{
      for (final table in dao.courseTables) table.actualTableName,
    }, declared);
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
      expect(
        await dao
            .customSelect("SELECT uid FROM words WHERE sublevel_code = 'A1.1'")
            .get(),
        hasLength(2),
      );
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
        await dao
            .customSelect("SELECT uid FROM words WHERE sublevel_code = 'A1.1'")
            .get(),
        hasLength(2),
        reason: 'the course was detached and never came back',
      );
    });

    test('#617 and a failed copy leaves no partial file behind', () async {
      await dao.attach();
      // What a copy cut short, on a full disk, would have left.
      final incoming = File('${(await dao.installedFile()).path}.new')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (_) async => null);

      await expectLater(dao.replaceWithBundled(), throwsA(anything));
      expect(incoming.existsSync(), isFalse);
    });
  });

  group('#617 whether a course reads', () {
    test('an installed one does', () async {
      await dao.attach();
      expect(ContentDao.readable(await dao.installedFile()), isTrue);
    });

    test('a missing, truncated or foreign file does not', () {
      final file = File('${support.path}/other.db');
      expect(ContentDao.readable(file), isFalse, reason: 'missing');

      file.writeAsBytesSync(assetBytes.sublist(0, assetBytes.length ~/ 3));
      expect(ContentDao.readable(file), isFalse, reason: 'truncated');

      file.deleteSync();
      sqlite3.open(file.path)
        ..execute('CREATE TABLE t (x)')
        ..close();
      expect(ContentDao.readable(file), isFalse, reason: 'no meta');
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
