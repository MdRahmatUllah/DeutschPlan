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
  Future<ContentChange?> runIfNeeded() async {
    // The kept manifest is the baseline, not the attached database. If the app
    // is killed between the file swap and the record — a launch, the most
    // likely moment — the database already reads as current while no
    // `content_updates` row exists and the kept manifest still describes the
    // old version. Comparing against the manifest makes the whole thing
    // re-runnable: the next launch simply does it again, and
    // `replaceWithBundled` is idempotent.
    final previous = await _readInstalledManifest();
    final installed = previous?['content_version'] as String? ?? '';

    final bundled = await _dao.bundledVersion();
    if (bundled.isEmpty || bundled == installed) return null;

    await _dao.replaceWithBundled();
    final change = _diff(previous, await _readBundledManifest(), bundled);

    await _record(change);
    // Last: until this is written, the update has not happened as far as the
    // next launch is concerned.
    await _saveInstalledManifest();
    return change;
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

  Future<void> markSeen(String version) => _db.customStatement(
    'UPDATE content_updates SET seen = 1 WHERE version = ?',
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

    final before = digests(previous, 'words');
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
        digests(previous, 'meanings'),
        digests(current, 'meanings'),
      ),
    );
  }

  Future<void> _record(ContentChange change) async {
    // Not INSERT OR REPLACE: that resets `seen`, and a re-run after an
    // interrupted update would bring back a card the learner had dismissed.
    await _db.customStatement(
      'INSERT INTO content_updates '
      '(version, added, removed, changed_json, seen, recorded_at) '
      'VALUES (?, ?, ?, ?, 0, ?) '
      'ON CONFLICT(version) DO UPDATE SET added = excluded.added, '
      'removed = excluded.removed, changed_json = excluded.changed_json',
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
