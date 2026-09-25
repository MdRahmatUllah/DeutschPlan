import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/domain/fsrs.dart' show Rating;
import 'package:deutschplan/domain/plan_engine.dart' show planDate;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

part 'word_repository.g.dart';

/// The four statuses `BR-STATUS-01` names.
///
/// Stored as text in `word_state.status`, with a CHECK that rejects anything
/// else — so this enum and the database agree by construction rather than by
/// convention.
enum WordStatus {
  /// Never introduced. A word with no `word_state` row at all is this.
  todo,

  /// Introduced, still being reviewed.
  learning,

  /// FSRS stability has reached `done_stability_days`. **Derived**
  /// (BR-STATUS-02) — a lapse moves it back to [learning].
  done,

  /// Paused by the learner. Excluded from everything (BR-STATUS-03), and the
  /// FSRS state is kept so resuming picks up where it left off.
  suspended;

  static WordStatus parse(String? value) => switch (value) {
    'learning' => WordStatus.learning,
    'done' => WordStatus.done,
    'suspended' => WordStatus.suspended,
    _ => WordStatus.todo,
  };

  String get wire => name;
}

/// How often a word was reviewed and how it was last rated; `last` is null
/// for a word never reviewed.
typedef ReviewHistory = ({int reviews, Rating? last});

/// A word and what the learner has done with it.
@immutable
class WordWithState {
  const WordWithState({
    required this.word,
    required this.state,
    required this.status,
  });

  final Word word;
  final WordStateData? state;

  /// Derived in SQL against the learner's `done_stability_days`, not read
  /// from `word_state.status` — that column is a cache, and a threshold the
  /// learner just moved would leave it a rating behind (BR-STATUS-02).
  final WordStatus status;

  String get uid => word.uid;

  bool get isSuspended => status == WordStatus.suspended;
}

/// One category's card on L5 (FR-L5-01): its words, suspended ones
/// included, and the bar's split.
@immutable
class CategoryProgress {
  const CategoryProgress({
    required this.id,
    required this.name,
    required this.words,
    required this.todo,
    required this.learning,
    required this.done,
  });

  final int id;
  final String name;
  final int words;
  final int todo;
  final int learning;
  final int done;
}

/// One step of the course and how far the learner is through it: L1's tile
/// and the Me card's share (FR-L1-01, FR-M1-01).
@immutable
class StepProgress {
  const StepProgress({
    required this.code,
    required this.levelCode,
    required this.words,
    required this.todo,
    required this.learning,
    required this.done,
    required this.grammar,
    required this.grammarLearned,
    required this.unlocked,
    required this.dailyNew,
    required this.studyDaysMask,
    this.passedSeed,
    this.startedOn,
    this.completedOn,
  });

  final String code;
  final String levelCode;

  /// Every word of the step, suspended ones included.
  final int words;
  final int todo;
  final int learning;
  final int done;
  final int grammar;

  /// Topics whose `grammar_state` is learning or done.
  final int grammarLearned;

  /// BR-EXAM-01: introduced >= `exam_unlock_percent` of the step's words.
  final bool unlocked;

  /// The first mock passed, by when: "Mock 1 passed" (BR-EXAM-04).
  final int? passedSeed;

  /// The step's enrollment, if it has one.
  final String? startedOn;
  final String? completedOn;

  /// The step's pace: frozen at enrollment (BR-PLAN-08), or today's
  /// settings for a step not yet started.
  final int dailyNew;
  final int studyDaysMask;

  /// BR-EXAM-04: any finished mock of the step passed.
  bool get passed => passedSeed != null;

  /// BR-COURSE-04: the one open enrollment.
  bool get active => startedOn != null && completedOn == null;

  /// Met at least once.
  int get introduced => learning + done;

  /// BR-EXAM-01's target: [percent] of the words, suspended ones left out
  /// as the bar leaves them out, rounded up.
  static int unlockTarget({
    required int todo,
    required int introduced,
    required int percent,
  }) => ((todo + introduced) * percent + 99) ~/ 100;

  /// BR-EXAM-01 for [percent]: [unlockTarget] introduced.
  static bool unlocks({
    required int todo,
    required int introduced,
    required int percent,
  }) =>
      todo + introduced > 0 &&
      introduced >=
          unlockTarget(todo: todo, introduced: introduced, percent: percent);
}

/// One of the learner's own words where a course word's uid goes:
/// `word_state`, `plan_items` and `review_log` (FR-R2-03, #363).
String customUid(int id) => 'custom:$id';

/// The `custom_words` id in [uid], or null for a course word.
int? customId(String uid) =>
    uid.startsWith('custom:') ? int.tryParse(uid.substring(7)) : null;

/// A word of the learner's own as R2 edits it (#143).
typedef MyWordDraft = ({
  String? article,
  String german,
  String meaning,
  String? whereSeen,
  String? example,
});

/// One of the learner's own words (`custom_words`), as R1's *My words* shows
/// it.
typedef MyWord = ({
  int id,
  String? article,
  String german,
  String meaning,
  String? whereSeen,
  int timesSeen,
});

/// Words, their state, and the transitions between statuses.
///
/// `docs/02-data/user-database.md` and `docs/04-screens/word-detail.md`.
///
/// Everything that reads for *learning* excludes suspended words. That is
/// BR-STATUS-03, and it is enforced in the SQL rather than by each caller
/// remembering — a plan that quietly included a suspended word would look like
/// the suspension never took.
///
/// **Every write goes through drift's API**, never `customStatement`. drift
/// works out which streams to re-emit from the tables a typed write touches;
/// a raw statement changes the same rows and tells it nothing, so Today and
/// the step list would keep showing the old numbers until something else
/// happened to invalidate them. That is the acceptance criterion about "no
/// manual invalidation", and it only holds if nothing writes behind drift's
/// back.
@DriftAccessor(include: <String>{'../db/word_queries.drift'})
class WordRepository extends DatabaseAccessor<AppDatabase>
    with _$WordRepositoryMixin {
  WordRepository(super.db, this._settings);

  final SettingsRepository _settings;

  /// `done_stability_days`, read on every query rather than cached.
  ///
  /// It is a Settings row the learner moves, and the derivation happens in
  /// SQL — so the value has to come from here each time or the lists would
  /// answer with the threshold that was current when this object was built.
  /// A double because it is compared against `stability`, which is REAL.
  double get _doneAfter =>
      _settings.read(SettingKeys.doneStabilityDays).toDouble();

  /// Runs [query] again whenever the learner moves `done_stability_days`.
  ///
  /// The threshold is a query variable, so a stream built once would keep the
  /// value it was built with and every status on an open screen would be
  /// stale until the screen was rebuilt (BR-STATUS-02). [row] is per-query
  /// because drift gives each one its own result class.
  Stream<List<WordWithState>> _watchWords<T>(
    Stream<List<T>> Function(double) query,
    WordWithState Function(T) row,
  ) => _settings
      .switchOn(
        SettingKeys.doneStabilityDays,
        (int days) => query(days.toDouble()),
      )
      .map((rows) => rows.map(row).toList());

  WordWithState _word(Word word, WordStateData? state, String derivedStatus) =>
      WordWithState(
        word: word,
        state: state,
        status: WordStatus.parse(derivedStatus),
      );

  /// Every word of a step, suspended ones included — the Words tab shows them
  /// greyed rather than hiding them.
  Stream<List<WordWithState>> watchStep(String code) => _watchWords(
    (days) => wordsWithStateForStep(days, code).watch(),
    (row) => _word(row.w, row.s, row.derivedStatus),
  );

  /// R2's edit mode (#143): one of the learner's own words, or null once it
  /// has gone.
  Future<MyWordDraft?> myWord(int id) async {
    final row = await (select(
      db.customWords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : (
            article: row.article,
            german: row.german,
            meaning: row.meaning,
            whereSeen: row.whereSeen,
            example: row.example,
          );
  }

  /// FR-R2-03 *Save*: a new word of the learner's own, or [id]'s changed.
  /// [matchedUid] is the course word it turned out to be, if any. With
  /// [reviseFrom], *Save and add to revision*: [addMyWordToRevision] from
  /// that day, in the same transaction, so a failure saves nothing. Returns
  /// the word's id.
  Future<int> saveMyWord(
    MyWordDraft word, {
    required DateTime now,
    int? id,
    String? matchedUid,
    String? reviseFrom,
  }) => transaction(() async {
    String? blank(String? text) =>
        text == null || text.trim().isEmpty ? null : text.trim();
    final fields = CustomWordsCompanion(
      article: Value(word.article),
      german: Value(word.german.trim()),
      meaning: Value(word.meaning.trim()),
      whereSeen: Value(blank(word.whereSeen)),
      example: Value(blank(word.example)),
      matchedUid: Value(matchedUid),
    );
    final saved =
        id ??
        await into(db.customWords).insert(
          fields.copyWith(createdAt: Value(now.toUtc().toIso8601String())),
        );
    if (id != null) {
      await (update(
        db.customWords,
      )..where((t) => t.id.equals(id))).write(fields);
    }
    if (reviseFrom != null) {
      await addMyWordToRevision(saved, today: reviseFrom);
    }
    return saved;
  });

  /// R2's *Delete* (edit mode): the word and its schedule, which is its
  /// `word_state` and its open plan rows (#363). Its reviews stay in
  /// `review_log` and the done rows, as the days' history.
  Future<void> deleteMyWord(int id) => transaction(() async {
    final uid = customUid(id);
    await (delete(db.customWords)..where((t) => t.id.equals(id))).go();
    await (delete(db.wordState)..where((t) => t.wordUid.equals(uid))).go();
    await (delete(
      db.planItems,
    )..where((t) => t.wordUid.equals(uid) & t.completedAt.isNull())).go();
  });

  /// FR-R2-03 *Save and add to revision* (#363): [id] scheduled as any word
  /// is, keyed `custom:<id>`, introduced and due [today]. If today's plan is
  /// already open, the word joins today's Revise block in the step being
  /// studied, or the last one started, as `DriftPlanStore.addToPlan` files
  /// it. If not, the plan picks it up, due, when it opens the day. A row
  /// there first is kept: an already scheduled word is left as it is.
  Future<void> addMyWordToRevision(int id, {required String today}) =>
      transaction(() async {
        final uid = customUid(id);
        if (await _hasState(uid)) return;
        await into(db.wordState).insert(
          WordStateCompanion.insert(
            wordUid: uid,
            status: const Value('learning'),
            introducedOn: Value(today),
            due: Value(today),
          ),
        );
        // Before the day is opened, a row here would count as its revisions
        // picked (BR-PLAN-04), and the day would get no others.
        final planned = _settings.read(SettingKeys.lastPlannedDate);
        if (planned == null || planDate(planned).compareTo(today) < 0) return;
        final step =
            await (select(db.enrollments)
                  ..orderBy([
                    (e) => OrderingTerm.desc(e.completedOn.isNull()),
                    (e) => OrderingTerm.desc(e.startedOn),
                  ])
                  ..limit(1))
                .getSingleOrNull();
        if (step == null) return;
        await into(db.planItems).insert(
          PlanItemsCompanion.insert(
            planDate: today,
            wordUid: uid,
            kind: 'revise',
            sublevelCode: step.sublevelCode,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });

  /// Whether [id] is scheduled: R2 offers *Save and add to revision* until it
  /// is.
  Future<bool> isMyWordInRevision(int id) => _hasState(customUid(id));

  Future<bool> _hasState(String uid) async =>
      await (select(
        db.wordState,
      )..where((t) => t.wordUid.equals(uid))).getSingleOrNull() !=
      null;

  /// FR-R2-02 *Log it*: one more real-life sighting of a course word, on its
  /// `word_state` row. A word never met gets one, as To do: logging it isn't
  /// studying it.
  Future<void> logSighting(String uid) => into(db.wordState).insert(
    WordStateCompanion.insert(wordUid: uid, timesLogged: const Value(1)),
    onConflict: DoUpdate(
      (old) => WordStateCompanion.custom(
        timesLogged: old.timesLogged + const Constant(1),
      ),
    ),
  );

  /// R1's *My words* (#138): the learner's own words, newest first, as they
  /// change.
  Stream<List<MyWord>> watchMyWords() => myWords().watch().map(
    (rows) => <MyWord>[
      for (final row in rows)
        (
          id: row.id,
          article: row.article,
          german: row.german,
          meaning: row.meaning,
          whereSeen: row.whereSeen,
          timesSeen: row.timesSeen,
        ),
    ],
  );

  /// [uids] with their state, in the order given — R1's results, which keep
  /// the search's ranking while their status chips follow the learner.
  Stream<List<WordWithState>> watchWords(List<String> uids) {
    final order = <String, int>{
      for (final (index, uid) in uids.indexed) uid: index,
    };
    return _watchWords(
      (days) => wordsWithStateByUids(days, uids).watch(),
      (row) => _word(row.w, row.s, row.derivedStatus),
    ).map(
      (words) => words..sort((a, b) => order[a.uid]!.compareTo(order[b.uid]!)),
    );
  }

  /// The same step, ready to be learned from. BR-STATUS-03.
  Stream<List<WordWithState>> watchLearnableStep(String code) => _watchWords(
    (days) => learnableWordsForStep(days, code).watch(),
    (row) => _word(row.w, row.s, row.derivedStatus),
  );

  Stream<List<WordWithState>> watchCategory(int categoryId) => _watchWords(
    (days) => wordsWithStateForCategory(days, categoryId).watch(),
    (row) => _word(row.w, row.s, row.derivedStatus),
  );

  /// L5's cards, as the learner's progress and `done_stability_days` move.
  Stream<List<CategoryProgress>> watchCategoryProgress() => _settings.switchOn(
    SettingKeys.doneStabilityDays,
    (int days) => categoryProgress(days.toDouble()).watch().map(
      (rows) => <CategoryProgress>[
        for (final row in rows)
          CategoryProgress(
            id: row.id,
            name: row.name,
            words: row.total,
            todo: row.todo,
            learning: row.learning,
            done: row.done,
          ),
      ],
    ),
  );

  Stream<WordWithState?> watchWord(String uid) => _settings
      .switchOn(
        SettingKeys.doneStabilityDays,
        (int days) => wordWithState(days.toDouble(), uid).watch(),
      )
      .map(
        (rows) => rows.isEmpty
            ? null
            : _word(rows.single.w, rows.single.s, rows.single.derivedStatus),
      );

  /// How many times [uid] was reviewed, and the last rating it got (W1's
  /// history caption) — again after every review.
  Stream<ReviewHistory> watchHistory(String uid) =>
      reviewHistory(uid).watchSingle().map(
        (row) => (
          reviews: row.reviews,
          last: row.lastRating == null ? null : Rating.parse(row.lastRating!),
        ),
      );

  /// Everything due on or before [today], excluding suspended words.
  ///
  /// [today] is a local date string — `plan_items.plan_date` and
  /// `word_state.due` are local days, because a study day is a local day.
  Stream<List<WordWithState>> watchDue(String today) => _watchWords(
    (days) => dueWords(days, today).watch(),
    (row) => _word(row.w, row.s, row.derivedStatus),
  );

  /// FR-M3-01: the stabilities Settings' retention estimate sums over.
  Future<List<double>> learnedStabilities() => stabilitiesOfLearned().get();

  Future<WordWithState?> find(String uid) async {
    if (customId(uid) case final id?) return _findMine(id);
    final rows = await wordWithState(_doneAfter, uid).get();
    return rows.isEmpty
        ? null
        : WordWithState(
            word: rows.single.w,
            state: rows.single.s,
            status: WordStatus.parse(rows.single.derivedStatus),
          );
  }

  /// A word of the learner's own in a course word's shape, so T2 serves it
  /// with the card it has (#363): the headword and article, and the meaning
  /// in `english`, which every meaning language shows when there's no Bangla.
  // ponytail: the meaning is one text in whatever language it was typed, so a
  // Bangla one sits in the English slot; a language on custom_words if that
  // matters.
  Future<WordWithState?> _findMine(int id) async {
    final row = await myWordWithState(_doneAfter, id).getSingleOrNull();
    if (row == null) return null;
    return WordWithState(
      word: Word(
        uid: customUid(id),
        sublevelCode: '',
        levelCode: '',
        seq: 0,
        seqInSublevel: 0,
        article: row.cw.article,
        german: row.cw.german,
        english: row.cw.meaning,
        searchKey: '',
        searchKeyAlt: '',
      ),
      state: row.s,
      status: WordStatus.parse(row.derivedStatus),
    );
  }

  /// Every step, in course order ([StepProgress]); again whenever the
  /// learner moves a setting it depends on.
  Stream<List<StepProgress>> watchStepProgress() => _settings.switchOnAny(
    <SettingKey<Object?>>{
      SettingKeys.doneStabilityDays,
      SettingKeys.examUnlockPercent,
      SettingKeys.dailyNew,
      SettingKeys.studyDaysMask,
    },
    () {
      final percent = _settings.read(SettingKeys.examUnlockPercent);
      final dailyNew = _settings.read(SettingKeys.dailyNew);
      final mask = _settings.read(SettingKeys.studyDaysMask);
      return stepProgress(_doneAfter).watch().map(
        (rows) => <StepProgress>[
          for (final row in rows)
            StepProgress(
              code: row.code,
              levelCode: row.levelCode,
              words: row.total,
              todo: row.todo,
              learning: row.learning,
              done: row.done,
              grammar: row.grammarCount,
              grammarLearned: row.grammarLearned,
              unlocked: StepProgress.unlocks(
                todo: row.todo,
                introduced: row.learning + row.done,
                percent: percent,
              ),
              passedSeed: row.passedSeed,
              startedOn: row.startedOn,
              completedOn: row.completedOn,
              dailyNew: row.dailyNew ?? dailyNew,
              studyDaysMask: row.studyDaysMask ?? mask,
            ),
        ],
      );
    },
  );

  /// [watchStatusCounts], once.
  Future<StatusCountsForStepResult> statusCounts(String code) =>
      statusCountsForStep(
        _settings.read(SettingKeys.doneStabilityDays).toDouble(),
        code,
      ).getSingle();

  Stream<StatusCountsForStepResult> watchStatusCounts(String code) =>
      _settings.switchOn(
        SettingKeys.doneStabilityDays,
        (int days) => statusCountsForStep(days.toDouble(), code).watchSingle(),
      );

  /// Suspends a word. Its FSRS state is untouched (BR-STATUS-03).
  Future<void> suspend(String uid) => _setStatus(uid, WordStatus.suspended);

  /// Resumes a suspended word.
  ///
  /// The status it goes back to is derived, not remembered: a word with
  /// stability past the threshold is `done`, one that has been reviewed is
  /// `learning`, and one that never was is `todo`. Storing the old status
  /// would let it come back as `done` after the threshold had been lowered.
  Future<void> resume(String uid) async {
    final state = await (select(
      db.wordState,
    )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();
    if (state == null) return;

    // `derivedStatus`, not `statusFor`: the latter answers "suspended" for a
    // suspended row, which is correct everywhere except here — resuming would
    // then set it back to suspended and nothing would ever come out of it.
    await _setStatus(uid, derivedStatus(state));
  }

  /// BR-STATUS-02: `done` is derived from stability, never set by hand.
  ///
  /// Read from settings on every call rather than cached, because
  /// `done_stability_days` is a Settings row the learner can move — and when
  /// they do, every word's status has to follow without a rebuild.
  WordStatus statusFor(WordStateData state) =>
      state.status == WordStatus.suspended.wire
      ? WordStatus.suspended
      : derivedStatus(state);

  /// What the FSRS state alone says, ignoring any suspension.
  ///
  /// This is the derivation BR-STATUS-02 describes. It is separate from
  /// [statusFor] because resuming needs the answer a suspended row would have
  /// had — asking [statusFor] there returns `suspended` and the word can never
  /// come back.
  WordStatus derivedStatus(WordStateData state) {
    // Introduced is what decides, not reviewed: `introduce()` writes the date
    // and leaves reps at 0, and reading that as never-met would put the word
    // back to `todo` on the next refresh and offer it as new again.
    if (state.introducedOn == null && state.reps == 0) return WordStatus.todo;

    final threshold = _settings.read(SettingKeys.doneStabilityDays);
    return state.stability >= threshold ? WordStatus.done : WordStatus.learning;
  }

  /// Recomputes and stores the derived status for one word.
  ///
  /// Called after every rating. The stored column is a cache of the
  /// derivation, kept because the status chip is drawn in a list and a
  /// per-row computation would mean reading settings once per row.
  Future<WordStatus> refreshStatus(String uid) async {
    final state = await (select(
      db.wordState,
    )..where((t) => t.wordUid.equals(uid))).getSingleOrNull();
    if (state == null) return WordStatus.todo;

    final status = statusFor(state);
    if (status.wire != state.status) await _setStatus(uid, status);
    return status;
  }

  /// Upsert, not update: a word at `todo` has no `word_state` row at all, and
  /// `word-detail.md` offers *Suspend* on exactly those. An UPDATE would match
  /// nothing, the chip would flip, and the next read would say `todo` again.
  Future<void> _setStatus(String uid, WordStatus status) async {
    await into(db.wordState).insertOnConflictUpdate(
      WordStateCompanion.insert(wordUid: uid, status: Value(status.wire)),
    );
  }

  /// FR-L9-01 *Add mistakes to revision*: [uids] due on [date], whatever
  /// FSRS said. A quiz's words are learned, so each has its row.
  Future<void> dueOn(List<String> uids, String date) =>
      (update(db.wordState)..where((t) => t.wordUid.isIn(uids))).write(
        WordStateCompanion(due: Value(date)),
      );

  /// Creates the state row a word gets when it is first introduced.
  ///
  /// `introduced_on` is a local date: "the day I met this word" is a local
  /// day, and it is what the streak and the stats read.
  Future<void> introduce(String uid, {required String today}) async {
    await into(db.wordState).insert(
      WordStateCompanion.insert(
        wordUid: uid,
        status: const Value('learning'),
        introducedOn: Value(today),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
