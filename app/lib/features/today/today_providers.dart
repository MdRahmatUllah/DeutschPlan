import 'package:deutschplan/core/providers/app_providers.dart';
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

  return TodayView(
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
    streak: await engine.streak(date),
    // BR-PLAN-09 for what is left, not for the whole day: the ring's caption
    // is how long until done.
    estimate: await engine.estimate(
      DailyPlan(
        date: date,
        revise: openRevise,
        newToday: openNew,
        grammarDue: plan.grammarDue,
        backlog: const <String>[],
        activeStep: step,
        isStudyDay: plan.isStudyDay,
      ),
    ),
    courseDay: started == null ? 1 : daysBetween(started, date) + 1,
    stepWords: (
      done: counts?.done ?? 0,
      learning: counts?.learning ?? 0,
      todo: counts?.todo ?? 0,
      total: counts?.total ?? 0,
    ),
    step: step,
    learnerName: name == null || name.isEmpty ? null : name,
    newCategory: await content.mainCategory(plan.newToday),
    grammar: next == null
        ? null
        : GrammarPreview(
            uid: next.uid,
            topic: next.topic.topic,
            rule: next.topic.rule ?? '',
          ),
  );
}
