import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show WordStatus;
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/features/study/study_card.dart' show spokenForm;
import 'package:deutschplan/features/today/today_view.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'today_providers.g.dart';

/// FR-T1-01: today's plan, from the idempotent `openDay`.
///
/// It watches [todayProvider], so a new date re-plans and the same date does
/// not: that is FR-T1-05's midnight rollover, whether it arrives by
/// pull-to-refresh or by coming back to the app.
@riverpod
Future<DailyPlan> todayPlan(Ref ref) =>
    ref.watch(planEngineProvider).openDay(ref.watch(todayProvider));

/// Today's still-open plan rows as `(kind, uid)`, as they change: a finished
/// session moves the ring without Today having to ask.
///
/// Open the way BR-PLAN-10 counts it — a skipped card is not waiting either.
/// Keys rather than rows because the rows are drift's generated class, which
/// the provider generator cannot see.
@riverpod
Stream<Set<(String, String)>> todayOpen(Ref ref) => ref
    .watch(planRepositoryProvider)
    .watchPlan(ref.watch(todayProvider))
    .map(
      (items) => <(String, String)>{
        for (final item in items)
          if (item.completedAt == null && item.skipped == 0)
            (item.kind, item.wordUid),
      },
    );

/// How many of today's practice sentences have been rated, as it changes:
/// T5 finishing moves Today's sentence card without Today having to ask.
@riverpod
Stream<int> todaySentencesRated(Ref ref) =>
    ref.watch(sentenceStoreProvider).watchRated(ref.watch(todayProvider));

/// The grammar topics due today, as they change: a topic practised in L15
/// moves its `due` on and leaves Today's grammar block without Today having
/// to ask.
@riverpod
Stream<Set<String>> todayGrammarDue(Ref ref) => ref
    .watch(grammarRepositoryProvider)
    .watchDue(ref.watch(todayProvider))
    .map((topics) => <String>{for (final topic in topics) topic.uid});

/// Whether the on-device voice is installed and verified: Today's voice card
/// offers it until it is.
///
/// Not installed when the manifest has no such model or the check itself
/// fails — offering the voice again is harmless, and Today must not fail on
/// a file check.
@riverpod
Future<bool> voiceInstalled(Ref ref) async {
  final models = ref.watch(modelRepositoryProvider);
  try {
    final entry = (await models.manifest()).model(ModelRepository.voiceModel);
    final variant = entry?.variants.firstOrNull;
    if (entry == null || variant == null) return false;
    return await models.verify(entry.id, variant) == ModelStatus.ready;
  } on Exception {
    return false;
  }
}

/// The backlog's plan days, newest first, as they change (BR-PLAN-05): a
/// word studied or removed from T4 takes Today's backlog card with it,
/// rather than the count the day's plan held at dawn.
@riverpod
Stream<List<String>> todayBacklog(Ref ref) => ref
    .watch(planRepositoryProvider)
    .watchBacklog(ref.watch(todayProvider))
    .map((rows) => <String>[for (final row in rows) row.planDate]);

/// #460: once the app has drawn its first frame, Supertonic's sessions
/// opened and today's first cards made, so a session's first card plays
/// from the cache rather than waiting ~2.3 s for the sessions and a second
/// for its synthesis. Best effort: a voice that can't be reached here is a
/// speak's to report.
// ponytail: the first three headwords, Revise then New as a session orders
// them (BR-PLAN-02); the session prepares the rest as it opens (#430).
Future<void> warmTodaysVoice(ProviderContainer container) async {
  // Held while it is read: nothing else may be listening yet.
  final hold = container.listen(todayViewProvider, (_, _) {});
  try {
    final tts = container.read(ttsProvider);
    await tts.warm();
    final view = await container.read(todayViewProvider.future);
    final words = container.read(wordRepositoryProvider);
    await tts.prepare(<String>[
      for (final uid in <String>[...view.openRevise, ...view.openNew].take(3))
        if (await words.find(uid) case final found?) spokenForm(found.word),
    ]);
  } on Object {
    // As above.
  } finally {
    hold.close();
  }
}

/// Everything T1 draws, rendered from the persisted plan.
@riverpod
Future<TodayView> todayView(Ref ref) async {
  final date = ref.watch(todayProvider);
  final now = ref.watch(clockProvider)();
  final engine = ref.watch(planEngineProvider);
  final plans = ref.watch(planRepositoryProvider);
  final words = ref.watch(wordRepositoryProvider);
  final grammar = ref.watch(grammarRepositoryProvider);
  final content = ref.watch(contentDaoProvider);
  final settings = ref.watch(settingsProvider);
  final updates = ref.watch(contentUpdaterProvider);
  // Watched: a rename on Me reaches the greeting of a Today kept alive.
  final name = ref.watch(learnerNameProvider);
  // Not awaited: Today does not wait on a file check. Until it answers the
  // voice counts as installed, so the card appears late rather than wrongly.
  final voiceReady = ref.watch(voiceInstalledProvider).value ?? true;
  final planning = ref.watch(todayPlanProvider.future);
  final changes = ref.watch(todayOpenProvider.future);
  final picker = ref.watch(sentencePickerProvider);
  final rating = ref.watch(todaySentencesRatedProvider.future);
  final waiting = ref.watch(todayBacklogProvider.future);
  final grammarChanges = ref.watch(todayGrammarDueProvider.future);

  final plan = await planning;
  final open = await changes;
  // FR-T5-01: the day's sentences, picked once and kept in sentence_log.
  final sentences = await picker.forDay(date);
  final rated = await rating;
  final openSentences = sentences.length - rated;
  List<String> stillOpen(PlanKind kind, List<String> planned) => <String>[
    for (final uid in planned)
      if (open.contains((kind.wire, uid))) uid,
  ];
  final openRevise = stillOpen(PlanKind.revise, plan.revise);
  final openNew = stillOpen(PlanKind.newWord, plan.newToday);
  // The day's topics are the ones due when it opened; one practised since is
  // done, and one falling due later in the day waits for tomorrow's plan.
  final dueNow = await grammarChanges;
  final openGrammar = <String>[
    for (final uid in plan.grammarDue)
      if (dueNow.contains(uid)) uid,
  ];

  final backlog = await waiting;
  final started = await plans.courseStartedOn();
  final step = plan.activeStep;
  final counts = step == null ? null : await words.statusCounts(step);
  final next = step == null
      ? null
      : (await grammar.step(step))
            .where((topic) => topic.status == WordStatus.todo)
            .firstOrNull;
  final seconds = (await plans.statsFor(date))?.seconds ?? 0;
  final streak = await engine.streak(date);
  // BR-PLAN-09 for what is left, not for the whole day: the ring's caption is
  // how long until done.
  final estimate = await engine.estimate(
    DailyPlan(
      date: date,
      revise: openRevise,
      newToday: openNew,
      grammarDue: openGrammar,
      backlog: const <String>[],
      activeStep: step,
      isStudyDay: plan.isStudyDay,
    ),
    sentences: openSentences,
  );
  final category = await content.mainCategory(plan.newToday);
  // TodayRest's note: what revising anyway would take off the next study
  // day: tomorrow, or the first day after that isn't off too (#345).
  String? nextStudyDay;
  if (!plan.isStudyDay) {
    for (var ahead = 1; ahead <= 7 && nextStudyDay == null; ahead++) {
      final day = addDays(date, ahead);
      if (await engine.studyDayOn(day)) nextStudyDay = day;
    }
    nextStudyDay ??= addDays(date, 1);
  }
  final dueTomorrow = nextStudyDay == null
      ? null
      : await plans.dueBy(nextStudyDay);
  final update = await updates.unseen();
  final contextual = contextualFor(
    ContextualFacts(
      dismissed: dismissedIds(settings.read(SettingKeys.dismissedCards)),
      stepComplete: plan.stepComplete,
      nextStep: plan.nextStep,
      contentUpdate: update == null
          ? null
          : (
              version: update.version,
              added: update.added.length,
              removed: update.removed.length,
              changed: update.changed.length,
            ),
      backlog: backlog.length,
      dailyNew: settings.read(SettingKeys.dailyNew),
      pauseOn: settings.read(SettingKeys.pauseNewWhenBacklog),
      step: step,
      introduced: (counts?.done ?? 0) + (counts?.learning ?? 0),
      stepWords:
          (counts?.done ?? 0) + (counts?.learning ?? 0) + (counts?.todo ?? 0),
      examUnlockPercent: settings.read(SettingKeys.examUnlockPercent),
      systemVoice: !voiceReady,
    ),
  );

  TodayView build({TomorrowPreview? tomorrow}) => TodayView(
    date: date,
    hour: now.hour,
    revise: BlockProgress(
      done: plan.revise.length - openRevise.length,
      total: plan.revise.length,
    ),
    newToday: BlockProgress(
      done: plan.newToday.length - openNew.length,
      total: plan.newToday.length,
    ),
    openRevise: openRevise,
    openNew: openNew,
    grammarDue: openGrammar,
    grammarDone: plan.grammarDue.length - openGrammar.length,
    sentences: BlockProgress(done: rated, total: sentences.length),
    isStudyDay: plan.isStudyDay,
    backlog: backlog.length,
    backlogFrom: backlog.lastOrNull,
    backlogTo: backlog.firstOrNull,
    streak: streak,
    estimate: estimate,
    courseDay: started == null ? 1 : daysBetween(started, date) + 1,
    stepWords: (
      done: counts?.done ?? 0,
      learning: counts?.learning ?? 0,
      todo: counts?.todo ?? 0,
      total: counts?.total ?? 0,
    ),
    step: step,
    learnerName: name,
    newCategory: category,
    grammar: next == null
        ? null
        : GrammarPreview(
            uid: next.uid,
            topic: next.topic.topic,
            rule: next.topic.rule ?? '',
          ),
    minutes: seconds ~/ 60,
    tomorrow: tomorrow,
    dueTomorrow: dueTomorrow,
    nextStudyDay: nextStudyDay,
    contextual: contextual,
  );

  final view = build();
  if (!view.isDone) return view;

  // #96: tomorrow as opening it will make it, without making it.
  final ahead = await engine.previewDay(addDays(date, 1));
  return build(
    tomorrow: TomorrowPreview(
      revise: ahead.revise.length,
      newWords: ahead.newToday.length,
      grammar: ahead.grammarDue.length,
      estimate: await engine.estimate(ahead),
      category: await content.mainCategory(ahead.newToday),
      restDay: !ahead.isStudyDay,
    ),
  );
}
