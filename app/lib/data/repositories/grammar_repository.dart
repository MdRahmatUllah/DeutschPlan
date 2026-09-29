import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart'
    show WordStatus, statusForStability;
import 'package:sogda/domain/grammar_item_generator.dart';

part 'grammar_repository.g.dart';

/// A grammar topic and how the learner is doing with it.
@immutable
class TopicWithState {
  const TopicWithState({
    required this.topic,
    required this.state,
    required this.status,
  });

  final GrammarTopic topic;
  final GrammarStateData? state;

  /// Derived in SQL against `done_stability_days`, for the same reason words
  /// are: the threshold is a setting the learner moves, and a cached status
  /// would stay a practice run behind.
  final WordStatus status;

  String get uid => topic.uid;

  /// The tags the item generator reads to decide which item types apply
  /// (`grammar-practice.md`). Every topic carries gap-fill and pick-the-form.
  List<String> get tags => topic.tags.split(',');
}

/// #1081: a grammar topic's text in one meaning language
/// (`grammar_translations`).
typedef GrammarText = ({
  String topic,
  String? rule,
  String? example,
  String? watchOut,
});

/// How one practice run went, as it goes into `grammar_practice_log`.
@immutable
class PracticeResult {
  const PracticeResult({
    required this.items,
    required this.correct,
    required this.practisedAt,
  });

  final int items;
  final int correct;
  final String practisedAt;

  /// `grammar-practice.md`'s rating (BR-FSRS-05), as the generator states
  /// it.
  int get rating => practiceRating(items: items, correct: correct);
}

/// Grammar topics, their scheduling and their practice history.
///
/// BR-FSRS-05 gives grammar the same FSRS fields as words, so the shape here
/// mirrors `WordRepository` — including that the scheduling maths is computed
/// in pure Dart and handed over rather than done here.
@DriftAccessor(include: <String>{'../db/grammar_queries.drift'})
class GrammarRepository extends DatabaseAccessor<AppDatabase>
    with _$GrammarRepositoryMixin {
  GrammarRepository(super.db, this._settings);

  final SettingsRepository _settings;

  /// #1081: the primary meaning language, which the topics read in.
  String get _lang => meaningChoiceOf(_settings).primary;

  double get _doneAfter =>
      _settings.read(SettingKeys.doneStabilityDays).toDouble();

  /// What the topic queries read: `done_stability_days`, and the primary
  /// meaning language (#1081).
  static const Set<SettingKey<Object?>> _read = <SettingKey<Object?>>{
    SettingKeys.doneStabilityDays,
    SettingKeys.meaningLanguage,
    SettingKeys.meaningPrimary,
  };

  /// Runs [query] again whenever the learner moves `done_stability_days` or
  /// the primary meaning language.
  ///
  /// Both are query variables, so a stream built once would keep the values
  /// it was built with and every status on an open screen would be stale
  /// until the screen was rebuilt (BR-STATUS-02). [row] is per-query
  /// because drift gives each one its own result class.
  Stream<List<TopicWithState>> _watchTopics<T>(
    Stream<List<T>> Function(double, String) query,
    TopicWithState Function(T) row,
  ) => _settings
      .switchOnAny(_read, () => query(_doneAfter, _lang))
      .map((rows) => rows.map(row).toList());

  /// [topic] in the primary meaning language where the course has it
  /// ([text]); English, the course's own, where it has none.
  TopicWithState _topic(
    GrammarTopic topic,
    GrammarStateData? state,
    String derivedStatus,
    GrammarText? text,
  ) => TopicWithState(
    topic: text == null
        ? topic
        : topic.copyWith(
            topic: text.topic,
            rule: Value<String?>(text.rule ?? topic.rule),
            exampleEn: Value<String?>(text.example ?? topic.exampleEn),
            watchOut: Value<String?>(text.watchOut ?? topic.watchOut),
          ),
    state: state,
    status: WordStatus.parse(derivedStatus),
  );

  static GrammarText? _text(
    String? topic,
    String? rule,
    String? example,
    String? watchOut,
  ) => topic == null
      ? null
      : (topic: topic, rule: rule, example: example, watchOut: watchOut);

  /// [watchStep], once.
  Future<List<TopicWithState>> step(String code) async => <TopicWithState>[
    for (final row in await topicsWithStateForStep(
      _doneAfter,
      _lang,
      code,
    ).get())
      _topic(
        row.g,
        row.s,
        row.derivedStatus,
        _text(row.trTopic, row.trRule, row.trExample, row.trWatchOut),
      ),
  ];

  Stream<List<TopicWithState>> watchStep(String code) => _watchTopics(
    (days, lang) => topicsWithStateForStep(days, lang, code).watch(),
    (row) => _topic(
      row.g,
      row.s,
      row.derivedStatus,
      _text(row.trTopic, row.trRule, row.trExample, row.trWatchOut),
    ),
  );

  /// Every topic of the course, level by level, in teaching order: L3.
  Stream<List<TopicWithState>> watchAll() => _watchTopics(
    (days, lang) => allTopicsWithState(days, lang).watch(),
    (row) => _topic(
      row.g,
      row.s,
      row.derivedStatus,
      _text(row.trTopic, row.trRule, row.trExample, row.trWatchOut),
    ),
  );

  /// Everything due on or before [today]. The plan engine's `ensureGrammarDue`
  /// reads this, and Step detail shows the same list.
  Stream<List<TopicWithState>> watchDue(String today) => _watchTopics(
    (days, lang) => dueTopics(days, lang, today).watch(),
    (row) => _topic(
      row.g,
      row.s,
      row.derivedStatus,
      _text(row.trTopic, row.trRule, row.trExample, row.trWatchOut),
    ),
  );

  Stream<TopicWithState?> watchTopic(String uid) => _settings
      .switchOnAny(_read, () => topicWithState(_doneAfter, _lang, uid).watch())
      .map(
        (rows) => rows.isEmpty
            ? null
            : _topic(
                rows.single.g,
                rows.single.s,
                rows.single.derivedStatus,
                _text(
                  rows.single.trTopic,
                  rows.single.trRule,
                  rows.single.trExample,
                  rows.single.trWatchOut,
                ),
              ),
      );

  Future<TopicWithState?> find(String uid) async {
    final rows = await topicWithState(_doneAfter, _lang, uid).get();
    return rows.isEmpty
        ? null
        : _topic(
            rows.single.g,
            rows.single.s,
            rows.single.derivedStatus,
            _text(
              rows.single.trTopic,
              rows.single.trRule,
              rows.single.trExample,
              rows.single.trWatchOut,
            ),
          );
  }

  Stream<List<GrammarPracticeLogData>> watchPractice(
    String uid, {
    int limit = 5,
  }) => practiceFor(uid, limit).watch();

  /// Records one practice run: the log entry, the new scheduling and the day's
  /// total, together.
  ///
  /// One transaction, for the same reason a rating is: a run that logged but
  /// did not reschedule would show in the history and never come round again,
  /// and the learner would have no way to tell.
  ///
  /// [reps] and [lapses] both come from the caller's FSRS card. Deriving
  /// either here would let the stored value drift from the card's — and the
  /// stored one is what the next review reads back.
  ///
  /// [today] is the local study day, not [PracticeResult.practisedAt]: that is
  /// an instant, and a study day is a local day. [seconds] is the run's time
  /// on screen, added to the day's study time as a card's is (#785).
  Future<void> recordPractice({
    required String uid,
    required PracticeResult result,
    required double stability,
    required double difficulty,
    required String due,
    required int reps,
    required int lapses,
    required String today,
    int seconds = 0,
  }) => db.transaction(() async {
    final before = await (select(
      db.grammarState,
    )..where((t) => t.grammarUid.equals(uid))).getSingleOrNull();

    await into(db.grammarPracticeLog).insert(
      GrammarPracticeLogCompanion.insert(
        grammarUid: uid,
        practisedAt: result.practisedAt,
        items: result.items,
        correct: result.correct,
      ),
    );

    await _writeState(
      uid: uid,
      suspended: before?.status == WordStatus.suspended.wire,
      stability: stability,
      difficulty: difficulty,
      due: due,
      reps: reps,
      lapses: lapses,
      lastReview: result.practisedAt,
    );

    // One statement rather than read-then-write, the same way `PlanRepository`
    // bumps its counters: two runs finishing in the same millisecond would
    // otherwise each read the same total and one would be lost.
    await db.customStatement(
      'INSERT INTO daily_stats (day, grammar_done, seconds) VALUES (?, 1, ?) '
      'ON CONFLICT(day) DO UPDATE SET grammar_done = grammar_done + 1, '
      'seconds = seconds + excluded.seconds',
      <Object?>[today, seconds],
    );
    // A raw statement, so drift has to be told which streams to re-emit.
    db.markTablesUpdated(<TableInfo<Table, Object?>>{db.dailyStats});
  });

  /// FR-L4-01: a topic scheduled without a practice run — *Mark as
  /// learned*. No log row and no `grammar_done`: nothing was practised.
  Future<void> schedule({
    required String uid,
    required double stability,
    required double difficulty,
    required String due,
    required int reps,
    required int lapses,
    required String lastReview,
  }) => db.transaction(() async {
    final before = await (select(
      db.grammarState,
    )..where((t) => t.grammarUid.equals(uid))).getSingleOrNull();
    await _writeState(
      uid: uid,
      suspended: before?.status == WordStatus.suspended.wire,
      stability: stability,
      difficulty: difficulty,
      due: due,
      reps: reps,
      lapses: lapses,
      lastReview: lastReview,
    );
  });

  /// The scheduling a rating leaves. Suspension survives it: the learner
  /// suspended the topic, and finishing a run they started does not
  /// un-suspend it.
  Future<void> _writeState({
    required String uid,
    required bool suspended,
    required double stability,
    required double difficulty,
    required String due,
    required int reps,
    required int lapses,
    required String lastReview,
  }) => into(db.grammarState).insertOnConflictUpdate(
    GrammarStateCompanion.insert(
      grammarUid: uid,
      status: Value(
        (suspended ? WordStatus.suspended : _statusFor(stability)).wire,
      ),
      due: Value(due),
      stability: Value(stability),
      difficulty: Value(difficulty),
      reps: Value(reps),
      lapses: Value(lapses),
      lastReview: Value(lastReview),
    ),
  );

  Future<void> suspend(String uid) => _setStatus(uid, WordStatus.suspended);

  /// Resumes a topic, deriving the status from its stability rather than
  /// remembering the one it had — the same rule words follow.
  Future<void> resume(String uid) async {
    final state = await (select(
      db.grammarState,
    )..where((t) => t.grammarUid.equals(uid))).getSingleOrNull();

    await _setStatus(
      uid,
      state == null || state.lastReview == null
          ? WordStatus.todo
          : _statusFor(state.stability),
    );
  }

  WordStatus _statusFor(double stability) => statusForStability(
    stability,
    _settings.read(SettingKeys.doneStabilityDays),
  );

  /// Upsert, not update: a topic nobody has practised has no row, and Step
  /// detail offers *Suspend* on those too.
  Future<void> _setStatus(String uid, WordStatus status) =>
      into(db.grammarState).insertOnConflictUpdate(
        GrammarStateCompanion.insert(
          grammarUid: uid,
          status: Value(status.wire),
        ),
      );
}
