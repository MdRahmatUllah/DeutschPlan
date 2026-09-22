import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// What one content update changed.
///
/// The counts go into `content_updates.added` / `.removed`; the uid lists go
/// into `changed_json`, because Today's card names words and `word-detail`
/// shows an *updated* chip for the ones whose meaning moved.
@immutable
class ContentChange {
  const ContentChange({
    required this.version,
    required this.added,
    required this.removed,
    required this.changed,
  });

  const ContentChange.none(this.version)
    : added = const <String>[],
      removed = const <String>[],
      changed = const <String>[];

  final String version;
  final List<String> added;
  final List<String> removed;
  final List<String> changed;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// The shape `content_updates.changed_json` stores.
  String toJson() => jsonEncode(<String, List<String>>{
    'added': added,
    'removed': removed,
    'changed': changed,
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
  Future<ContentChange?> runIfNeeded() async {
    final installed = await _dao.version();
    final bundled = await _dao.bundledVersion();
    if (bundled.isEmpty || bundled == installed) return null;

    // The previous manifest, read before anything overwrites it.
    final previous = await _readInstalledManifest();

    await _dao.replaceWithBundled();
    final change = _diff(previous, await _readBundledManifest(), bundled);

    await _record(change);
    await _saveInstalledManifest();
    return change;
  }

  /// The update Today should be showing, or `null`.
  ///
  /// BR-CONTENT-03: the card stays until the learner dismisses it, which is
  /// what `seen` records.
  Future<ContentChange?> unseen() async {
    final row = await _db
        .customSelect(
          'SELECT version, changed_json FROM content_updates '
          'WHERE seen = 0 ORDER BY version DESC LIMIT 1',
        )
        .getSingleOrNull();
    if (row == null) return null;

    return ContentChange.fromJson(
      row.read<String>('version'),
      row.read<String?>('changed_json') ?? '{}',
    );
  }

  Future<void> markSeen(String version) => _db.customStatement(
    'UPDATE content_updates SET seen = 1 WHERE version = ?',
    <Object?>[version],
  );

  /// The uids whose meaning changed recently enough to wear the chip.
  ///
  /// Read as a set because `word-detail` asks per word, and a list scan per
  /// card is the kind of thing that turns a smooth list into a stuttering one.
  Future<Set<String>> recentlyUpdated(DateTime now) async {
    final cutoff = now.subtract(updatedChipWindow);
    final rows = await _db
        .customSelect(
          'SELECT version, changed_json FROM content_updates '
          'WHERE version >= ?',
          variables: <Variable<Object>>[Variable<String>(_versionAt(cutoff))],
        )
        .get();

    return <String>{
      for (final row in rows)
        ...ContentChange.fromJson(
          row.read<String>('version'),
          row.read<String?>('changed_json') ?? '{}',
        ).changed,
    };
  }

  /// `content_version` is `YYYYMMDDHHMM`, so a date comparison is a string
  /// comparison — which is why the format was chosen (PIPE-07).
  static String _versionAt(DateTime time) {
    final utc = time.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}';
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

    final before = (previous['words'] as Map<String, dynamic>? ?? const {})
        .cast<String, String>();
    final after = (current['words'] as Map<String, dynamic>? ?? const {})
        .cast<String, String>();

    return ContentChange(
      version: version,
      added: <String>[...after.keys.where((uid) => !before.containsKey(uid))]
        ..sort(),
      removed: <String>[...before.keys.where((uid) => !after.containsKey(uid))]
        ..sort(),
      changed: <String>[
        ...after.keys.where(
          (uid) => before.containsKey(uid) && before[uid] != after[uid],
        ),
      ]..sort(),
    );
  }

  Future<void> _record(ContentChange change) async {
    await _db.customStatement(
      'INSERT OR REPLACE INTO content_updates '
      '(version, added, removed, changed_json, seen) VALUES (?, ?, ?, ?, 0)',
      <Object?>[
        change.version,
        change.added.length,
        change.removed.length,
        change.toJson(),
      ],
    );
  }

  Future<File> _installedManifest() async =>
      File('${(await getApplicationSupportDirectory()).path}/$manifestFile');

  Future<Map<String, dynamic>?> _readInstalledManifest() async {
    final file = await _installedManifest();
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
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
  Future<void> _saveInstalledManifest() async {
    final text = await rootBundle.loadString(manifestAsset);
    (await _installedManifest()).writeAsStringSync(text, flush: true);
  }
}
