@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/content_update.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

  /// Builds a content.db with [version] and, optionally, an extra word, a
  /// changed Bangla meaning, a removed word, or any other [edit] (SQL) — the
  /// things a real update does. The manifest digests as the pipeline's does
  /// (`tools/content_manifest.py`): `words` over what the learner sees,
  /// `meanings` over the meanings only; [meanings] false writes a manifest
  /// from before it had them.
  ({Uint8List bytes, String manifest}) course({
    required String version,
    bool addWord = false,
    bool changeMeaning = false,
    bool removeWord = false,
    String? edit,
    bool meanings = true,
  }) {
    final path = '${support.path}/build-$version.db';
    ContentFixture.write(path);

    final database = sqlite3.open(path);
    final digests = <String, String>{};
    final meaningDigests = <String, String>{};
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
        // Bangla: `english` is in the uid (PIPE-03), so it cannot change in
        // place — a new English meaning is a new word.
        database.execute(
          "UPDATE words SET bangla = 'বাসা' "
          "WHERE uid = '${ContentFixture.haus}'",
        );
      }
      if (edit != null) database.execute(edit);
      if (removeWord) {
        database.execute(
          "DELETE FROM words WHERE uid = '${ContentFixture.tuer}'",
        );
      }

      // The manifest the pipeline would have written beside it: uid -> a
      // digest of what the learner sees.
      for (final row in database.select(
        'SELECT uid, german, english, bangla, freq, category_id, '
        "(SELECT group_concat(german, '|') FROM word_examples "
        'WHERE word_uid = uid) AS examples FROM words',
      )) {
        final uid = row['uid'] as String;
        digests[uid] =
            '${row['german']}|${row['english']}|${row['bangla']}|'
            '${row['freq']}|${row['category_id']}|${row['examples']}';
        meaningDigests[uid] = '${row['english']}|${row['bangla']}';
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
        if (meanings) 'meanings': meaningDigests,
      }),
    );
  }

  void publish(({Uint8List bytes, String manifest}) build) {
    assets = <String, Object>{
      ContentDao.asset: build.bytes,
      ContentUpdater.manifestAsset: build.manifest,
    };

    // `rootBundle` caches strings by key, and publishing a new course here is
    // pretending a new *app version* shipped — which in life means a new
    // process. Without the evict the second publish hands back the first
    // manifest, and the version read from it disagrees with the database in a
    // way that cannot happen on a device.
    rootBundle.evict(ContentDao.asset);
    rootBundle.evict(ContentUpdater.manifestAsset);
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

  test('an update with nothing to report is not shown', () async {
    // A first install is recorded as a change of nothing; Today must not
    // announce "0 added · 0 removed · 0 changed".
    await db.customStatement(
      "INSERT INTO content_updates (version, changed_json, seen) VALUES "
      "('202601011200', '{\"added\":[],\"removed\":[],\"changed\":[]}', 0)",
    );
    expect(await updater.unseen(), isNull);

    // And it does not hide a real one behind it.
    await db.customStatement(
      "INSERT INTO content_updates (version, changed_json, seen) VALUES "
      "('202512010000', '{\"added\":[\"x\"],\"removed\":[],\"changed\":[]}', 0)",
    );
    expect((await updater.unseen())?.version, '202512010000');
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
      expect(change.meaning, <String>[ContentFixture.haus]);
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
      expect(
        json.keys,
        containsAll(<String>['added', 'removed', 'changed', 'meaning']),
      );
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

  group('BR-CONTENT-02 the updated chip', () {
    test('names the words whose meaning moved', () async {
      publish(course(version: '202602020000', changeMeaning: true));
      await updater.runIfNeeded();

      expect(await updater.recentlyUpdated(DateTime.now().toUtc()), <String>{
        ContentFixture.haus,
      });
    });

    test('a freq re-rank, a category move or a new example is a change the '
        'card counts, not a new meaning', () async {
      var version = 202602020000;
      for (final edit in <String>[
        "UPDATE words SET freq = 9 WHERE uid = '${ContentFixture.haus}'",
        'UPDATE words SET category_id = NULL '
            "WHERE uid = '${ContentFixture.haus}'",
        'INSERT INTO word_examples (word_uid, ord, german, english) '
            "VALUES ('${ContentFixture.haus}', 3, 'Das Haus ist neu.', "
            "'The house is new.')",
      ]) {
        publish(course(version: '${version++}', edit: edit));
        final change = (await updater.runIfNeeded())!;
        expect(change.changed, <String>[ContentFixture.haus], reason: edit);
        expect(change.meaning, isEmpty, reason: edit);
      }
      expect(await updater.recentlyUpdated(DateTime.now()), isEmpty);
    });

    test(
      'a new English meaning is a new word (PIPE-03), with no chip',
      () async {
        publish(
          course(
            version: '202602020000',
            edit:
                "UPDATE words SET english = 'home', uid = 'uid-haus-home' "
                "WHERE uid = '${ContentFixture.haus}'",
          ),
        );
        final change = (await updater.runIfNeeded())!;
        expect(change.added, <String>['uid-haus-home']);
        expect(change.removed, <String>[ContentFixture.haus]);
        expect(change.meaning, isEmpty);
        expect(await updater.recentlyUpdated(DateTime.now()), isEmpty);
      },
    );

    test('a kept manifest from before `meanings` gives no chip, never a '
        'false one', () async {
      File('${support.path}/${ContentUpdater.manifestFile}').writeAsStringSync(
        course(version: '202601010000', meanings: false).manifest,
      );
      publish(course(version: '202602020000', changeMeaning: true));
      final change = (await updater.runIfNeeded())!;
      expect(change.changed, <String>[ContentFixture.haus]);
      expect(change.meaning, isEmpty);
    });

    test('the window is 168 h from when this device recorded it, the end '
        'included, in UTC', () async {
      publish(course(version: '202602020000', changeMeaning: true));
      await updater.runIfNeeded();
      final recorded = DateTime.utc(2026, 2, 10, 12);
      await db.customStatement(
        'UPDATE content_updates SET recorded_at = ?',
        <Object?>[recorded.toIso8601String()],
      );

      final end = recorded.add(const Duration(hours: 168));
      expect(await updater.recentlyUpdated(end), <String>{ContentFixture.haus});
      // The same instant on a local clock.
      expect(await updater.recentlyUpdated(end.toLocal()), <String>{
        ContentFixture.haus,
      });
      expect(
        await updater.recentlyUpdated(end.add(const Duration(milliseconds: 1))),
        isEmpty,
      );
    });

    test('it ages from when this device saw it, not from the build', () async {
      // `version` is the pipeline's build time and can be years old by the
      // time a learner installs the app. Ageing from it would mean they never
      // saw a chip at all.
      publish(course(version: '202001010000', changeMeaning: true));
      await updater.runIfNeeded();

      expect(
        await updater.recentlyUpdated(DateTime.now().toUtc()),
        isNotEmpty,
        reason: 'a 2020 build installed today is new to this learner',
      );
    });

    test('the window is the seven days the issue asks for', () {
      expect(ContentUpdater.updatedChipWindow, const Duration(days: 7));
    });

    test('recentlyUpdatedProvider asks at the clock time: in the window, '
        'then out of it', () async {
      publish(course(version: '202602020000', changeMeaning: true));
      await updater.runIfNeeded();

      final now = DateTime.now();
      Future<Set<String>> daysLater(int days) {
        final container = ProviderContainer(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(
              () => now.add(Duration(days: days)),
            ),
          ],
        );
        addTearDown(container.dispose);
        return container.read(recentlyUpdatedProvider.future);
      }

      expect(await daysLater(6), <String>{ContentFixture.haus});
      expect(await daysLater(8), isEmpty);
    });
  });

  group('an interrupted update', () {
    test('runs again on the next launch', () async {
      // The crash window: the file is swapped and the app dies before the row
      // is written. The kept manifest still describes the old version, which
      // is what makes the update re-runnable — comparing against the attached
      // database instead would have lost it for good.
      publish(course(version: '202602020000', addWord: true));
      await dao.replaceWithBundled();

      final change = await updater.runIfNeeded();
      expect(change, isNotNull, reason: 'the update was lost');
      expect(change!.added, <String>['uid-neu']);
    });

    test('does not bring back a card the learner dismissed', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();
      await updater.markSeen('202602020000');

      // Force a re-run of the same version, as an interrupted update would.
      File('${support.path}/${ContentUpdater.manifestFile}').deleteSync();
      await updater.runIfNeeded();

      expect(
        await updater.unseen(),
        isNull,
        reason: 'INSERT OR REPLACE would have reset seen',
      );
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

  group('FR-S1-02 — the version probe', () {
    test('reads the manifest, not the whole database', () async {
      // The probe used to copy the entire 8 MB asset to a temp file, attach
      // it, read one string and delete it — every launch, warm or cold. That
      // was the single largest thing between a warm start and the 500 ms
      // budget, and `splash.md` warns about it by name.
      //
      // Asserted by taking the database away: with only the manifest present
      // the version still comes back.
      final build = course(version: '202603030000');
      assets = <String, Object>{ContentUpdater.manifestAsset: build.manifest};
      rootBundle.evict(ContentDao.asset);
      rootBundle.evict(ContentUpdater.manifestAsset);

      expect(await dao.bundledVersion(), '202603030000');
    });

    test(
      'and falls back to the database when the manifest is unreadable',
      () async {
        // A corrupt manifest must not stop the app noticing a content update,
        // so the old path is still there.
        final build = course(version: '202604040000');
        assets = <String, Object>{
          ContentDao.asset: build.bytes,
          ContentUpdater.manifestAsset: 'not json at all',
        };
        rootBundle.evict(ContentDao.asset);
        rootBundle.evict(ContentUpdater.manifestAsset);

        expect(await dao.bundledVersion(), '202604040000');
      },
    );
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
