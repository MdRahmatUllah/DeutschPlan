import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/plan_stats.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show GoRouteData;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'me_screen.g.dart';

/// What was practised on each day, as it changes (FR-M1-02).
@riverpod
Stream<Map<String, int>> activity(Ref ref) =>
    ref.watch(planRepositoryProvider).watchActivity();

/// Everything M1 draws.
typedef MeView = ({
  PlanDate today,
  List<StepProgress> steps,
  int streak,
  PlanDate? since,
  Map<String, int> activity,
  ScheduleStatus schedule,

  /// `done_stability_days`, for the legend.
  int doneDays,

  /// BR-EXAM-01's `exam_unlock_percent`.
  int unlockPercent,
});

/// M1's figures, recomputed whenever the course, a day's practice or the
/// backlog moves: a session finished on Today moves them without Me having to
/// ask, and so does a setting — `stepProgress` re-reads on the two it shows.
@riverpod
Future<MeView> meView(Ref ref) async {
  final date = ref.watch(todayProvider);
  final engine = ref.watch(planEngineProvider);
  final plans = ref.watch(planRepositoryProvider);
  final settings = ref.watch(settingsProvider);
  final course = ref.watch(stepProgressProvider.future);
  final practice = ref.watch(activityProvider.future);
  final backlog = ref.watch(todayBacklogProvider.future);

  final steps = await course;
  final activity = await practice;
  await backlog;
  return (
    today: date,
    steps: steps,
    streak: await engine.streak(date),
    since: await plans.courseStartedOn(),
    activity: activity,
    // FR-M1-03, measured through yesterday: today's new words are today's
    // work, not the backlog, and counting them would put every learner a day
    // behind each morning. What is left is exactly T4's backlog.
    schedule: await engine.scheduleCheck(
      addDays(date, -1),
      fallbackDailyNew: settings.read(SettingKeys.dailyNew),
    ),
    doneDays: settings.read(SettingKeys.doneStabilityDays),
    unlockPercent: settings.read(SettingKeys.examUnlockPercent),
  );
}

/// FR-M1-02's five shades: nothing, 1–9, 10–19, 20–39 and 40 or more items
/// in a day.
int activityShade(int items) => items <= 0
    ? 0
    : items < 10
    ? 1
    : items < 20
    ? 2
    : items < 40
    ? 3
    : 4;

/// The heat-map's twelve weeks, oldest first, each Monday to Sunday and the
/// last one the week of [today]. Days still to come are null.
List<List<PlanDate?>> activityWeeks(PlanDate today) {
  final first = addDays(
    today,
    -(parsePlanDate(today).weekday - DateTime.monday) - 7 * (weeks - 1),
  );
  return <List<PlanDate?>>[
    for (var week = 0; week < weeks; week++)
      <PlanDate?>[
        for (var day = 0; day < 7; day++)
          switch (addDays(first, week * 7 + day)) {
            final date when date.compareTo(today) <= 0 => date,
            _ => null,
          },
      ],
  ];
}

/// How many weeks the heat-map shows.
const int weeks = 12;

/// M1 · Me (`docs/04-screens/me.md`, `Me-android.html`): the learner's own
/// overview. A Cobalt header with the name and the streak, the course's words,
/// twelve weeks of activity, the schedule check, the twelve steps' mock exams,
/// and the doors to Settings, the models and About.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(meViewProvider);

    final Widget body;
    if (me.value != null) {
      body = _Me(me: me.value!);
    } else if (me.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
            message: l10n.meLoadFailed,
            retryLabel: l10n.retry,
            onRetry: () => ref
              ..invalidate(stepProgressProvider)
              ..invalidate(meViewProvider),
          ),
        ),
      );
    } else {
      body = const SizedBox.expand();
    }

    // Glass has no paper of its own: the aurora is, led by Cobalt.
    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.der, child: body)
          : body,
    );
  }
}

class _Me extends ConsumerWidget {
  const _Me({required this.me});

  final MeView me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final steps = me.steps;
    final active = steps.where((step) => step.active).firstOrNull;

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        MeHeader(
          name: ref.watch(learnerNameProvider),
          streak: me.streak,
          since: me.since,
          // Not a day after today: a learner who flew west can have
          // practised on what is now tomorrow.
          daysStudied: me.activity.keys
              .where((day) => day.compareTo(me.today) <= 0)
              .length,
          onEditName: () => _editName(context, ref),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MeWordsCard(
                steps: steps,
                doneDays: me.doneDays,
                onTap: () => context.jumpToTab(const ProgressRoute()),
              ),
              const SizedBox(height: 10),
              MeActivityCard(
                today: me.today,
                activity: me.activity,
                onTap: () => context.jumpToTab(const ProgressRoute()),
              ),
              const SizedBox(height: 10),
              MeScheduleCard(
                schedule: me.schedule,
                onTap: () => context.jumpToTab(const BacklogRoute()),
              ),
              const SizedBox(height: 10),
              MeExamsCard(
                steps: steps,
                active: active,
                unlockPercent: me.unlockPercent,
                // FR-M1-04: L10 for that step, in the Learn tab.
                onStep: (code) => context.jumpToTab(
                  LearnStepRoute(code: code, tab: StepTab.exams),
                ),
              ),
              const SizedBox(height: 10),
              _Links(
                links: <(IconData, String, GoRouteData)>[
                  (
                    Icons.settings_outlined,
                    l10n.meSettings,
                    const SettingsRoute(),
                  ),
                  (Icons.mic_none, l10n.meVoice, const ModelsRoute()),
                  (Icons.shield_outlined, l10n.meAbout, const AboutRoute()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The header's *edit name*: a sheet with the name, saved on *Save*.
  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final name = await Adaptive.showSheet<String>(
      context: context,
      builder: (_) => _NameSheet(initial: ref.read(learnerNameProvider) ?? ''),
    );
    if (name != null) await ref.read(learnerNameProvider.notifier).rename(name);
  }
}

/// The Cobalt header: the name to edit, the streak, and since when.
class MeHeader extends StatelessWidget {
  const MeHeader({
    required this.name,
    required this.streak,
    required this.since,
    required this.daysStudied,
    required this.onEditName,
    super.key,
  });

  final String? name;
  final int streak;

  /// The day the course began, or null before it has.
  final PlanDate? since;
  final int daysStudied;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // Glass tints a white panel, so the ink is the page's; Cobalt takes the
    // ink made for it, in dark mode too.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onDer;
    final shown = name ?? l10n.meNameEmpty;
    final studied = l10n.meDaysStudied(daysStudied);
    final started = since;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        10 + MediaQuery.paddingOf(context).top,
        16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  // A node of its own: without `container` the name's button
                  // swallowed the whole header, streak and all.
                  child: Semantics(
                    container: true,
                    button: true,
                    label: shown,
                    hint: l10n.meEditName,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onEditName,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: DpOneLine(
                                shown,
                                role: DpTextRole.headline,
                                color: ink,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.edit_outlined, size: 18, color: ink),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DpChip(
                label: streak.toString(),
                kind: DpChipKind.streak,
                semanticLabel: l10n.todayStreak(streak),
              ),
            ],
          ),
          DpText(
            started == null
                ? studied
                : '${l10n.meSince(_date(context, started))} · $studied',
            role: DpTextRole.label,
            weight: 500,
            color: ink.withValues(alpha: 0.9),
          ),
        ],
      ),
    );

    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.der),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.der, child: content);
  }

  /// "19 Aug 2026".
  static String _date(BuildContext context, PlanDate date) => DateFormat(
    'd MMM y',
    Localizations.localeOf(context).toString(),
  ).format(parsePlanDate(date));
}

/// FR-M1-01: the course's Done, Learning and To do, and what they mean.
class MeWordsCard extends StatelessWidget {
  const MeWordsCard({
    required this.steps,
    required this.doneDays,
    required this.onTap,
    super.key,
  });

  final List<StepProgress> steps;

  /// `done_stability_days`: what Done means, in the legend.
  final int doneDays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    int sum(int Function(StepProgress step) of) =>
        steps.fold(0, (total, step) => total + of(step));
    final done = sum((step) => step.done);
    final learning = sum((step) => step.learning);
    final todo = sum((step) => step.todo);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );

    Widget count(int value, Color colour, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Swatch(colour: colour),
              const SizedBox(width: 6),
              Flexible(
                child: DpText(number.format(value), role: DpTextRole.title),
              ),
            ],
          ),
          const SizedBox(height: 2),
          DpText(
            label,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DpSegmentedBar(
              done: done,
              learning: learning,
              todo: todo,
              height: 12,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                count(done, tokens.color.easy, l10n.wordStatusDone),
                const SizedBox(width: 8),
                count(learning, tokens.color.learning, l10n.wordStatusLearning),
                const SizedBox(width: 8),
                count(todo, tokens.surface.muted, l10n.wordStatusToDo),
              ],
            ),
            const SizedBox(height: 10),
            DpText(
              l10n.meWordsLegend(doneDays),
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A status's colour beside its count: the bar's segment, outlined in ink.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: context.tokens.color.ink),
    ),
  );
}

/// FR-M1-02: twelve weeks of practice, a column a week and a row a weekday,
/// in five shades of Lagoon.
class MeActivityCard extends StatelessWidget {
  const MeActivityCard({
    required this.today,
    required this.activity,
    required this.onTap,
    super.key,
  });

  final PlanDate today;

  /// Items practised per day; a day with none is absent.
  final Map<String, int> activity;
  final VoidCallback onTap;

  /// The Lagoon's alpha per shade, above none. The artboard draws the top
  /// three; 1–9 items, which it has no day of, is lighter still.
  static const List<double> alphas = <double>[0.15, 0.35, 0.65, 1];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final days = activityWeeks(today);
    final practised = days
        .expand((week) => week)
        .where((day) => (activity[day] ?? 0) > 0)
        .length;

    Color shade(PlanDate? day) {
      final step = day == null ? 0 : activityShade(activity[day] ?? 0);
      return step == 0
          ? tokens.surface.muted
          : tokens.color.primary.withValues(alpha: alphas[step - 1]);
    }

    return Semantics(
      button: true,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: DpText(
                    l10n.meActivity,
                    role: DpTextRole.body,
                    weight: 600,
                  ),
                ),
                DpText(
                  l10n.meActivityRange,
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Colour alone says nothing to a screen reader: the grid reads
            // as how many days had practice.
            Semantics(
              label: l10n.meActivityLabel(practised),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    for (final week in days)
                      Column(
                        children: <Widget>[
                          for (final (i, day) in week.indexed) ...<Widget>[
                            if (i > 0) const SizedBox(height: 3),
                            Container(
                              key: day == null ? null : ValueKey<String>(day),
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: shade(day),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FR-M1-03: how far behind the plan, and the way into the backlog; or on
/// schedule, with nowhere to go.
class MeScheduleCard extends StatelessWidget {
  const MeScheduleCard({
    required this.schedule,
    required this.onTap,
    super.key,
  });

  final ScheduleStatus schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final behind = !schedule.onSchedule;
    // Whole days, since that is how the plan is laid out; under one it says
    // so rather than rounding a few words up to a day or down to none.
    final days = schedule.daysBehind.round();

    return Semantics(
      // A node of its own even when it is not a button: "On schedule"
      // otherwise ran on into the exams card below.
      container: true,
      button: behind,
      child: DpSurface(
        kind: DpSurfaceKind.bar,
        onTap: behind ? onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: behind ? tokens.color.hard : tokens.color.easy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.color.ink, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Icon(
                behind ? Icons.schedule : Icons.check,
                size: 18,
                color: tokens.color.onAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DpText(
                    !behind
                        ? l10n.meOnSchedule
                        : days == 0
                        ? l10n.meBehindUnderADay
                        : l10n.meBehind(days),
                    role: DpTextRole.body,
                    weight: 600,
                  ),
                  if (behind) ...<Widget>[
                    const SizedBox(height: 1),
                    DpText(
                      l10n.meBehindLine(schedule.behind),
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
            if (behind)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: tokens.color.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

/// A step's mock exams, as M1's badges show them.
enum ExamBadge { passed, unlocked, current, locked }

/// Lime once a mock is passed, Lagoon once the exams are unlocked, outlined
/// for the step in progress, and faded for the rest.
ExamBadge examBadge(StepProgress step) {
  if (step.passed) return ExamBadge.passed;
  if (step.unlocked) return ExamBadge.unlocked;
  if (step.active) return ExamBadge.current;
  return ExamBadge.locked;
}

/// The twelve steps' mock exams: how many are passed, when the current
/// step's unlock, and a badge per step that opens its exams (FR-M1-04).
class MeExamsCard extends StatelessWidget {
  const MeExamsCard({
    required this.steps,
    required this.active,
    required this.unlockPercent,
    required this.onStep,
    super.key,
  });

  final List<StepProgress> steps;

  /// The step in progress, if there is one.
  final StepProgress? active;

  /// BR-EXAM-01's `exam_unlock_percent`.
  final int unlockPercent;
  final ValueChanged<String> onStep;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final passed = steps.where((step) => step.passed).length;
    final current = active;
    final line = <String>[
      l10n.meExamsPassed(passed),
      if (current != null && !current.passed)
        current.unlocked
            ? l10n.meExamsUnlocked(current.code)
            : l10n.meExamsUnlocksAt(current.code, unlockPercent),
    ].join(' · ');

    return DpSurface(
      kind: DpSurfaceKind.bar,
      // The badges' 48 dp targets reach into the padding below them and the
      // gap above; the badges themselves are drawn at the artboard's 26.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: <Widget>[
              DpText(l10n.meExams, role: DpTextRole.body, weight: 600),
              DpText(
                line,
                role: DpTextRole.caption,
                color: tokens.color.textSecondary,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              for (final (i, step) in steps.indexed) ...<Widget>[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _Badge(
                    step: step,
                    badge: examBadge(step),
                    onTap: () => onStep(step.code),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.step, required this.badge, required this.onTap});

  final StepProgress step;
  final ExamBadge badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final (Color fill, Color text, String state) = switch (badge) {
      ExamBadge.passed => (
        tokens.color.easy,
        tokens.color.onAccent,
        l10n.learnPassed,
      ),
      ExamBadge.unlocked => (
        tokens.color.primary,
        tokens.color.onPrimary,
        l10n.learnExamsUnlocked,
      ),
      ExamBadge.current => (
        tokens.surface.muted,
        tokens.color.ink,
        l10n.learnCurrent,
      ),
      ExamBadge.locked => (
        tokens.surface.muted,
        tokens.color.textSecondary,
        l10n.learnNotStarted,
      ),
    };
    Widget label(String code) =>
        DpText(code, role: DpTextRole.caption, weight: 700, color: text);
    final border = badge == ExamBadge.locked
        ? Border.all(
            color: tokens.surface.outline,
            width: tokens.surface.outlineWidth,
          )
        : Border.all(color: tokens.color.ink, width: 1.5);

    return Semantics(
      container: true,
      button: true,
      label: l10n.meBadge(step.code, state),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(6),
                border: border,
              ),
              alignment: Alignment.center,
              // The artboard's 9 px: twelve codes across a phone. Scaled
              // down as one: each code sits in the box of the widest, so a
              // `.2` is not drawn smaller than a `.1`.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      for (final widest in const <String>[
                        'A2.2',
                        'B2.2',
                        'C2.2',
                      ])
                        Visibility.maintain(
                          visible: false,
                          child: label(widest),
                        ),
                      label(step.code),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings, Voice & translation, About & privacy: one card, a row each.
class _Links extends StatelessWidget {
  const _Links({required this.links});

  final List<(IconData, String, GoRouteData)> links;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DpSurface(
      kind: DpSurfaceKind.bar,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          for (final (i, (icon, label, route)) in links.indexed) ...<Widget>[
            if (i > 0) Container(height: 1, color: tokens.surface.outline),
            Semantics(
              container: true,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.jumpToTab(route),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(icon, size: 22, color: tokens.color.ink),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DpText(
                            label,
                            role: DpTextRole.body,
                            weight: 500,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: tokens.color.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The name, in a sheet: popped with what was typed on *Save*, with nothing
/// when the sheet is dismissed.
class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.initial});

  final String initial;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.shape.button),
      borderSide: BorderSide(color: tokens.color.ink, width: 2),
    );
    // No keyboard inset of its own: the sheet opens in the Me tab, whose
    // shell already shrinks above the keyboard, and adding the inset again
    // floated the field a keyboard's height above it (seen on the device).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DpText(l10n.meNameTitle, role: DpTextRole.title),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            // ponytail: 40 characters — the header shows one line of it.
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: DpText.styleFor(tokens, DpTextRole.bodyLarge),
            decoration: InputDecoration(
              labelText: l10n.meNameTitle,
              counterText: '',
              filled: true,
              fillColor: tokens.surface.cardStrong,
              border: edge,
              enabledBorder: edge,
              focusedBorder: edge,
            ),
          ),
          const SizedBox(height: 12),
          DpButton(label: l10n.meNameSave, onPressed: _save),
        ],
      ),
    );
  }
}
