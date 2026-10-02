import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/matcher.dart';
import 'package:sogda/domain/documents/photo_privacy.dart';
import 'package:sogda/domain/documents/tokens.dart';
import 'package:sogda/domain/text_norm.dart';

/// What a document's run reads of the course and the learner, once
/// (`document-matcher.md`, *The matcher*).
typedef MatcherInput = ({
  List<LemmaEntry> entries,
  Map<String, CourseWordInfo> course,
  LearnerSnapshot learner,
});

/// Learn from your documents (#1230): the saved documents, what D2 found in
/// them, and the learner's own sentences for a word (`user-database.md`,
/// the v6 tables of #1226).
class DocumentRepository {
  DocumentRepository(this._db, this._now);

  final AppDatabase _db;
  final DateTime Function() _now;

  /// D1 saves the text (BR-DOC-05), and D2 opens it by the id this returns.
  /// [body] is the text after clean-up (`cleanPages`, pipeline step 2), and
  /// cut to the limit: [match] reads it as it is.
  Future<int> create({
    required String title,
    required String source,
    required String body,
    int pageCount = 1,
  }) => _db
      .into(_db.documents)
      .insert(
        DocumentsCompanion.insert(
          title: title,
          source: source,
          createdAt: _now().toUtc().toIso8601String(),
          body: body,
          pageCount: Value(pageCount),
        ),
      );

  /// BR-DOC-05: [id]'s photos, kept with it while *Save original images* is
  /// on (#1229), without their metadata (`withoutMetadata`). Written under
  /// `<appSupport>/documents/<id>/` in page order, and listed in
  /// `image_paths` relative to `<appSupport>`, so a moved app folder keeps
  /// them.
  Future<void> saveImages(
    int id,
    List<String> photos, {
    Directory? support,
  }) async {
    final root = support ?? await getApplicationSupportDirectory();
    await Directory('${root.path}/documents/$id').create(recursive: true);
    final kept = <String>[];
    for (final (i, photo) in photos.indexed) {
      // Rewritten without its metadata, never copied: no GPS, no camera,
      // no time taken (BR-DOC-05). A format that can't be cleaned isn't
      // kept; the document's text is.
      final clean = withoutMetadata(await File(photo).readAsBytes());
      if (clean == null) continue;
      final name = 'documents/$id/page-${i + 1}${_extension(photo)}';
      await File('${root.path}/$name').writeAsBytes(clean, flush: true);
      kept.add(name);
    }
    await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
      DocumentsCompanion(imagePaths: Value(jsonEncode(kept))),
    );
  }

  /// Every document's photos: *Reset everything* (FR-M7-02) and a Replace,
  /// whose documents come without them (BR-DOC-06). Best effort, after the
  /// data, as the recordings go.
  Future<void> deleteAllImages({Directory? support}) async {
    final root = support ?? await getApplicationSupportDirectory();
    final folder = Directory('${root.path}/documents');
    if (folder.existsSync()) await folder.delete(recursive: true);
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot).toLowerCase() : '.jpg';
  }

  /// FR-D1-04, before D1 saves anything: the share of [body]'s words the
  /// course knows (`germanShare`), read in an isolate as [match] is.
  Future<double> germanShareOf(String body) async {
    final entries = <LemmaEntry>[
      for (final row in await ContentDao(_db).lemmaWords().get())
        LemmaEntry(
          uid: row.uid,
          german: row.german,
          pos: row.pos ?? '',
          article: row.article,
          forms: row.forms,
        ),
    ];
    return _shareApart(body, entries);
  }

  Future<Document?> document(int id) => (_db.select(
    _db.documents,
  )..where((d) => d.id.equals(id))).getSingleOrNull();

  /// The course and the learner as the matcher reads them: every word to
  /// learn, with its step, level and frequency; the statuses; every uid any
  /// day's plan has held; *My words*; and the active step.
  Future<MatcherInput> matcherInput() async {
    final content = ContentDao(_db);
    final steps = await content.allSublevels().get();
    // The course's order of steps, A1.1 first: not a column read raw.
    final order = <String, int>{
      for (final (i, step) in steps.indexed) step.code: i + 1,
    };
    final entries = <LemmaEntry>[];
    final course = <String, CourseWordInfo>{};
    for (final row in await content.lemmaWords().get()) {
      entries.add(
        LemmaEntry(
          uid: row.uid,
          german: row.german,
          pos: row.pos ?? '',
          article: row.article,
          forms: row.forms,
        ),
      );
      course[row.uid] = CourseWordInfo(
        stepOrder: order[row.sublevelCode] ?? 0,
        level: row.levelCode,
        freq: row.freq ?? 0,
      );
    }
    final planned = _db.selectOnly(_db.planItems, distinct: true)
      ..addColumns(<Expression<Object>>[_db.planItems.wordUid]);
    final active =
        await (_db.select(_db.enrollments)
              ..where((e) => e.completedOn.isNull())
              ..limit(1))
            .getSingleOrNull();
    final step = active == null
        ? null
        : steps.where((s) => s.code == active.sublevelCode).firstOrNull;
    final custom = await _db.select(_db.customWords).get();
    return (
      entries: entries,
      course: course,
      learner: LearnerSnapshot(
        status: <String, String>{
          for (final row in await _db.select(_db.wordState).get())
            row.wordUid: row.status,
        },
        everPlanned: <String>{
          for (final row in await planned.get())
            row.read(_db.planItems.wordUid)!,
        },
        mine: <String>{for (final row in custom) searchKey(row.german)},
        mineUids: <String>{for (final row in custom) ?row.matchedUid},
        activeStepOrder: step == null ? null : order[step.code],
        level: step?.levelCode,
      ),
    );
  }

  /// Document [id]'s words, worked out in an isolate, where the lemmatiser
  /// builds its index, and saved as `document_words` for D3 (FR-D2-07). A
  /// word it saved before keeps its `added`. Null for a document that's
  /// gone.
  Future<DocumentMatch?> match(int id) async {
    final document = await this.document(id);
    if (document == null) return null;
    final body = document.body;
    final match = await _matchApart(body, await matcherInput());
    await _db.transaction(() async {
      await _db.batch((batch) {
        // A row from an earlier run takes this run's class and surface (what
        // the learner has learnt since), and keeps its `added`, which the
        // companions don't carry (agent-3's review of #1275).
        batch.insertAllOnConflictUpdate(
          _db.documentWords,
          <DocumentWordsCompanion>[
            for (final word in match.words)
              for (final s in word.sentences)
                DocumentWordsCompanion.insert(
                  documentId: id,
                  lemmaKey: word.key,
                  surface: word.surface,
                  sentence: _sentence(body, match, s),
                  class$: word.docClass.name,
                ),
          ],
        );
      });
      await (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(wordCount: Value(match.words.length)),
      );
    });
    return match;
  }

  /// The lemma keys of [id]'s words the learner has added.
  Future<Set<String>> added(int id) async => <String>{
    for (final row in await (_db.select(
      _db.documentWords,
    )..where((w) => w.documentId.equals(id) & w.added.equals(1))).get())
      row.lemmaKey,
  };

  /// D2's *Add* (BR-DOC-04): the word is marked added in [documentId], and
  /// [sentence] is kept as its context, once (a second add of the same
  /// sentence changes nothing). The plan's side is #1231's.
  Future<void> recordAdd({
    required int documentId,
    required String lemmaKey,
    required String wordKey,
    required String sentence,
  }) => _db.transaction(() async {
    await (_db.update(_db.documentWords)..where(
          (w) => w.documentId.equals(documentId) & w.lemmaKey.equals(lemmaKey),
        ))
        .write(const DocumentWordsCompanion(added: Value(1)));
    await _db
        .into(_db.wordContexts)
        .insert(
          WordContextsCompanion.insert(
            wordKey: wordKey,
            sentence: sentence,
            documentId: Value(documentId),
            createdAt: _now().toUtc().toIso8601String(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });

  /// The run, in its own isolate. Static, so the closure takes only [body]
  /// and [input] across: an instance method's closures share a context with
  /// `this`, and the database can't be sent.
  static Future<DocumentMatch> _matchApart(String body, MatcherInput input) =>
      Isolate.run(
        () => matchText(
          body,
          Lemmatiser(input.entries),
          input.course,
          input.learner,
        ),
      );

  /// Static for the same reason as [_matchApart].
  static Future<double> _shareApart(String body, List<LemmaEntry> entries) =>
      Isolate.run(() => germanShare(splitText(body), Lemmatiser(entries)));

  static String _sentence(String body, DocumentMatch match, int index) {
    final sentence = match.sentences[index];
    return body.substring(sentence.start, sentence.end).trim();
  }
}
