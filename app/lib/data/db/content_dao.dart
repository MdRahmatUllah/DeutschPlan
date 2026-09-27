import 'dart:io';

import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/domain/compare_set.dart';
import 'package:sogda/domain/placement.dart';
import 'package:sogda/domain/quiz_builder.dart' show QuizWord;
import 'package:sogda/domain/text_norm.dart' show searchKey;
import 'package:drift/drift.dart';

import 'dart:convert';

import 'package:sogda/data/db/content_update.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, sqlite3;

part 'content_dao.g.dart';

/// One step of the course, as S2 page 3 lists it.
typedef CourseStep = ({String code, String levelCode, int wordCount});

/// What M9 says of the course (FR-M9-01).
typedef ContentFacts = ({
  String version,
  DateTime? builtAt,
  int words,
  int grammar,
  int sentences,
});

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

  /// FR-T5-03: the course word a sentence's token belongs to (#324): its
  /// search key itself; else a form the course gives in `words.forms`
  /// ("ist" for *sein*, "gibt" for *geben*, "Häuser" for *Haus*); else the
  /// longest key, three letters at least, that the token is plus an
  /// inflection ending ("Wohnungen" for *Wohnung*, "leichter" for
  /// *leicht*). A compound is not its first part: "Hausfrau" is not *Haus*.
  /// Else, for the sentence's [first] word or a small-letter one ending in
  /// -e, the verb it is the du-imperative or first person of (#724): "Mach"
  /// *machen*, "Sei" *sein*, "habe" *haben*. Anywhere else a bare stem is
  /// most often an adjective or a split verb's particle ("leid", "wahr",
  /// "teil"), and a capital a noun ("Stimme" is no *stimmen*).
  /// Null for a word the course lacks.
  // ponytail: "Mach die Lampe an." is *machen*, not *anmachen*: a particle
  // at the clause's end isn't looked for. And a word the course lacks,
  // opening a sentence, may be read as a verb: "Stille Diplomatie…" opens
  // *stillen*, "Anstoß erregen…" *anstoßen*, "dank + Dativ…" *danken* (3 of
  // the 35 first words this step matches in the course); telling them apart
  // needs the part of speech of a word the course doesn't have.
  Future<Word?> wordForToken(String token, {bool first = false}) async {
    final key = searchKey(token, stripArticle: false);
    if (key.isEmpty) return null;
    Future<Word?> where(String sql, List<Variable<Object>> variables) async {
      final row = await customSelect(
        'SELECT * FROM words WHERE $sql ORDER BY length(search_key) DESC, seq '
        'LIMIT 1',
        variables: variables,
        readsFrom: <ResultSetImplementation<Object, Object>>{words},
      ).getSingleOrNull();
      return row == null ? null : words.map(row.data);
    }

    final exact = await where(
      "search_key = ?1 AND coalesce(pos, '') <> 'phrase'",
      <Variable<Object>>[Variable<String>(key)],
    );
    if (exact != null) return exact;
    final form = (await _forms())[key];
    if (form != null) {
      return where('uid = ?1', <Variable<Object>>[Variable<String>(form)]);
    }
    // A phrase keyed the same only after the words and their forms: "geht"
    // is gehen's, not "geht"'s ("it works").
    final phrase = await where('search_key = ?1', <Variable<Object>>[
      Variable<String>(key),
    ]);
    if (phrase != null) return phrase;
    final ending = await where(
      "length(search_key) >= 3 AND ?1 LIKE search_key || '%' "
      'AND substr(?1, length(search_key) + 1) IN '
      // Not -t or -st: the headwords are infinitives, nouns and
      // adjectives, and "bist", "erfolgt", "gehört" are not bis, Erfolg,
      // Gehör.
      "('e', 'en', 'er', 'es', 'em', 'ern', 'ens', 'n', 's')",
      <Variable<Object>>[Variable<String>(key)],
    );
    if (ending != null ||
        !(first || (key.endsWith('e') && _small.hasMatch(token)))) {
      return ending;
    }
    return where(
      "pos = 'verb' AND search_key IN (?1 || 'en', ?1 || 'n')",
      <Variable<Object>>[Variable<String>(key)],
    );
  }

  static final RegExp _small = RegExp(r'^\p{Ll}', unicode: true);

  /// Every form in `words.forms`, by search key, to its word: the first by
  /// the course's order where two share one. Built once per DAO.
  ///
  /// ponytail: in memory, a few thousand keys; a `word_forms` table built by
  /// the pipeline if the content ever gets big enough for this to show.
  Future<Map<String, String>> _forms() => _formIndex ??= () async {
    final index = <String, String>{};
    final rows = await customSelect(
      // Not a phrase's: "Zeit haben" carries haben's forms, and "hat" is
      // haben, not the phrase. A verb of more words (sich freuen) is fine.
      "SELECT uid, forms FROM words WHERE forms IS NOT NULL "
      "AND coalesce(pos, '') <> 'phrase' ORDER BY seq",
      readsFrom: <ResultSetImplementation<Object, Object>>{words},
    ).get();
    for (final row in rows) {
      final uid = row.read<String>('uid');
      for (final key in formKeys(row.read<String>('forms'))) {
        index.putIfAbsent(key, () => uid);
      }
    }
    return index;
  }();

  Future<Map<String, String>>? _formIndex;

  /// EN → DE's other right answers (#832): the course's words by meaning
  /// cell, English or Bangla, for each cell two words or more share — "you"
  /// is du, dich and Sie. A cell is compared as written. Built once per DAO.
  Future<Map<String, List<QuizWord>>> sharedMeanings() => _shared ??= () async {
    final rows = await customSelect(
      'SELECT uid, sublevel_code, article, german, pos, english, bangla '
      "FROM words WHERE kind = 'vocab' AND (english IN (SELECT english "
      "FROM words WHERE kind = 'vocab' GROUP BY english HAVING COUNT(*) > 1) "
      "OR bangla IN (SELECT bangla FROM words WHERE kind = 'vocab' "
      'AND bangla IS NOT NULL GROUP BY bangla HAVING COUNT(*) > 1)) '
      'ORDER BY seq',
      readsFrom: <ResultSetImplementation<Object, Object>>{words},
    ).get();
    final shared = <String, List<QuizWord>>{};
    for (final row in rows) {
      final word = QuizWord(
        uid: row.read<String>('uid'),
        german: row.read<String>('german'),
        english: row.read<String>('english'),
        step: row.read<String>('sublevel_code'),
        article: row.readNullable<String>('article'),
        pos: row.readNullable<String>('pos'),
        bangla: row.readNullable<String>('bangla'),
      );
      for (final cell in <String>{word.english, ?word.bangla}) {
        (shared[cell] ??= <QuizWord>[]).add(word);
      }
    }
    return shared..removeWhere((_, words) => words.length < 2);
  }();

  Future<Map<String, List<QuizWord>>>? _shared;

  /// W2 (#142): the set word [uid], and the course word each of its members
  /// is (FR-W2-01) — its own search key, the set's step first, then the
  /// course's order. Not a phrase or another set, and of the set's part of
  /// speech unless the set is a phrase: "rund" in *circa / etwa / rund* is
  /// not the adjective *rund*, "round", nor "klasse" in *prima / super /
  /// klasse* the noun *die Klasse*. Null for no such word, or a word that is
  /// no set to compare (`comparesSet`).
  // ponytail: a homograph of the same part of speech still resolves — *das
  // Alter* ("age") for "Alter" (dude) in *Digga / Alter*, *die Liebe* for
  // "Liebe" in the phrase set *Liebe / Lieber …*. A sense column in
  // content.db, or a curated member list, would tell them apart.
  Future<CompareSet?> compareSet(String uid) async {
    final set = await wordByUid(uid).getSingleOrNull();
    if (set == null || !comparesSet(set.german)) return null;
    Future<CompareWord> read(Word word) async => CompareWord(
      uid: word.uid,
      german: word.german,
      english: word.english,
      step: word.sublevelCode,
      article: word.article,
      pos: word.pos,
      forms: word.forms,
      register: word.synonymsRegister,
      collocations: word.collocations,
      examples: <CompareExample>[
        for (final e in await examplesForWord(word.uid).get())
          (german: e.german, english: e.english),
      ],
    );
    final resolved = <String, CompareWord>{};
    for (final name in compareMemberNames(set.german)) {
      final candidates = await compareCandidates(
        searchKey(name),
        set.sublevelCode,
      ).get();
      final word = candidates
          .where(
            (w) => set.pos == null || set.pos == 'phrase' || w.pos == set.pos,
          )
          .firstOrNull;
      if (word != null) resolved[name] = await read(word);
    }
    return CompareSet(await read(set), resolved);
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
      "WHERE w.sublevel_code = ?1 AND w.kind = 'vocab' "
      'ORDER BY w.seq_in_sublevel, e.ord',
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

  /// M9 · About (FR-M9-01, #150): the course's version, when it was built,
  /// and how much it holds.
  Future<ContentFacts> facts() async {
    final counts = await contentCounts().getSingle();
    final built = await contentMeta('built_at').getSingleOrNull();
    return (
      version: await version(),
      builtAt: built == null ? null : DateTime.tryParse(built),
      words: counts.wordTotal,
      grammar: counts.grammarTotal,
      sentences: counts.sentenceTotal,
    );
  }

  /// Whether [file] reads as a course: it opens, passes SQLite's quick check,
  /// and `meta` holds its version. Asked before deleting one (#617): a course
  /// that reads is never the reason a start failed.
  static bool readable(File file) {
    if (!file.existsSync()) return false;
    try {
      final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        final check = db.select('PRAGMA quick_check');
        final meta = db.select(
          "SELECT value FROM meta WHERE key = 'content_version'",
        );
        return check.length == 1 &&
            check.first.values.first == 'ok' &&
            meta.isNotEmpty &&
            '${meta.first['value'] ?? ''}'.isNotEmpty;
      } finally {
        db.close();
      }
    } on Object {
      // Not a database, or not the course's shape: it does not read.
      return false;
    }
  }

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
    // The manifest first, because it is 513 KB of JSON beside an 8 MB
    // database and carries the same `content_version` the database does;
    // and only its first bytes, where that version is (#710).
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

    try {
      await _copyAsset(incoming);
      await detach();
      try {
        incoming.renameSync(installed.path);
      } finally {
        // Whatever happened, the course has to come back.
        await attach();
      }
    } finally {
      // A copy, detach or rename that fails, on a full disk most likely,
      // leaves a file nothing will ever read (#617). After a rename there is
      // nothing left to delete.
      if (incoming.existsSync()) incoming.deleteSync();
    }
  }

  /// Async (#710): 8 MB written on the UI isolate froze S1's progress line.
  Future<void> _copyAsset(File target) async {
    final bytes = await rootBundle.load(asset);
    await target.parent.create(recursive: true);
    // flush: the next line opens this file with SQLite, and a buffered write
    // would give it a truncated header.
    await target.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  /// `content_version` out of the bundled manifest, or null when it cannot be
  /// read as one.
  Future<String?> _versionFromManifest() async {
    try {
      final data = await rootBundle.load(ContentUpdater.manifestAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final version =
          ContentUpdater.versionIn(bytes) ??
          (jsonDecode(utf8.decode(bytes))
              as Map<String, dynamic>)['content_version'];
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

/// The search keys of the forms in a `words.forms` cell: "ist · ist gewesen
/// (war)" gives `ist`, `gewesen`, `war`. A perfect's auxiliary, a
/// superlative's "am" and a reflexive's "sich" go (they belong to other
/// words). A separable verb split in two gives nothing: "steht auf" is not
/// *stehen*'s, nor its particle ("hat vor", "kommt zurück") a word's. An
/// ending ("-en") is not a form.
List<String> formKeys(String forms) {
  const helpers = <String>{'hat', 'ist', 'sind', 'haben', 'sein', 'am', 'sich'};
  final keys = <String>[];
  for (final part in forms.split(RegExp(r'[·,;/()]'))) {
    final words = part.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty || w.startsWith('-'));
    final more = words.length > 1;
    words.removeWhere((w) => helpers.contains(w.toLowerCase()) && more);
    // Still two words: a separable verb split ("steht auf" is aufstehen,
    // but "steht" is stehen), so neither is this word's. One left beside a
    // helper must be a participle or a superlative, not a particle ("hat
    // vor").
    if (words.length != 1 || (more && words.single.length < 4)) continue;
    final key = searchKey(words.single, stripArticle: false);
    if (key.isNotEmpty) keys.add(key);
  }
  return keys;
}
