import 'dart:io';

import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:drift/drift.dart';

import 'dart:convert';

import 'package:deutschplan/data/db/content_update.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

part 'content_dao.g.dart';

/// One step of the course, as S2 page 3 lists it.
typedef CourseStep = ({String code, String levelCode, int wordCount});

/// Where the course is read from.
///
/// `docs/02-data/content-database.md`: content.db is bundled as an asset,
/// copied to app-support storage on first run or when `meta.content_version`
/// differs, then **attached** to the user database as schema `c` and opened
/// read-only. The app never writes to it.
///
/// Every query is hand-written SQL in `content.drift`, because drift generates
/// nothing for an attached database. It type-checks them against
/// `content_schema.drift`, which mirrors the pipeline's DDL.
@DriftAccessor(include: <String>{'content.drift'})
class ContentDao extends DatabaseAccessor<AppDatabase> with _$ContentDaoMixin {
  ContentDao(super.db);

  /// FR-T5-03: the course word a sentence's token belongs to — its search
  /// key itself, or the longest key the token starts with ("Wohnungen" for
  /// "Wohnung"), three letters at least. Null for a word the course lacks.
  Future<Word?> wordForToken(String key) async {
    if (key.isEmpty) return null;
    final row = await customSelect(
      'SELECT * FROM words WHERE search_key = ?1 '
      "OR (length(search_key) >= 3 AND ?1 LIKE search_key || '%') "
      'ORDER BY length(search_key) DESC, seq LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(key)],
      readsFrom: <ResultSetImplementation<Object, Object>>{words},
    ).getSingleOrNull();
    return row == null ? null : words.map(row.data);
  }

  /// The category most of [uids] belong to: T1's "7 new · Wohnen & Haushalt".
  ///
  /// Null when none of them has one. A tie goes to the lower category id, so
  /// the card does not flip between two names from one build to the next.
  Future<String?> mainCategory(List<String> uids) async {
    if (uids.isEmpty) return null;
    final row = await customSelect(
      'SELECT k.name FROM words w JOIN categories k ON k.id = w.category_id '
      'WHERE w.uid IN (${List.filled(uids.length, '?').join(', ')}) '
      'GROUP BY k.id ORDER BY COUNT(*) DESC, k.id LIMIT 1',
      variables: <Variable<Object>>[
        for (final uid in uids) Variable<String>(uid),
      ],
    ).getSingleOrNull();
    return row?.read<String>('name');
  }

  /// L2's category chips (FR-L2-02): the categories [step]'s words fall in,
  /// the biggest first, a tie to the lower id.
  Future<List<({int id, String name})>> stepCategories(String step) async {
    final rows = await customSelect(
      'SELECT k.id, k.name FROM words w '
      'JOIN categories k ON k.id = w.category_id '
      'WHERE w.sublevel_code = ?1 '
      'GROUP BY k.id, k.name ORDER BY COUNT(*) DESC, k.id',
      variables: <Variable<Object>>[Variable<String>(step)],
    ).get();
    return <({int id, String name})>[
      for (final row in rows)
        (id: row.read<int>('id'), name: row.read<String>('name')),
    ];
  }

  /// S3's pool for one step: its words, with their example sentences for a
  /// gap item. Read-only, like everything on the attached course.
  Future<List<PlacementWord>> placementPool(String step) async {
    final rows = await customSelect(
      'SELECT w.uid, w.article, w.german, w.english, w.bangla, w.pos, '
      'e.german AS example '
      'FROM words w LEFT JOIN word_examples e ON e.word_uid = w.uid '
      'WHERE w.sublevel_code = ?1 ORDER BY w.seq_in_sublevel, e.ord',
      variables: <Variable<Object>>[Variable<String>(step)],
    ).get();

    final words = <String, PlacementWord>{};
    final examples = <String, List<String>>{};
    for (final row in rows) {
      final uid = row.read<String>('uid');
      words.putIfAbsent(
        uid,
        () => PlacementWord(
          uid: uid,
          article: row.readNullable<String>('article'),
          german: row.read<String>('german'),
          english: row.read<String>('english'),
          bangla: row.readNullable<String>('bangla'),
          pos: row.readNullable<String>('pos') ?? '',
          examples: examples.putIfAbsent(uid, () => <String>[]),
        ),
      );
      final example = row.readNullable<String>('example');
      if (example != null) examples[uid]!.add(example);
    }
    return words.values.toList();
  }

  /// The twelve steps in course order (BR-COURSE-01), with their word counts.
  ///
  /// A record rather than drift's row class, so a screen can hold it — and a
  /// provider can return it, which riverpod_generator cannot do with a type
  /// drift writes in the same build.
  Future<List<CourseStep>> courseSteps() async => <CourseStep>[
    for (final step in await allSublevels().get())
      (code: step.code, levelCode: step.levelCode, wordCount: step.wordCount),
  ];

  /// The schema name the doc uses. Queries do not write it — see the note at
  /// the top of `content.drift` — but `ATTACH` does, and so does anything that
  /// needs to be explicit.
  static const String schema = 'c';

  /// The bundled asset.
  static const String asset = 'assets/db/content.db';

  /// The installed copy's file name, under app support.
  static const String fileName = 'content.db';

  /// Attaches the installed copy, copying it from the asset first if needed.
  ///
  /// Returns the version now attached.
  ///
  /// The attach is by plain path, not by a `file:…?mode=ro` URI. SQLite only
  /// parses a URI filename when the *main* connection was opened with
  /// `SQLITE_OPEN_URI`, and the one `drift_flutter` opens is not — so the URI
  /// is taken as a literal file name and the attach fails.
  ///
  /// Read-only is kept by construction instead, which is stronger than a flag
  /// nobody re-checks: `content.drift` holds only SELECTs, the manager API
  /// that would generate writers is off, and `architecture_test.dart` fails
  /// the build if anything under `lib/` writes to a content table. ADR 26.
  Future<String> attach() async {
    final file = await installedFile();
    if (!file.existsSync()) {
      await _copyAsset(file);
    }

    await customStatement("ATTACH DATABASE '${attachPath(file)}' AS $schema");
    return version();
  }

  Future<void> detach() => customStatement('DETACH DATABASE $schema');

  /// `meta.content_version` of the attached copy.
  Future<String> version() async {
    final row = await contentMeta('content_version').getSingleOrNull();
    if (row == null) {
      throw StateError(
        'the attached content.db has no content_version. It was not written '
        'by the pipeline, or it is truncated.',
      );
    }
    return row;
  }

  /// `meta.content_version` of the **bundled** asset, without installing it.
  ///
  /// This is the probe `content-database.md` step 1 describes: the app has to
  /// know whether the asset is newer than the installed copy before deciding
  /// to replace it, and reading the asset means writing it somewhere first,
  /// because SQLite cannot open a Flutter asset in place.
  Future<String> bundledVersion() async {
    // The manifest first, because it is 255 KB of JSON beside an 8 MB
    // database and carries the same `content_version` the database does.
    //
    // The probe below reads the authoritative value, but to do it it copies
    // the *whole asset* to a temp file, attaches it, reads one string and
    // deletes it — on every launch, warm or cold. That is the cost
    // `splash.md` warns about ("probe the bundled asset's version without
    // loading the whole 5.5 MB into memory twice") and it was the single
    // largest thing between a warm start and FR-S1-02's 500 ms.
    //
    // `make content` writes the two files together, so they cannot disagree.
    // If the manifest is missing or unreadable the probe still runs: a
    // corrupt manifest must not stop the app noticing a content update.
    final fromManifest = await _versionFromManifest();
    if (fromManifest != null) return fromManifest;

    final probe = File(
      '${(await getTemporaryDirectory()).path}/content_probe.db',
    );
    try {
      await _copyAsset(probe);
      await customStatement("ATTACH DATABASE '${attachPath(probe)}' AS probe");
      final row = await customSelect(
        "SELECT value FROM probe.meta WHERE key = 'content_version'",
      ).getSingleOrNull();
      return row?.read<String>('value') ?? '';
    } finally {
      // Detached here, not after the SELECT: a truncated asset throws between
      // the two, and a probe left attached makes every later call fail with
      // "database probe is already in use". The app would then stop noticing
      // content updates for the rest of the session, with nothing on screen
      // to say why.
      try {
        await customStatement('DETACH DATABASE probe');
      } on Object {
        // It was never attached, which is the only way this throws here.
      }
      if (probe.existsSync()) probe.deleteSync();
    }
  }

  /// The installed copy, in app-support storage beside user.db.
  Future<File> installedFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');

  /// Replaces the installed copy with the bundled asset.
  ///
  /// The new copy is written beside the old one and only swapped in once it is
  /// on disk. Detaching first and then copying would leave the connection with
  /// no `c` schema at all if the copy failed — a full disk, a revoked
  /// permission — and every screen that reads the course would error until the
  /// app was restarted. Stale content is the better failure.
  ///
  /// The detach still has to happen before the rename: overwriting a file
  /// SQLite has open is how a database becomes unreadable rather than merely
  /// out of date.
  Future<void> replaceWithBundled() async {
    final installed = await installedFile();
    final incoming = File('${installed.path}.new');

    await _copyAsset(incoming);
    await detach();
    try {
      incoming.renameSync(installed.path);
    } finally {
      // Whatever happened, the course has to come back.
      await attach();
    }
  }

  Future<void> _copyAsset(File target) async {
    final bytes = await rootBundle.load(asset);
    target.parent.createSync(recursive: true);
    // flush: the next line opens this file with SQLite, and a buffered write
    // would give it a truncated header.
    target.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  /// `content_version` out of the bundled manifest, or null when it cannot be
  /// read as one.
  Future<String?> _versionFromManifest() async {
    try {
      final text = await rootBundle.loadString(ContentUpdater.manifestAsset);
      final version =
          (jsonDecode(text) as Map<String, dynamic>)['content_version'];
      return version is String && version.isNotEmpty ? version : null;
    } on Object {
      // Missing, truncated, or not the shape expected. The probe answers.
      return null;
    }
  }

  /// The path as it goes inside a quoted `ATTACH DATABASE '…'`.
  ///
  /// Only the quote is escaped. A Windows path keeps its backslashes, because
  /// SQLite treats the string as a file name rather than as an escape
  /// sequence — and rewriting it to forward slashes is what turned it into a
  /// URI that would not open.
  static String attachPath(File file) =>
      file.absolute.path.replaceAll("'", "''");
}
