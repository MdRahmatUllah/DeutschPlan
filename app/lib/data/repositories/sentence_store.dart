import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:drift/drift.dart';

/// [SentenceStore] over drift: `word_examples` from the attached course,
/// `word_state` and `sentence_log` from the learner's database.
class DriftSentenceStore implements SentenceStore {
  DriftSentenceStore(this._db);

  final AppDatabase _db;

  static SentenceCandidate _candidate(QueryRow row) => SentenceCandidate(
    wordUid: row.read<String>('word_uid'),
    ord: row.read<int>('ord'),
    german: row.read<String>('german'),
    english: row.readNullable<String>('english'),
    headword: row.data['headword'] as String?,
    pos: row.data['pos'] as String?,
  );

  @override
  Future<List<SentenceCandidate>> shownOn(PlanDate date) async {
    final rows = await _db
        .customSelect(
          '''
SELECT l.word_uid, l.ord, e.german, e.english
FROM sentence_log l
JOIN word_examples e ON e.word_uid = l.word_uid AND e.ord = l.ord
WHERE l.shown_on = ?1
ORDER BY l.rowid
''',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.sentenceLog},
        )
        .get();
    return rows.map(_candidate).toList();
  }

  @override
  Future<List<SentenceCandidate>> candidates(
    PlanDate today, {
    required int gapDays,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT e.word_uid, e.ord, e.german, e.english, w.german AS headword, w.pos
FROM word_examples e
JOIN words w ON w.uid = e.word_uid
JOIN word_state s ON s.word_uid = e.word_uid
WHERE s.status IN ('learning', 'done')
  AND NOT EXISTS (
    SELECT 1 FROM sentence_log l
    WHERE l.word_uid = e.word_uid AND l.ord = e.ord AND l.shown_on > ?1
  )
ORDER BY e.word_uid, e.ord
''',
          variables: <Variable<Object>>[
            Variable<String>(addDays(today, -gapDays)),
          ],
          readsFrom: <ResultSetImplementation<Object, Object>>{
            _db.wordState,
            _db.sentenceLog,
          },
        )
        .get();
    return rows.map(_candidate).toList();
  }

  @override
  Future<Set<String>> learnedKeys() async {
    final rows = await _db
        .customSelect(
          '''
SELECT w.search_key FROM words w
JOIN word_state s ON s.word_uid = w.uid
WHERE s.status IN ('learning', 'done')
''',
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.wordState},
        )
        .get();
    return <String>{for (final row in rows) row.read<String>('search_key')};
  }

  @override
  Future<void> record(PlanDate date, List<SentenceCandidate> picked) =>
      _db.transaction(() async {
        for (final sentence in picked) {
          await _db.customInsert(
            'INSERT OR IGNORE INTO sentence_log (word_uid, ord, shown_on) '
            'VALUES (?1, ?2, ?3)',
            variables: <Variable<Object>>[
              Variable<String>(sentence.wordUid),
              Variable<int>(sentence.ord),
              Variable<String>(date),
            ],
            updates: <TableInfo<Table, Object>>{_db.sentenceLog},
          );
        }
      });

  /// FR-T5-02: how a sentence went — `self_rating` 3 Understood, 2 Partly,
  /// 1 Not yet (`sentences.md`).
  Future<void> rate(PlanDate date, SentenceCandidate sentence, int rating) =>
      _db.customUpdate(
        'UPDATE sentence_log SET self_rating = ?4 '
        'WHERE word_uid = ?1 AND ord = ?2 AND shown_on = ?3',
        variables: <Variable<Object>>[
          Variable<String>(sentence.wordUid),
          Variable<int>(sentence.ord),
          Variable<String>(date),
          Variable<int>(rating),
        ],
        updates: <TableInfo<Table, Object>>{_db.sentenceLog},
      );

  /// [date]'s ratings so far, by sentence: where T5 picks up on reopening.
  Future<Map<(String, int), int>> ratings(PlanDate date) async {
    final rows = await _db
        .customSelect(
          'SELECT word_uid, ord, self_rating FROM sentence_log '
          'WHERE shown_on = ?1 AND self_rating IS NOT NULL',
          variables: <Variable<Object>>[Variable<String>(date)],
          readsFrom: <ResultSetImplementation<Object, Object>>{_db.sentenceLog},
        )
        .get();
    return <(String, int), int>{
      for (final row in rows)
        (row.read<String>('word_uid'), row.read<int>('ord')): row.read<int>(
          'self_rating',
        ),
    };
  }

  /// How many of [date]'s sentences have been rated: Today's done count.
  Stream<int> watchRated(PlanDate date) =>
      _rated(date).watchSingle().map((row) => row.read<int>('n'));

  /// [watchRated], once: T3's "Practice 3 sentences".
  Future<int> rated(PlanDate date) async =>
      (await _rated(date).getSingle()).read<int>('n');

  Selectable<QueryRow> _rated(PlanDate date) => _db.customSelect(
    'SELECT COUNT(*) AS n FROM sentence_log '
    'WHERE shown_on = ?1 AND self_rating IS NOT NULL',
    variables: <Variable<Object>>[Variable<String>(date)],
    readsFrom: <ResultSetImplementation<Object, Object>>{_db.sentenceLog},
  );
}
