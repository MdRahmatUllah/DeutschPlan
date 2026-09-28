import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';

/// What one content update changed.
///
/// The counts go into `content_updates.added` / `.removed`; the uid lists go
/// into `changed_json`, because Today's card counts words and W1 and T2's
/// back show an *Updated* chip for the ones whose meaning moved.
@immutable
class ContentChange {
  const ContentChange({
    required this.version,
    required this.added,
    required this.removed,
    required this.changed,
    this.meaning = const <String>[],
  });

  const ContentChange.none(this.version)
    : added = const <String>[],
      removed = const <String>[],
      changed = const <String>[],
      meaning = const <String>[];

  final String version;
  final List<String> added;
  final List<String> removed;

  /// Every word whose manifest digest moved: Today's card counts these.
  final List<String> changed;

  /// The [changed] words whose *meaning* moved (the manifest's `meanings`
  /// digests): only these wear BR-CONTENT-02's chip. A freq re-rank or a new
  /// example is a change, not a new meaning.
  final List<String> meaning;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// The shape `content_updates.changed_json` stores.
  String toJson() => jsonEncode(<String, List<String>>{
    'added': added,
    'removed': removed,
    'changed': changed,
    'meaning': meaning,
  });

  static ContentChange fromJson(String version, String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    List<String> list(String key) =>
        ((map[key] as List<dynamic>?) ?? const <dynamic>[]).cast<String>();
    return ContentChange(
      version: version,
      added: list('added'),
      removed: list('removed'),
      changed: list('changed'),
      meaning: list('meaning'),
    );
  }
}

/// Installs a new course when the bundled asset is newer than the installed
/// copy, and records what changed.
///
/// `docs/02-data/content-database.md`, "Update flow". The four steps there are
/// the four things this does, in that order — and the order matters: the diff
/// is computed against the manifest kept from the *previous* version, which
/// the install then overwrites.
class ContentUpdater {
  ContentUpdater(this._db, this._dao);

  final AppDatabase _db;
  final ContentDao _dao;

  /// The manifest the pipeline ships beside the database.
  static const String manifestAsset = 'assets/db/content_manifest.json';

  /// The copy kept in app support, describing the version currently installed.
  static const String manifestFile = 'content_manifest.json';

  /// How long a changed word wears its *updated* chip.
  ///
  /// The issue asks for seven days. It is a property of the update, not of the
  /// word, so it is measured from when the update was recorded rather than
  /// stored per word — which would mean five thousand rows to age out.
  static const Duration updatedChipWindow = Duration(days: 7);

  /// Runs the update if there is one. Returns what changed, or `null` when the
  /// installed course is already current.
  ///
  /// Called from `bootstrap()` (#66), before `runApp`, because a course that
  /// changes under a running screen is worse than a slightly longer launch.
  ///
  /// [onCopy] hears that the copy is about to start: the splash's caption
  /// for an update (#686 ST-9).
  Future<ContentChange?> runIfNeeded({void Function()? onCopy}) async {
    // The kept manifest is the baseline, not the attached database. If the app
    // is killed between the file swap and the record — a launch, the most
    // likely moment — the database already reads as current while no
    // `content_updates` row exists and the kept manifest still describes the
    // old version. Comparing against the manifest makes the whole thing
    // re-runnable: the next launch simply does it again, and
    // `replaceWithBundled` is idempotent.
    //
    // #710: the versions are read with a regex, not a JSON decode. Each
    // manifest is half a megabyte, decoded in full only when there is a diff
    // to take.
    final installed = await _installedVersion();

    final bundled = await _dao.bundledVersion();
    if (bundled.isEmpty || bundled == installed) return null;

    final previous = await _readInstalledManifest();
    onCopy?.call();
    try {
      await _dao.replaceWithBundled();
    } on Object catch (error) {
      debugPrint('content update: $error');
      // #617: a copy that fails, on a full disk most likely, leaves the old
      // course attached (`replaceWithBundled`). Nothing is recorded and the
      // kept manifest stays the old one, so the next launch tries again. The
      // learner studies the old course meanwhile, rather than meeting an app
      // that won't open. If the old course did not come back either,
      // bootstrap's `version()` right after still fails the start.
      // #885: so does one older than this build reads, with the copy's own
      // error, which says storage when it was the space.
      if (!await _dao.fitsBuild()) rethrow;
      return null;
    }
    final current = await _readBundledManifest();
    await _moveAliased(current);
    final change = _diff(previous, current, bundled);

    await _record(change);
    // Last: until this is written, the update has not happened as far as the
    // next launch is concerned.
    await _saveInstalledManifest();
    return change;
  }

  /// Whether the installed course is this build's, as [runIfNeeded] decides
  /// it. A background task runs only on one (#1018): this build's SQL on an
  /// older course fails, and an update's re-keying is the app's to do.
  Future<bool> current() async {
    final bundled = await _dao.bundledVersion();
    return bundled.isEmpty || bundled == await _installedVersion();
  }

  /// The update Today should be showing, or `null`.
  ///
  /// BR-CONTENT-03: the card stays until the learner dismisses it, which is
  /// what `seen` records.
  ///
  /// An update with nothing to report is not one to show: a first install is
  /// recorded as [ContentChange.none], and a card reading "0 added · 0
  /// removed · 0 changed" would announce a change that did not happen.
  Future<ContentChange?> unseen() async {
    final rows = await _db
        .customSelect(
          'SELECT version, changed_json FROM content_updates '
          'WHERE seen = 0 ORDER BY version DESC',
        )
        .get();
    for (final row in rows) {
      final change = ContentChange.fromJson(
        row.read<String>('version'),
        row.read<String?>('changed_json') ?? '{}',
      );
      if (!change.isEmpty) return change;
    }
    return null;
  }

  /// BR-CONTENT-03's card is one-time: dismissing the newest update clears
  /// every one before it too (#477). Versions order as strings, as
  /// [unseen]'s does, because PIPE-07's `content_version` is the UTC build
  /// stamp: `YYYYMMDDHHMMSS`, or `YYYYMMDDHHMM` before #722, and a longer
  /// stamp of a later build sorts after a shorter one.
  // ponytail: the card counts the newest update alone, so an older unseen
  // one's changes go uncounted; net counts from the unseen rows'
  // changed_json if the owner wants them.
  Future<void> markSeen(String version) => _db.customStatement(
    'UPDATE content_updates SET seen = 1 WHERE version <= ?',
    <Object?>[version],
  );

  /// The uids whose meaning changed recently enough to wear the chip: the
  /// `meaning` list, not `changed`, which counts every field Today's card does.
  ///
  /// Aged from `recorded_at` — when *this device* saw the update — not from
  /// `version`, which is the pipeline's build time. Someone who installs the
  /// app three months after a build would otherwise never see a chip at all,
  /// because the version is already outside the window on the day they get it.
  ///
  /// Read as a set because `word-detail` asks per word, and a list scan per
  /// card is the kind of thing that turns a smooth list into a stuttering one.
  Future<Set<String>> recentlyUpdated(DateTime now) async {
    final cutoff = now.toUtc().subtract(updatedChipWindow);
    final rows = await _db
        .customSelect(
          'SELECT version, changed_json FROM content_updates '
          'WHERE recorded_at >= ?',
          variables: <Variable<Object>>[
            Variable<String>(cutoff.toIso8601String()),
          ],
        )
        .get();

    return <String>{
      for (final row in rows)
        ...ContentChange.fromJson(
          row.read<String>('version'),
          row.read<String?>('changed_json') ?? '{}',
        ).meaning,
    };
  }

  /// Every user.db column holding a course word's uid.
  static const List<(String, String)> aliasedColumns = <(String, String)>[
    ('word_state', 'word_uid'),
    ('review_log', 'word_uid'),
    ('plan_items', 'word_uid'),
    ('sentence_log', 'word_uid'),
    ('quiz_answers', 'word_uid'),
    // A word section's ref is the bare uid; grammar, writing and speaking
    // refs carry `#` or a prefix and never match one.
    ('exam_answers', 'item_ref'),
    ('custom_words', 'matched_uid'),
  ];

  /// Every user.db column holding a grammar topic's uid (#808). An exam's
  /// grammar ref, `<topic uid>#<n>`, moves too, in [_moveAliased].
  static const List<(String, String)> aliasedGrammarColumns =
      <(String, String)>[
        ('grammar_state', 'grammar_uid'),
        ('grammar_practice_log', 'grammar_uid'),
      ];

  /// The installed course's PIPE-09 `aliases`, old uid to uid now: an import
  /// moves a backup's rows along them, since a file exported under an older
  /// course names its words as that course did (#809). The kept manifest,
  /// not the bundled one: it describes the course attached. Empty when there
  /// is none, or none this build can read.
  Future<Map<String, String>> aliases() async {
    try {
      final aliases = (await _readInstalledManifest())?['aliases'];
      if (aliases is Map<String, dynamic>) {
        return Map<String, String>.from(aliases);
      }
    } on Object catch (error) {
      debugPrint('content aliases: $error');
    }
    return const <String, String>{};
  }

  /// PIPE-09 (#648): a word, or a grammar topic (#808), whose uid changed
  /// between builds keeps the learner's progress. The manifest's `aliases`
  /// map each old uid to the one it has now, and every row under an old uid
  /// moves to it, in one transaction. Re-runnable: once moved, nothing is
  /// under the old uid.
  ///
  /// OR IGNORE: where a row under the new uid already holds the key, it
  /// wins, and the old one stays where it was, as it would without the map.
  Future<void> _moveAliased(Map<String, dynamic>? manifest) async {
    final aliases = manifest?['aliases'];
    if (aliases is! Map<String, dynamic> || aliases.isEmpty) return;
    final json = jsonEncode(aliases);
    await _db.transaction(() async {
      for (final (table, column) in [
        ...aliasedColumns,
        ...aliasedGrammarColumns,
      ]) {
        await _db.customStatement(
          'UPDATE OR IGNORE $table SET $column = '
          '(SELECT value FROM json_each(?1) WHERE key = $column) '
          'WHERE $column IN (SELECT key FROM json_each(?1))',
          <Object?>[json],
        );
      }
      // A grammar item's ref keeps its `#<n>`: the topic moves, not the item.
      const topic = "substr(item_ref, 1, instr(item_ref, '#') - 1)";
      await _db.customStatement(
        'UPDATE exam_answers SET item_ref = '
        '(SELECT value FROM json_each(?1) WHERE key = $topic) '
        "|| substr(item_ref, instr(item_ref, '#')) "
        'WHERE $topic IN (SELECT key FROM json_each(?1))',
        <Object?>[json],
      );
    });
  }

  ContentChange _diff(
    Map<String, dynamic>? previous,
    Map<String, dynamic>? current,
    String version,
  ) {
    if (previous == null || current == null) {
      // A first install, or a manifest this build cannot read. Recording every
      // word as added would tell the learner their whole course is new, which
      // it is — but on an *update* it would be a lie, so neither is reported.
      return ContentChange.none(version);
    }

    Map<String, String> digests(Map<String, dynamic> manifest, String key) =>
        (manifest[key] as Map<String, dynamic>? ?? const {})
            .cast<String, String>();
    List<String> moved(Map<String, String> before, Map<String, String> after) =>
        <String>[
          ...after.keys.where(
            (uid) => before.containsKey(uid) && before[uid] != after[uid],
          ),
        ]..sort();

    // PIPE-09: a word whose uid changed is the same word, changed, not one
    // removed and one added. A duplicate merged into a word [before] already
    // had (PIPE-12) is neither: its progress moved to that word, and the
    // learner lost nothing (#922). `diff` in tools/content_manifest.py does
    // the same.
    final aliases = digests(current, 'aliases');
    Map<String, String> follow(Map<String, String> before) => <String, String>{
      for (final MapEntry(key: uid, value: digest) in before.entries)
        if (!before.containsKey(aliases[uid])) aliases[uid] ?? uid: digest,
    };

    final before = follow(digests(previous, 'words'));
    final after = digests(current, 'words');

    return ContentChange(
      version: version,
      added: <String>[...after.keys.where((uid) => !before.containsKey(uid))]
        ..sort(),
      removed: <String>[...before.keys.where((uid) => !after.containsKey(uid))]
        ..sort(),
      changed: moved(before, after),
      // A kept manifest from before `meanings` compares nothing: no chip,
      // rather than a false one.
      meaning: moved(
        follow(digests(previous, 'meanings')),
        digests(current, 'meanings'),
      ),
    );
  }

  Future<void> _record(ContentChange change) async {
    // Not INSERT OR REPLACE: that resets `seen`, and a re-run after an
    // interrupted update would bring back a card the learner had dismissed.
    // #621: a re-run with no baseline (a reset course, a truncated kept
    // manifest) diffs to nothing; it never wipes the diff already recorded.
    await _db.customStatement(
      'INSERT INTO content_updates '
      '(version, added, removed, changed_json, seen, recorded_at) '
      'VALUES (?, ?, ?, ?, 0, ?) '
      'ON CONFLICT(version) DO '
      '${change.isEmpty ? 'NOTHING' : 'UPDATE SET added = excluded.added, '
                'removed = excluded.removed, '
                'changed_json = excluded.changed_json'}',
      <Object?>[
        change.version,
        change.added.length,
        change.removed.length,
        change.toJson(),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<File> _installedManifest() async =>
      File('${(await getApplicationSupportDirectory()).path}/$manifestFile');

  static final RegExp _versionKey = RegExp(
    r'"content_version"\s*:\s*"([^"\\]+)"',
  );

  /// A manifest's `content_version`, or null (#710).
  ///
  /// A regex over the text rather than a JSON decode: a launch with no update
  /// compares two versions, and this spares it two decodes of half a megabyte
  /// of JSON. Only the top level has the key (below it are uids and digests).
  /// The whole text, not a head: since #648 the growing `aliases` map sorts
  /// before it (`write_manifest` sorts keys).
  static String? versionIn(List<int> bytes) => _versionKey
      .firstMatch(utf8.decode(bytes, allowMalformed: true))
      ?.group(1);

  /// The kept manifest's `content_version`, or '' when there is none.
  Future<String> _installedVersion() async {
    final file = await _installedManifest();
    if (!await file.exists()) return '';
    return versionIn(await file.readAsBytes()) ?? '';
  }

  Future<Map<String, dynamic>?> _readInstalledManifest() async {
    final file = await _installedManifest();
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      // A truncated manifest is a diff nobody can trust, not a crash.
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readBundledManifest() async {
    try {
      final text = await rootBundle.loadString(manifestAsset);
      return jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  /// Keeps the bundled manifest as the baseline for the next update.
  ///
  /// Written beside it and renamed over it: a copy cut short would keep the
  /// new version in its first bytes, which is all a launch reads (#710), over
  /// a diff nobody could take.
  Future<void> _saveInstalledManifest() async {
    final text = await rootBundle.loadString(manifestAsset);
    final kept = await _installedManifest();
    final incoming = File('${kept.path}.new');
    await incoming.writeAsString(text, flush: true);
    await incoming.rename(kept.path);
  }
}
