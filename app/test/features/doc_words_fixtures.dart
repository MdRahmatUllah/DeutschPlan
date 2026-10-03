import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/document_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/word_actions.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/documents/lemmatiser.dart';
import 'package:sogda/domain/documents/matcher.dart';
import 'package:sogda/domain/plan_engine.dart';
import 'package:sogda/domain/text_norm.dart';
import 'package:sogda/features/words/word_detail_screen.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/documents/lemmatiser_test.dart' show courseEntries;
import '../domain/documents/matcher_test.dart' show courseInfo;
import 'settings_fixtures.dart';

/// D2's artboard letter (#1222, `DocWords`): a team-written landlord's note.
const String artboardLetter =
    'Sehr geehrte Damen und Herren,\n\n'
    'hier ist die Nebenkostenabrechnung für 2025. Bitte überweisen Sie die '
    'Nachzahlung bis zum 15. November auf unser Konto.\n\n'
    'Am Dienstag kommt der Hausmeister. Er will die Heizkörper kontrollieren '
    'und den Wasserzähler ablesen. Bitte seien Sie zwischen 9 und 12 Uhr '
    'erreichbar.\n\n'
    'Bei Fragen zur Abrechnung rufen Sie uns an.';

final Lemmatiser _lemmatiser = Lemmatiser(courseEntries());
final Map<String, CourseWordInfo> _course = courseInfo();
final Map<String, String> _uid = <String, String>{
  for (final e in courseEntries()) e.german: e.uid,
};

/// The uid of a course word, by its headword.
String uidOf(String german) => _uid[german]!;

/// A learner in A2.1 (step 3), A2, who knows «überweisen» and keeps
/// «Heizkörper» as a word of their own.
LearnerSnapshot artboardLearner() => LearnerSnapshot(
  status: <String, String>{uidOf('überweisen'): 'done'},
  everPlanned: const <String>{},
  mine: <String>{searchKey('Heizkörper', stripArticle: false)},
  mineIds: <String, int>{searchKey('Heizkörper', stripArticle: false): 4},
  activeStepOrder: 3,
  level: 'A2',
);

/// The matcher's real run over [text], as D2 receives it.
DocumentMatch docMatch(String text, [LearnerSnapshot? learner]) =>
    matchText(text, _lemmatiser, _course, learner ?? artboardLearner());

/// [DocumentRepository] without a database: one document, its run, and
/// what D2 records.
class FakeDocuments extends Fake implements DocumentRepository {
  FakeDocuments({
    this.body = artboardLetter,
    this.title = 'Nebenkosten 2025',
    Set<String>? added,
    this._learner,
  }) : _added = added ?? <String>{};

  final String body;
  final String title;
  final Set<String> _added;
  final LearnerSnapshot? _learner;
  final List<({String lemmaKey, String wordKey, String sentence})> recorded =
      <({String lemmaKey, String wordKey, String sentence})>[];
  int runs = 0;

  @override
  Future<Document?> document(int id) async => Document(
    id: id,
    title: title,
    source: 'paste',
    createdAt: '2026-10-02T07:00:00Z',
    body: body,
    pageCount: 1,
    wordCount: 0,
  );

  @override
  Future<DocumentMatch?> match(int id) async {
    runs++;
    return docMatch(body, _learner);
  }

  @override
  Future<Set<String>> added(int id) async => <String>{..._added};

  @override
  Future<void> recordAdd({
    required int documentId,
    required String lemmaKey,
    required String wordKey,
    required String sentence,
  }) async {
    _added.add(lemmaKey);
    recorded.add((lemmaKey: lemmaKey, wordKey: wordKey, sentence: sentence));
  }
}

/// [PlanEngine]'s two document calls (#1272): today takes [slots], the rest
/// start on Monday.
class FakePlan extends Fake implements PlanEngine {
  FakePlan({
    this.slots = 5,
    this.paused = false,
    this.planned = const <String>{},
  });

  int slots;

  /// No day can be said (the backlog pause, a cap of 0): every start null.
  final bool paused;

  /// What today's plan has already by the course's route (#1315).
  final Set<String> planned;

  @override
  Future<Set<String>> plannedToday(PlanDate today) async => planned;
  final List<List<String>> added = <List<String>>[];

  @override
  Future<int> docSlotsLeft(PlanDate today) async => slots;

  @override
  Future<Map<String, PlanDate?>> addDocWords(
    List<String> uids,
    PlanDate today, {
    required String at,
  }) async {
    added.add(uids);
    final starts = <String, PlanDate?>{};
    for (final uid in uids) {
      if (paused) {
        starts[uid] = null;
        continue;
      }
      starts[uid] = slots > 0 ? today : '2026-10-05';
      if (slots > 0) slots--;
    }
    return starts;
  }
}

/// W1's *Mark known*, recorded, with an undo that's recorded too.
class FakeActions extends Fake implements WordActions {
  final List<String> known = <String>[];
  int undone = 0;

  @override
  Future<Undo> markKnown(String uid, {required String today}) async {
    known.add(uid);
    return () async => undone++;
  }
}

/// W1's data for [uid] as the shipped course has it, so D2's card shows the
/// word's own meaning and step, not the artboard's Straße.
WordDetail courseWordDetail(String uid) {
  final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
  try {
    final row = db.select('SELECT * FROM words WHERE uid = ?', <Object>[
      uid,
    ]).single;
    return WordDetail(
      meanings: const Meanings(MeaningChoice('en', 'bn')),
      pron: null,
      translate: false,
      examples: const <({String german, String? translation})>[],
      word: WordWithState(
        word: Word(
          kind: row['kind'] as String,
          uid: uid,
          sublevelCode: row['sublevel_code'] as String,
          levelCode: row['level_code'] as String,
          seq: row['seq'] as int,
          seqInSublevel: row['seq_in_sublevel'] as int,
          article: row['article'] as String?,
          german: row['german'] as String,
          forms: row['forms'] as String?,
          pos: row['pos'] as String?,
          english: row['english'] as String,
          bangla: row['bangla'] as String?,
          searchKey: row['search_key'] as String,
          searchKeyAlt: row['search_key_alt'] as String,
        ),
        state: null,
        status: WordStatus.todo,
      ),
    );
  } finally {
    db.close();
  }
}

/// D2 without a database, for the widget tests and the goldens.
List<Override> docWordsStub({
  FakeDocuments? documents,
  FakePlan? plan,
  FakeActions? actions,
  StubSettings? settings,
}) => <Override>[
  documentRepositoryProvider.overrideWithValue(documents ?? FakeDocuments()),
  planEngineProvider.overrideWithValue(plan ?? FakePlan()),
  wordActionsProvider.overrideWithValue(actions ?? FakeActions()),
  todayProvider.overrideWithValue('2026-10-02'),
  clockProvider.overrideWithValue(() => DateTime(2026, 10, 2, 9)),
  settingsSourceProvider.overrideWithValue(settings ?? StubSettings()),
  wordDetailProvider.overrideWith(
    (ref, uid) => Stream.value(courseWordDetail(uid)),
  ),
];
