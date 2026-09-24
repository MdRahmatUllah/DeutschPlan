import 'package:deutschplan/features/sentences/sentences_screen.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/backlog/backlog_screen.dart';
import 'package:deutschplan/features/learn/grammar_library_screen.dart';
import 'package:deutschplan/features/learn/step_grammar.dart';
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The Today artboard's values: 12 of 20 done, A2.1, day 34, a backlog from
/// Tuesday to Wednesday and Konjunktiv II this week.
TodayView artboardToday({
  int reviseDone = 10,
  int newDone = 2,
  int backlog = 14,
  int grammarDue = 0,
  int sentencesDone = 0,
  bool isStudyDay = true,
  int courseDay = 34,
  String? learnerName = 'Maruf',
  ContextualOffer? contextual,
}) => TodayView(
  date: '2026-09-21',
  hour: 8,
  revise: BlockProgress(done: reviseDone, total: 10),
  newToday: BlockProgress(done: newDone, total: 7),
  openRevise: <String>[for (var i = reviseDone; i < 10; i++) 'r$i'],
  openNew: <String>[for (var i = newDone; i < 7; i++) 'n$i'],
  grammarDue: <String>[for (var i = 0; i < grammarDue; i++) 'g$i'],
  sentences: BlockProgress(done: sentencesDone, total: 3),
  isStudyDay: isStudyDay,
  contextual: contextual,
  backlog: backlog,
  backlogFrom: backlog == 0 ? null : '2026-09-15',
  backlogTo: backlog == 0 ? null : '2026-09-16',
  streak: 12,
  estimate: const Duration(minutes: 6),
  courseDay: courseDay,
  stepWords: (done: 184, learning: 60, todo: 296, total: 540),
  step: 'A2.1',
  learnerName: learnerName,
  newCategory: 'Wohnen & Haushalt',
  grammar: const GrammarPreview(
    uid: 'konj2',
    topic: 'Konjunktiv II – Höflichkeit',
    rule: 'Könnten Sie …? — polite requests with könnte and würde',
  ),
);

/// The TodayDone artboard: 20 of 20, day 34 · 17 words · 12 min, and a
/// Tomorrow of 12 revisions, 7 new and one grammar topic.
TodayView artboardDone({int backlog = 0, TomorrowPreview? tomorrow}) =>
    TodayView(
      date: '2026-09-21',
      hour: 19,
      revise: const BlockProgress(done: 10, total: 10),
      newToday: const BlockProgress(done: 7, total: 7),
      openRevise: const <String>[],
      openNew: const <String>[],
      grammarDue: const <String>[],
      sentences: const BlockProgress(done: 3, total: 3),
      backlog: backlog,
      streak: 13,
      estimate: Duration.zero,
      courseDay: 34,
      minutes: 12,
      stepWords: (done: 191, learning: 60, todo: 289, total: 540),
      step: 'A2.1',
      learnerName: 'Maruf',
      grammar: const GrammarPreview(
        uid: 'konj2',
        topic: 'Konjunktiv II – Höflichkeit',
        rule: 'Könnten Sie …? — polite requests with könnte and würde',
      ),
      tomorrow:
          tomorrow ??
          const TomorrowPreview(
            revise: 12,
            newWords: 7,
            grammar: 1,
            estimate: Duration(minutes: 13),
            category: 'Wohnen & Haushalt',
          ),
    );

/// The TodayRest artboard: Sunday the 27th off, six revisions optional, and
/// twelve due tomorrow if they are left alone.
TodayView artboardRest({int reviseDone = 0}) => TodayView(
  date: '2026-09-27',
  hour: 10,
  revise: BlockProgress(done: reviseDone, total: 6),
  newToday: BlockProgress.none,
  openRevise: <String>[for (var i = reviseDone; i < 6; i++) 'r$i'],
  openNew: const <String>[],
  grammarDue: const <String>[],
  sentences: const BlockProgress(done: 0, total: 3),
  isStudyDay: false,
  backlog: 0,
  streak: 12,
  estimate: const Duration(minutes: 3),
  courseDay: 40,
  stepWords: (done: 191, learning: 60, todo: 289, total: 540),
  step: 'A2.1',
  learnerName: 'Maruf',
  dueTomorrow: 12,
  grammar: const GrammarPreview(
    uid: 'konj2',
    topic: 'Konjunktiv II – Höflichkeit',
    rule: 'Könnten Sie …? — polite requests with könnte and würde',
  ),
);

/// The Learn artboard's course: A1.1 and A1.2 passed, A2.1 current with
/// 184 done, 60 learning and 296 to do, and everything after it not started.
List<StepProgress> artboardCourse({
  String active = 'A2.1',
  Set<String> passed = const <String>{'A1.1', 'A1.2'},
}) {
  const shape = <(String, String, int, int)>[
    ('A1.1', 'A1', 480, 14),
    ('A1.2', 'A1', 470, 12),
    ('A2.1', 'A2', 540, 10),
    ('A2.2', 'A2', 520, 11),
    ('B1.1', 'B1', 460, 16),
    ('B1.2', 'B1', 440, 16),
    ('B2.1', 'B2', 520, 18),
    ('B2.2', 'B2', 500, 18),
    ('C1.1', 'C1', 430, 17),
    ('C1.2', 'C1', 420, 17),
    ('C2.1', 'C2', 410, 16),
    ('C2.2', 'C2', 404, 17),
  ];
  return <StepProgress>[
    for (final (code, level, words, grammar) in shape)
      StepProgress(
        code: code,
        levelCode: level,
        words: words,
        todo: code == 'A2.1' ? 296 : (passed.contains(code) ? 0 : words),
        learning: code == 'A2.1' ? 60 : 0,
        done: code == 'A2.1' ? 184 : (passed.contains(code) ? words : 0),
        grammar: grammar,
        grammarLearned: code == 'A2.1'
            ? 4
            : (passed.contains(code) ? grammar : 0),
        unlocked: passed.contains(code),
        passedSeed: passed.contains(code) ? 1 : null,
        // A1.2 completed on 18 Aug and A2.1 started the day after, as the
        // artboards date them.
        startedOn: code == active
            ? '2026-08-19'
            : (passed.contains(code) ? '2026-07-01' : null),
        completedOn: passed.contains(code) ? '2026-08-18' : null,
        dailyNew: 7,
        studyDaysMask: 127,
      ),
  ];
}

/// The StepDetail artboard's rows: Rechnung and Vermieter done, Mietvertrag
/// and Nebenkosten learning, Kaution and umziehen to do, all Wohnen &
/// Haushalt but umziehen.
List<StepWord> artboardWords() {
  const rows = <(String?, String, String, WordStatus)>[
    ('die', 'Rechnung', 'bill, invoice', WordStatus.done),
    ('der', 'Mietvertrag', 'rental contract, lease', WordStatus.learning),
    (
      'die',
      'Nebenkosten',
      'utility costs, service charges',
      WordStatus.learning,
    ),
    ('der', 'Vermieter', 'landlord', WordStatus.done),
    ('die', 'Kaution', 'deposit', WordStatus.todo),
    (null, 'umziehen', 'to move (house)', WordStatus.todo),
  ];
  return <StepWord>[
    for (final (i, (article, german, english, status)) in rows.indexed)
      (
        meaning: english,
        word: WordWithState(
          word: Word(
            uid: 'a21-$i',
            sublevelCode: 'A2.1',
            levelCode: 'A2',
            seq: i,
            seqInSublevel: i,
            article: article,
            german: german,
            english: english,
            categoryId: article == null ? null : 1,
            searchKey: german.toLowerCase(),
            searchKeyAlt: german.toLowerCase(),
          ),
          state: null,
          status: status,
        ),
      ),
  ];
}

/// The StepGrammar artboard's ten topics on 21 September: two learned and
/// coming round in 4 and 9 days, two due today, six not learned yet.
List<TopicWithState> artboardTopics() {
  const rows = <(String, String, String?)>[
    (
      'Modalverben im Präteritum',
      'konnte, musste, wollte — no umlaut, no ge-',
      '2026-09-25',
    ),
    ('Nebensätze mit weil', 'weil sends the verb to the end', '2026-09-30'),
    (
      'Perfekt mit sein',
      'Movement and change: sein + Partizip II',
      '2026-09-21',
    ),
    (
      'Konjunktiv II – Höflichkeit',
      'könnte / würde + infinitive',
      '2026-09-19',
    ),
    ('Dativ nach Präpositionen', 'aus, bei, mit, nach, seit, von, zu', null),
    ('Reflexive Verben', 'sich freuen, sich waschen', null),
    ('Komparativ und Superlativ', 'schneller, am schnellsten', null),
    ('Wechselpräpositionen', 'in, an, auf: wohin takes the accusative', null),
    ('Relativsätze', 'der, die, das as relative pronouns', null),
    ('Genitiv', 'des Mannes, der Frau — wegen, trotz', null),
  ];
  return <TopicWithState>[
    for (final (i, (title, rule, due)) in rows.indexed)
      TopicWithState(
        topic: GrammarTopic(
          uid: 'g$i',
          sublevelCode: 'A2.1',
          levelCode: 'A2',
          seq: i,
          topic: title,
          rule: rule,
          tags: 'gap-fill,pick-the-form',
        ),
        state: due == null
            ? null
            : GrammarStateData(
                grammarUid: 'g$i',
                status: 'learning',
                due: due,
                stability: 4,
                difficulty: 5,
                reps: 2,
                lapses: 0,
              ),
        status: due == null ? WordStatus.todo : WordStatus.learning,
      ),
  ];
}

/// The GrammarLibrary artboard: 182 topics, 145 not learned yet and 2 due
/// on 21 September. A1 and A2 are the artboard's rows; B1 starts with its
/// two, and the rest of the course fills in below the fold.
List<TopicWithState> artboardLibrary() {
  // (step, title, due date or null for not learned)
  final rows = <(String, String, String?)>[
    ('A1.1', 'Präsens: regelmäßige Verben', '2026-10-02'),
    ('A1.1', 'Artikel und Genus', '2026-10-05'),
    ('A1.2', 'Perfekt mit haben', '2026-09-28'),
    ('A2.1', 'Modalverben im Präteritum', '2026-09-25'),
    ('A2.1', 'Konjunktiv II – Höflichkeit', '2026-09-21'),
    ('A2.1', 'Dativ nach Präpositionen', null),
    ('A2.2', 'Relativsätze im Nominativ', null),
    ('B1.1', 'Passiv Präsens', null),
    ('B1.1', 'Genitiv', null),
  ];
  // 173 more: 31 scheduled and one due among them, the rest not learned.
  const steps = <String>[
    'B1.2',
    'B2.1',
    'B2.2',
    'C1.1',
    'C1.2',
    'C2.1',
    'C2.2',
  ];
  for (var i = 0; i < 173; i++) {
    rows.add((
      steps[i * steps.length ~/ 173],
      'Topic ${i + 10}',
      i < 31
          ? '2026-11-01'
          : i == 31
          ? '2026-09-20'
          : null,
    ));
  }
  return <TopicWithState>[
    for (final (i, (step, title, due)) in rows.indexed)
      TopicWithState(
        topic: GrammarTopic(
          uid: 'lib$i',
          sublevelCode: step,
          levelCode: step.split('.').first,
          seq: i,
          topic: title,
          tags: 'gap-fill,pick-the-form',
        ),
        state: due == null
            ? null
            : GrammarStateData(
                grammarUid: 'lib$i',
                status: 'learning',
                due: due,
                stability: 4,
                difficulty: 5,
                reps: 2,
                lapses: 0,
              ),
        status: due == null ? WordStatus.todo : WordStatus.learning,
      ),
  ];
}

/// Today without a database: the artboard's plan, and no coach mark.
///
/// For tests about something else — the router, the shell — that only need
/// the first tab to draw.
List<Override> todayStub([
  TodayView? view,
  List<StepProgress>? course,
  Duration? dayAfter,
]) => <Override>[
  todayViewProvider.overrideWith((ref) async {
    // A day that arrives after the rest of the screen, as a slow plan does.
    if (dayAfter != null) await Future<void>.delayed(dayAfter);
    return view ?? artboardToday();
  }),
  coachMarkProvider.overrideWithValue(false),
  // T4 without a database: twenty rows, enough to scroll.
  backlogProvider.overrideWith(StubBacklog.new),
  backlogPauseProvider.overrideWith(_StubPause.new),
  // T5 without a database: nothing to practise.
  practiceSentencesProvider.overrideWith(_StubSentences.new),
  // L2's Words tab without a database: the StepDetail artboard's six.
  stepWordsProvider.overrideWith((ref, code) => Stream.value(artboardWords())),
  stepCategoriesProvider.overrideWith(
    (ref, code) async => const <({int id, String name})>[
      (id: 1, name: 'Wohnen & Haushalt'),
    ],
  ),
  // The artboards' Monday, so a due date reads the same on any day the
  // tests run.
  todayProvider.overrideWithValue('2026-09-21'),
  // L2's Grammar tab without a database: the StepGrammar artboard's ten.
  stepTopicsProvider.overrideWith(
    (ref, code) => Stream.value(artboardTopics()),
  ),
  // L2's Quiz tab without a database: the QuizSetup artboard's last quiz.
  lastStepQuizProvider.overrideWith(
    (ref, code) => Stream.value((
      score: 16,
      outOf: 20,
      length: 20,
      direction: 'deEn',
      finishedAt: '2026-09-20T19:05:00',
    )),
  ),
  // L3 without a database: the GrammarLibrary artboard's 182.
  libraryTopicsProvider.overrideWith((ref) => Stream.value(artboardLibrary())),
  // L1 without a database: the Learn artboard's course.
  stepProgressProvider.overrideWith(
    (ref) => Stream.value(course ?? artboardCourse()),
  ),
];

class _StubSentences extends PracticeSentences {
  @override
  Future<List<PracticeSentence>> build() async => const <PracticeSentence>[];
}

/// Twenty backlog words over two days: "das Wort0" … "das Wort19".
class StubBacklog extends Backlog {
  @override
  Stream<List<BacklogWord>> build() => Stream.value(<BacklogWord>[
    for (var i = 0; i < 20; i++)
      (
        planDate: i < 10 ? '2026-09-16' : '2026-09-15',
        meaning: 'word $i',
        word: WordWithState(
          word: Word(
            uid: 'w$i',
            sublevelCode: 'A1.1',
            levelCode: 'A1',
            seq: i,
            seqInSublevel: i,
            article: 'das',
            german: 'Wort$i',
            english: 'word $i',
            searchKey: 'wort$i',
            searchKeyAlt: 'wort$i',
          ),
          state: null,
          status: WordStatus.todo,
        ),
      ),
  ]);
}

class _StubPause extends BacklogPause {
  @override
  bool build() => false;
}
