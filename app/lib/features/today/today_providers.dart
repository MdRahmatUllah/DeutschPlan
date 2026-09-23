import 'dart:convert';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart'
    show WordStatus;
import 'package:deutschplan/domain/plan_engine.dart';
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
  // Not awaited: Today does not wait on a file check. Until it answers the
  // voice counts as installed, so the card appears late rather than wrongly.
  final voiceReady = ref.watch(voiceInstalledProvider).value ?? true;
  final planning = ref.watch(todayPlanProvider.future);
  final changes = ref.watch(todayOpenProvider.future);

  final plan = await planning;
  final open = await changes;
  List<String> stillOpen(PlanKind kind, List<String> planned) => <String>[
    for (final uid in planned)
      if (open.contains((kind.wire, uid))) uid,
  ];
  final openRevise = stillOpen(PlanKind.revise, plan.revise);
  final openNew = stillOpen(PlanKind.newWord, plan.newToday);

  final backlog = await plans.backlogDays(date);
  final started = await plans.courseStartedOn();
  final step = plan.activeStep;
  final counts = step == null ? null : await words.statusCounts(step);
  final next = step == null
      ? null
      : (await grammar.step(step))
            .where((topic) => topic.status == WordStatus.todo)
            .firstOrNull;
  final name = settings.read(SettingKeys.learnerName)?.trim();
  final seconds = (await plans.statsFor(date))?.seconds ?? 0;
  final streak = await engine.streak(date);
  // BR-PLAN-09 for what is left, not for the whole day: the ring's caption is
  // how long until done.
  final estimate = await engine.estimate(
    DailyPlan(
      date: date,
      revise: openRevise,
      newToday: openNew,
      grammarDue: plan.grammarDue,
      backlog: const <String>[],
      activeStep: step,
      isStudyDay: plan.isStudyDay,
    ),
  );
  final category = await content.mainCategory(plan.newToday);
  // TodayRest's note: what revising anyway would take off tomorrow.
  final dueTomorrow = plan.isStudyDay
      ? null
      : await plans.dueBy(addDays(date, 1));
  final update = await updates.unseen();
  final dismissed = settings.read(SettingKeys.dismissedCards);
  final contextual = contextualFor(
    ContextualFacts(
      dismissed: dismissed == null
          ? const <String>{}
          : (jsonDecode(dismissed) as List<dynamic>).cast<String>().toSet(),
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
      backlog: plan.backlog.length,
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
    grammarDue: plan.grammarDue,
    isStudyDay: plan.isStudyDay,
    backlog: plan.backlog.length,
    backlogFrom: backlog.from,
    backlogTo: backlog.to,
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
    learnerName: name == null || name.isEmpty ? null : name,
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
