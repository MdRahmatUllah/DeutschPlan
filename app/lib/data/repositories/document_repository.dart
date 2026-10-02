import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/matcher.dart';
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
    final active = await (_db.select(
      _db.enrollments,
    )..where((e) => e.completedOn.isNull())).getSingleOrNull();
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
        batch.insertAll(_db.documentWords, <DocumentWordsCompanion>[
          for (final word in match.words)
            for (final s in word.sentences)
              DocumentWordsCompanion.insert(
                documentId: id,
                lemmaKey: word.key,
                surface: word.surface,
                sentence: _sentence(body, match, s),
                class$: word.docClass.name,
              ),
        ], mode: InsertMode.insertOrIgnore);
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
