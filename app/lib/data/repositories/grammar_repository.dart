import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show WordStatus;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

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

  /// `grammar-practice.md`: all correct → Good, one wrong → Hard, more →
  /// Again. The mapping lives here because it is the only place that knows
  /// both numbers.
  int get rating {
    final wrong = items - correct;
    if (wrong == 0) return 3;
    return wrong == 1 ? 2 : 1;
  }
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

  double get _doneAfter =>
      _settings.read(SettingKeys.doneStabilityDays).toDouble();

  /// Runs [query] again whenever the learner moves `done_stability_days`.
  ///
  /// The threshold is a query variable, so a stream built once would keep the
  /// value it was built with and every status on an open screen would be
  /// stale until the screen was rebuilt (BR-STATUS-02). [row] is per-query
  /// because drift gives each one its own result class.
  Stream<List<TopicWithState>> _watchTopics<T>(
    Stream<List<T>> Function(double) query,
    TopicWithState Function(T) row,
  ) => _settings
      .switchOn(
        SettingKeys.doneStabilityDays,
        (int days) => query(days.toDouble()),
      )
      .map((rows) => rows.map(row).toList());

  TopicWithState _topic(
    GrammarTopic topic,
    GrammarStateData? state,
    String derivedStatus,
  ) => TopicWithState(
    topic: topic,
    state: state,
    status: WordStatus.parse(derivedStatus),
  );

  /// [watchStep], once.
  Future<List<TopicWithState>> step(String code) async => <TopicWithState>[
    for (final row in await topicsWithStateForStep(
      _settings.read(SettingKeys.doneStabilityDays).toDouble(),
      code,
    ).get())
      _topic(row.g, row.s, row.derivedStatus),
  ];

  Stream<List<TopicWithState>> watchStep(String code) => _watchTopics(
    (days) => topicsWithStateForStep(days, code).watch(),
    (row) => _topic(row.g, row.s, row.derivedStatus),
  );

  /// Every topic of the course, level by level, in teaching order: L3.
  Stream<List<TopicWithState>> watchAll() => _watchTopics(
    (days) => allTopicsWithState(days).watch(),
    (row) => _topic(row.g, row.s, row.derivedStatus),
  );

  /// Everything due on or before [today]. The plan engine's `ensureGrammarDue`
  /// reads this, and Step detail shows the same list.
  Stream<List<TopicWithState>> watchDue(String today) => _watchTopics(
    (days) => dueTopics(days, today).watch(),
    (row) => _topic(row.g, row.s, row.derivedStatus),
  );

  Stream<TopicWithState?> watchTopic(String uid) => _settings
      .switchOn(
        SettingKeys.doneStabilityDays,
        (int days) => topicWithState(days.toDouble(), uid).watch(),
      )
      .map(
        (rows) => rows.isEmpty
            ? null
            : _topic(rows.single.g, rows.single.s, rows.single.derivedStatus),
      );

  Future<TopicWithState?> find(String uid) async {
    final rows = await topicWithState(_doneAfter, uid).get();
    return rows.isEmpty
        ? null
        : _topic(rows.single.g, rows.single.s, rows.single.derivedStatus);
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
  /// an instant, and a study day is a local day.
  Future<void> recordPractice({
    required String uid,
    required PracticeResult result,
    required double stability,
    required double difficulty,
    required String due,
    required int reps,
    required int lapses,
    required String today,
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

    await into(db.grammarState).insertOnConflictUpdate(
      GrammarStateCompanion.insert(
        grammarUid: uid,
        // Suspension survives a practice run: the learner suspended the
        // topic, and finishing a run they started does not un-suspend it.
        status: Value(
          before?.status == WordStatus.suspended.wire
              ? WordStatus.suspended.wire
              : _statusFor(stability),
        ),
        due: Value(due),
        stability: Value(stability),
        difficulty: Value(difficulty),
        reps: Value(reps),
        lapses: Value(lapses),
        lastReview: Value(result.practisedAt),
      ),
    );

    // One statement rather than read-then-write, the same way `PlanRepository`
    // bumps its counters: two runs finishing in the same millisecond would
    // otherwise each read the same total and one would be lost.
    await db.customStatement(
      'INSERT INTO daily_stats (day, grammar_done) VALUES (?, 1) '
      'ON CONFLICT(day) DO UPDATE SET grammar_done = grammar_done + 1',
      <Object?>[today],
    );
    // A raw statement, so drift has to be told which streams to re-emit.
    db.markTablesUpdated(<TableInfo<Table, Object?>>{db.dailyStats});
  });

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
          : WordStatus.parse(_statusFor(state.stability)),
    );
  }

  String _statusFor(double stability) =>
      stability >= _doneAfter ? WordStatus.done.wire : WordStatus.learning.wire;

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
