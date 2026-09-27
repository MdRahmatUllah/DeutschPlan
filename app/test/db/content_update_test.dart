@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/db/content_update.dart';
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

  /// Every asset asked for, in order (#710).
  final requested = <String?>[];

  void serveAssets() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
          final key = const StringCodec().decodeMessage(message);
          requested.add(key);
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
    Map<String, String> aliases = const <String, String>{},
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
          "seq_in_sublevel, german, english, search_key, search_key_alt, kind) "
          "VALUES ('uid-neu', 'A1.2', 'A1', 4, 2, 'Neu', 'new', 'neu', 'neu', "
          "'vocab')",
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
        'aliases': aliases,
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
    support = Directory.systemTemp.createTempSync('sogda_update');
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

  test('#710 a launch with no update reads the two versions without '
      'decoding the manifests', () async {
    // Past their version both manifests are garbage: a launch that decoded
    // either would fall back to the 8 MB probe, or install again.
    const head = '{"format": 1, "content_version": "202601010000", ';
    final garbage = head + 'x' * 8192;
    File('${support.path}/${ContentUpdater.manifestFile}')
        .writeAsStringSync(garbage);
    assets[ContentUpdater.manifestAsset] = garbage;
    rootBundle.evict(ContentUpdater.manifestAsset);
    requested.clear();

    expect(await updater.runIfNeeded(), isNull);
    expect(requested, isNot(contains(ContentDao.asset)));
  });

  test('#710 #648 the version is found however far the aliases push it', () {
    // `aliases` sorts before `content_version` and only grows.
    final text = jsonEncode(<String, Object>{
      'aliases': <String, String>{
        for (var i = 0; i < 400; i++) 'old-uid-$i': 'new-uid-$i',
      },
      'content_version': '202609271200',
    });
    expect(text.length, greaterThan(8192));
    expect(ContentUpdater.versionIn(utf8.encode(text)), '202609271200');
  });

  test('#710 the shipped manifest\'s version is found without a decode', () {
    final bytes = File('assets/db/content_manifest.json').readAsBytesSync();
    final version = (jsonDecode(
      utf8.decode(bytes),
    ) as Map<String, dynamic>)['content_version'];

    expect(ContentUpdater.versionIn(bytes), version);
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
      expect(
        await dao
            .customSelect("SELECT uid FROM words WHERE sublevel_code = 'A1.2'")
            .get(),
        hasLength(2),
      );
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

    test('#477 BR-CONTENT-03 two updates before a dismiss: one card, the '
        'newest, and dismissing it clears both', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();
      publish(course(version: '202603030000', removeWord: true));
      await updater.runIfNeeded();

      final shown = await updater.unseen();
      expect(shown!.version, '202603030000');
      await updater.markSeen(shown.version);
      expect(
        await updater.unseen(),
        isNull,
        reason: "the older update's card doesn't come back",
      );
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

  test('#617 a newer course whose copy fails keeps the old one, records '
      'nothing, and installs on the next launch', () async {
    final newer = course(version: '202602020000', addWord: true);
    // The manifest ships but the database never lands, as on a full disk.
    assets = <String, Object>{ContentUpdater.manifestAsset: newer.manifest};
    rootBundle.evict(ContentDao.asset);
    rootBundle.evict(ContentUpdater.manifestAsset);
    final kept = File('${support.path}/${ContentUpdater.manifestFile}');
    final before = kept.readAsStringSync();

    expect(await updater.runIfNeeded(), isNull);
    expect(await dao.version(), '202601010000', reason: 'the old course');
    expect(
      await db.customSelect('SELECT * FROM content_updates').get(),
      isEmpty,
    );
    expect(
      kept.readAsStringSync(),
      before,
      reason: 'so the next launch retries',
    );
    expect(
      support.listSync().where((file) => file.path.endsWith('.new')),
      isEmpty,
    );

    // The next launch, with the space back.
    publish(newer);
    expect((await updater.runIfNeeded())?.version, '202602020000');
    expect(await dao.version(), '202602020000');
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

    test('#621 a re-run with no baseline keeps the diff it recorded', () async {
      publish(course(version: '202602020000', addWord: true));
      await updater.runIfNeeded();

      // A reset course or a truncated kept manifest: the re-run has nothing
      // to diff against and records a change of nothing.
      File('${support.path}/${ContentUpdater.manifestFile}').deleteSync();
      expect((await updater.runIfNeeded())!.isEmpty, isTrue);

      final card = await updater.unseen();
      expect(card?.added, <String>['uid-neu'], reason: 'the card was wiped');
      final row = await db
          .customSelect('SELECT added FROM content_updates')
          .getSingle();
      expect(row.read<int>('added'), 1);
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

  group('#648 PIPE-09 a word whose uid changed', () {
    const home = 'uid-haus-home';

    /// The gloss fix of the issue: the same Haus, a new English, a new uid,
    /// and the manifest's alias from the old one.
    ({Uint8List bytes, String manifest}) glossFixed() => course(
      version: '202602020000',
      edit:
          "UPDATE words SET english = 'home', uid = '$home' "
          "WHERE uid = '${ContentFixture.haus}'",
      aliases: <String, String>{ContentFixture.haus: home},
    );

    Future<int> count(String table, String column, String uid) async =>
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM $table WHERE $column = ?',
                  variables: <Variable<Object>>[Variable<String>(uid)],
                )
                .getSingle())
            .read<int>('n');

    Future<void> learnHaus() async {
      final haus = ContentFixture.haus;
      await db.customStatement(
        "INSERT INTO word_state (word_uid, status, reps) "
        "VALUES ('$haus', 'learning', 7)",
      );
      await db.customStatement(
        'INSERT INTO review_log (word_uid, reviewed_at, rating, source) '
        "VALUES ('$haus', '2026-01-02T08:00:00Z', 3, 'daily')",
      );
      await db.customStatement(
        'INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) '
        "VALUES ('2026-01-02', '$haus', 'new', 'A1.1')",
      );
      await db.customStatement(
        'INSERT INTO sentence_log (word_uid, ord, shown_on) '
        "VALUES ('$haus', 1, '2026-01-02')",
      );
      await db.customStatement(
        'INSERT INTO quiz_attempts (id, started_at, direction, source, seed, '
        "length) VALUES (1, '2026-01-02T08:00:00Z', 'deToEn', 'step', 1, 1)",
      );
      await db.customStatement(
        'INSERT INTO quiz_answers (attempt_id, ord, word_uid, prompt, '
        "expected) VALUES (1, 1, '$haus', 'Haus', 'house')",
      );
      await db.customStatement(
        'INSERT INTO exam_attempts (id, sublevel_code, seed, started_at) '
        "VALUES (1, 'A1.1', 1, '2026-01-02T08:00:00Z')",
      );
      await db.customStatement(
        'INSERT INTO exam_answers (attempt_id, ord, section, item_ref, prompt) '
        "VALUES (1, 1, 'meaning', '$haus', '{}'), "
        "(1, 2, 'grammar', 'uid-topic#1', '{}')",
      );
      await db.customStatement(
        'INSERT INTO custom_words (created_at, german, meaning, matched_uid) '
        "VALUES ('2026-01-02T08:00:00Z', 'Haus', 'house', '$haus')",
      );
    }

    test('keeps every row the learner has under the old uid', () async {
      await learnHaus();
      publish(glossFixed());
      await updater.runIfNeeded();

      for (final (table, column) in ContentUpdater.aliasedColumns) {
        expect(
          await count(table, column, ContentFixture.haus),
          0,
          reason: '$table.$column still under the old uid',
        );
        expect(await count(table, column, home), 1, reason: '$table.$column');
      }
      final state = await db
          .customSelect("SELECT reps FROM word_state WHERE word_uid = '$home'")
          .getSingle();
      expect(state.read<int>('reps'), 7, reason: 'the progress itself moved');
      expect(
        await count('exam_answers', 'item_ref', home),
        1,
        reason:
            "an exam's word ref moved, so the next paper does not repeat it",
      );
      expect(
        await count('exam_answers', 'item_ref', 'uid-topic#1'),
        1,
        reason: 'a grammar ref is not a word uid',
      );
    });

    test('is reported as changed with a new meaning, not removed and '
        'added', () async {
      publish(glossFixed());
      final change = (await updater.runIfNeeded())!;

      expect(change.added, isEmpty);
      expect(change.removed, isEmpty);
      expect(change.changed, <String>[home]);
      expect(change.meaning, <String>[home]);
    });

    test(
      'a row already under the new uid wins, and the old one is kept',
      () async {
        await db.customStatement(
          'INSERT INTO word_state (word_uid, status, reps) VALUES '
          "('${ContentFixture.haus}', 'learning', 7), ('$home', 'todo', 1)",
        );
        publish(glossFixed());
        await updater.runIfNeeded();

        expect(await count('word_state', 'word_uid', ContentFixture.haus), 1);
        final state = await db
            .customSelect(
              "SELECT reps FROM word_state WHERE word_uid = '$home'",
            )
            .getSingle();
        expect(state.read<int>('reps'), 1);
      },
    );

    test('a move that fails moves nothing, and the next launch moves it '
        'all', () async {
      await learnHaus();
      // The last table in the list fails, after the others have moved.
      await db.customStatement(
        'CREATE TRIGGER fail_move BEFORE UPDATE OF matched_uid ON custom_words '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );
      publish(glossFixed());
      await expectLater(updater.runIfNeeded(), throwsA(anything));

      for (final (table, column) in ContentUpdater.aliasedColumns) {
        expect(
          await count(table, column, ContentFixture.haus),
          1,
          reason: '$table.$column rolled back',
        );
        expect(await count(table, column, home), 0, reason: '$table.$column');
      }
      expect(await count('content_updates', 'version', '202602020000'), 0);

      await db.customStatement('DROP TRIGGER fail_move');
      await updater.runIfNeeded();
      for (final (table, column) in ContentUpdater.aliasedColumns) {
        expect(await count(table, column, home), 1, reason: '$table.$column');
      }
    });

    test('every user.db column named for a word uid is moved', () async {
      // A table added later with a word_uid column, and left out of the
      // list, would lose its rows on the next gloss fix.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final found = <(String, String)>{};
      for (final table in tables) {
        final name = table.read<String>('name');
        for (final column
            in await db.customSelect('PRAGMA table_info("$name")').get()) {
          final columnName = column.read<String>('name');
          if (columnName == 'word_uid' || columnName == 'matched_uid') {
            found.add((name, columnName));
          }
        }
      }
      expect(found, isNotEmpty);
      expect(ContentUpdater.aliasedColumns.toSet(), containsAll(found));
    });
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
