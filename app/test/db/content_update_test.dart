@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/content_update.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'content_fixture.dart';

/// `content-database.md`, "Update flow": probe the bundled version, replace
/// the installed file, diff against the manifest kept from the previous
/// version, and record the result for Today's card.
///
/// The asset bundle is mocked, so the whole path runs against real files.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory support;
  late AppDatabase db;
  late ContentDao dao;
  late ContentUpdater updater;

  /// The bytes each asset currently serves.
  late Map<String, Object> assets;

  void serveAssets() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final key = const StringCodec().decodeMessage(message);
          final value = assets[key];
          if (value == null) return null;
          if (value is String) {
            return ByteData.view(Uint8List.fromList(utf8.encode(value)).buffer);
          }
          return ByteData.view((value as Uint8List).buffer);
        });
  }

  /// Builds a content.db with [version] and, optionally, an extra word and a
  /// changed meaning — the two things a real update does.
  ({Uint8List bytes, String manifest}) course({
    required String version,
    bool addWord = false,
    bool changeMeaning = false,
    bool removeWord = false,
  }) {
    final path = '${support.path}/build-$version.db';
    ContentFixture.write(path);

    final database = sqlite3.open(path);
    final digests = <String, String>{};
    try {
      database.execute(
        "UPDATE meta SET value = '$version' WHERE \"key\" = 'content_version'",
      );
      if (addWord) {
        database.execute(
          "INSERT INTO words (uid, sublevel_code, level_code, seq, "
          "seq_in_sublevel, german, english, search_key, search_key_alt) "
          "VALUES ('uid-neu', 'A1.2', 'A1', 4, 2, 'Neu', 'new', 'neu', 'neu')",
        );
      }
      if (changeMeaning) {
        database.execute(
          "UPDATE words SET english = 'dwelling' "
          "WHERE uid = '${ContentFixture.haus}'",
        );
      }
      if (removeWord) {
        database.execute(
          "DELETE FROM words WHERE uid = '${ContentFixture.tuer}'",
        );
      }

      // The manifest the pipeline would have written beside it: uid -> a
      // digest of what the learner sees.
      for (final row in database.select(
        'SELECT uid, german, english FROM words',
      )) {
        digests[row['uid'] as String] = '${row['german']}|${row['english']}';
      }
    } finally {
      database.close();
    }

    final bytes = File(path).readAsBytesSync();
    File(path).deleteSync();
    return (
      bytes: bytes,
      manifest: jsonEncode(<String, Object>{
        'format': 1,
        'content_version': version,
        'words': digests,
      }),
    );
  }

  void publish(({Uint8List bytes, String manifest}) build) {
    assets = <String, Object>{
      ContentDao.asset: build.bytes,
      ContentUpdater.manifestAsset: build.manifest,
    };
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    support = Directory.systemTemp.createTempSync('deutschplan_update');
    PathProviderPlatform.instance = _TempPaths(support.path);

    publish(course(version: '202601010000'));
    serveAssets();

    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    dao = ContentDao(db);
    updater = ContentUpdater(db, dao);

    // First launch: install and keep the manifest as the baseline.
    await dao.attach();
    File('${support.path}/${ContentUpdater.manifestFile}')
        .writeAsStringSync(assets[ContentUpdater.manifestAsset]! as String);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await db.close();
    try {
      support.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows releases it a moment later.
    }
  });

  test('an unchanged asset is not an update', () async {
    expect(await updater.runIfNeeded(), isNull);
    expect(await updater.unseen(), isNull);
  });

  group('when the bundled course is newer', () {
    test('it installs and reports what changed', () async {
      publish(
        course(
          version: '202602020000',
          addWord: true,
          changeMeaning: true,
          removeWord: true,
        ),
      );

      final change = await updater.runIfNeeded();

      expect(change, isNotNull);
      expect(change!.version, '202602020000');
      expect(change.added, <String>['uid-neu']);
      expect(change.removed, <String>[ContentFixture.tuer]);
      expect(change.changed, <String>[ContentFixture.haus]);
    });

    test('the installed course is the new one', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();

      expect(await dao.version(), '202602020000');
      expect(await dao.wordsForStep('A1.2').get(), hasLength(2));
    });

    test('the row Today reads is written with seen = 0', () async {
      publish(course(version: '202602020000', addWord: true, removeWord: true));
      await updater.runIfNeeded();

      final row = await db
          .customSelect('SELECT * FROM content_updates')
          .getSingle();
      expect(row.read<String>('version'), '202602020000');
      expect(row.read<int>('added'), 1);
      expect(row.read<int>('removed'), 1);
      expect(row.read<int>('seen'), 0);

      final json =
          jsonDecode(row.read<String>('changed_json')) as Map<String, dynamic>;
      expect(json.keys, containsAll(<String>['added', 'removed', 'changed']));
    });

    test('the manifest is kept as the next baseline', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();

      // A second run against the same asset must report nothing — which only
      // works if the manifest was replaced.
      expect(await updater.runIfNeeded(), isNull);
    });
  });

  group('the card Today shows', () {
    test('is the newest unseen update', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();

      final unseen = await updater.unseen();
      expect(unseen, isNotNull);
      expect(unseen!.added, <String>['uid-neu']);
    });

    test('goes away once it is dismissed', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();

      await updater.markSeen('202602020000');
      expect(await updater.unseen(), isNull);
    });
  });

  group('the updated chip', () {
    test('names the words whose meaning moved', () async {
      publish(course(version: '202602020000', changeMeaning: true));
      await updater.runIfNeeded();

      final recent = await updater.recentlyUpdated(DateTime.utc(2026, 2, 2, 1));
      expect(recent, <String>{ContentFixture.haus});
    });

    test('stops after seven days', () async {
      publish(course(version: '202602020000', changeMeaning: true));
      await updater.runIfNeeded();

      // Six days later it is still there; eight days later it is not.
      expect(
        await updater.recentlyUpdated(DateTime.utc(2026, 2, 8)),
        isNotEmpty,
      );
      expect(await updater.recentlyUpdated(DateTime.utc(2026, 2, 10)), isEmpty);
    });

    test('the window is the seven days the issue asks for', () {
      expect(ContentUpdater.updatedChipWindow, const Duration(days: 7));
    });
  });

  test('a removed word keeps its word_state and stops appearing', () async {
    // Step 4 of the update flow. The learner's progress is not deleted — the
    // word simply stops being joined to, so nothing on screen refers to it.
    await db.customStatement(
      "INSERT INTO word_state (word_uid, status) "
      "VALUES ('${ContentFixture.tuer}', 'learning')",
    );

    publish(course(version: '202602020000', removeWord: true));
    await updater.runIfNeeded();

    final kept = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM word_state "
          "WHERE word_uid = '${ContentFixture.tuer}'",
        )
        .getSingle();
    expect(kept.read<int>('n'), 1, reason: 'progress must survive an update');

    final joined = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM word_state s JOIN words w '
          'ON w.uid = s.word_uid',
        )
        .getSingle();
    expect(joined.read<int>('n'), 0, reason: 'but the word is gone from view');
  });

  test(
    'an unreadable manifest reports nothing rather than everything',
    () async {
      // Reporting every word as added would tell the learner their whole course
      // had been replaced.
      File('${support.path}/${ContentUpdater.manifestFile}')
          .writeAsStringSync('not json');

      publish(course(version: '202602020000', addWord: true));
      final change = await updater.runIfNeeded();

      expect(change, isNotNull);
      expect(change!.isEmpty, isTrue);
    },
  );
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
