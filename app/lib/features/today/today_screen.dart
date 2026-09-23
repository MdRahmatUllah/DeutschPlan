import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_coach_mark.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/domain/plan_engine.dart' show parsePlanDate;
import 'package:deutschplan/features/today/today_components.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// T1 · Today, in progress. `docs/04-screens/today.md`, `Today-android.html`.
///
/// "What do I do now, and how long will it take": the header, the ring card,
/// one card per block of today's plan, the grammar-this-week card and the
/// docked button.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // FR-T1-05: coming back after midnight is a new day.
    _lifecycle = AppLifecycleListener(onResume: _reread);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Re-reads the date and the view. The plan watches only the date, so a
  /// new date re-plans and the same date plans nothing; the view is read
  /// again either way, because the greeting's hour has moved on too.
  void _reread() {
    ref.invalidate(todayProvider);
    ref.invalidate(todayViewProvider);
  }

  /// FR-T1-05's pull-to-refresh.
  Future<void> _refresh() async {
    _reread();
    try {
      await ref.read(todayViewProvider.future);
    } on Object {
      // The error panel says so; the pull only has to end, not rethrow into
      // a refresh indicator that nobody awaits.
    }
  }

  /// FR-T1-04: a session with only [uids], from today's plan.
  void _study(List<String> uids, String date) =>
      StudyRoute.open(context, SessionArgs(wordUids: uids, planDate: date));

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(todayViewProvider);
    final view = state.value;

    final Widget body;
    if (view != null) {
      body = _Plan(view: view, onRefresh: _refresh, onStudy: _study);
    } else if (state.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
            message: l10n.todayLoadFailed,
            retryLabel: l10n.retry,
            onRetry: () {
              ref.invalidate(todayPlanProvider);
              ref.invalidate(todayViewProvider);
            },
          ),
        ),
      );
    } else {
      // The plan is on this phone and opens in a moment; a spinner would
      // only flash.
      body = const SizedBox.expand();
    }

    // Glass has no paper of its own: the aurora is the paper, led by Lagoon.
    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.primary, child: body)
          : body,
    );
  }
}

class _Plan extends ConsumerWidget {
  const _Plan({
    required this.view,
    required this.onRefresh,
    required this.onStudy,
  });

  final TodayView view;
  final Future<void> Function() onRefresh;
  final void Function(List<String> uids, String date) onStudy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final open = <String>[...view.openRevise, ...view.openNew];
    final start = open.isEmpty ? null : () => onStudy(open, view.date);
    final step = view.step;
    final grammar = view.grammar;

    final sections = <Widget>[
      PlanSectionCard(
        icon: Icons.autorenew,
        tile: tokens.color.primary,
        title: l10n.todayRevise(view.revise.total),
        subtitle: switch (view.revise.total) {
          0 when view.firstDay => l10n.todayReviseFirstDay,
          0 => l10n.todayReviseNone,
          final count => l10n.todayReviseDue(count),
        },
        trailing: _trailing(view.revise),
        progress: view.revise,
        ringColour: tokens.color.primary,
        onTap: view.openRevise.isEmpty
            ? null
            : () => onStudy(view.openRevise, view.date),
      ),
      if (view.newToday.total > 0)
        PlanSectionCard(
          icon: Icons.star_outline,
          tile: tokens.color.accent,
          title: l10n.todayNew(view.newToday.total),
          subtitle: view.newCategory == null
              ? l10n.todayNewPlain(view.newToday.total)
              : l10n.todayNewCategory(view.newToday.total, view.newCategory!),
          trailing: _trailing(view.newToday),
          progress: view.newToday,
          ringColour: tokens.color.accent,
          onTap: view.openNew.isEmpty
              ? null
              : () => onStudy(view.openNew, view.date),
        ),
      if (view.backlog > 0)
        PlanSectionCard(
          icon: Icons.layers_outlined,
          tile: tokens.surface.muted,
          title: l10n.todayBacklog(view.backlog),
          subtitle: _backlogDays(context, l10n),
          trailing: SectionTrailing.open,
          onTap: () => context.jumpToTab(const BacklogRoute()),
        ),
      if (view.grammarDue.isNotEmpty)
        PlanSectionCard(
          icon: Icons.menu_book_outlined,
          tile: tokens.color.der,
          tileInk: tokens.color.onDer,
          title: l10n.todayGrammarDue(view.grammarDue.length),
          subtitle: l10n.todayGrammarDueTopics(view.grammarDue.length),
          trailing: SectionTrailing.open,
          onTap: () => GrammarPracticeRoute.open(
            context,
            GrammarPracticeArgs(topicUids: view.grammarDue),
          ),
        ),
      if (view.sentences.total > 0)
        PlanSectionCard(
          icon: Icons.chat_bubble_outline,
          tile: tokens.color.die,
          title: l10n.todaySentences(view.sentences.total),
          subtitle: l10n.todaySentencesKnown(view.sentences.total),
          trailing: view.sentences.finished
              ? SectionTrailing.done
              : SectionTrailing.open,
          onTap: () => SentencesRoute.open(context),
        ),
    ];

    final label = switch (todayAction(view)) {
      TodayAction.start => l10n.todayStart(view.total),
      TodayAction.resume => l10n.todayContinue(view.left),
      TodayAction.done => l10n.todayAllDone,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: AdaptiveRefresh(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: <Widget>[
                TodayHeader(
                  view: view,
                  onStreak: () => context.jumpToTab(const ProgressRoute()),
                  onSettings: () => context.jumpToTab(const SettingsRoute()),
                ),
                // The ring card reaches up into the header, and everything
                // under it moves with it; the 24 dp this leaves at the end of
                // the list is under the docked button.
                Transform.translate(
                  offset: const Offset(0, -TodayHeader.overlap),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        ProgressRingCard(
                          view: view,
                          onStart: start,
                          onStep: () {
                            if (step != null) {
                              context.jumpToTab(LearnStepRoute(code: step));
                            }
                          },
                        ),
                        for (var i = 0; i < sections.length; i++) ...<Widget>[
                          SizedBox(height: i == 0 ? 16 : 10),
                          sections[i],
                        ],
                        if (grammar != null) ...<Widget>[
                          const SizedBox(height: 12),
                          GrammarPreviewCard(
                            preview: grammar,
                            onTap: () => context.jumpToTab(
                              GrammarTopicRoute(uid: grammar.uid),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // FR-S2-03's one-time mark, on the button a new learner starts with.
        DpCoachMark(
          message: l10n.todayCoachMark,
          visible: ref.watch(coachMarkProvider),
          onShown: () => ref.read(coachMarkProvider.notifier).markShown(),
          onDismissed: () => ref.read(coachMarkProvider.notifier).dismiss(),
          child: PrimaryActionBar(label: label, onPressed: start),
        ),
      ],
    );
  }

  static SectionTrailing _trailing(BlockProgress block) {
    if (block.finished) return SectionTrailing.done;
    return block.total == 0 ? SectionTrailing.none : SectionTrailing.progress;
  }

  /// "Tue–Wed", in the UI's language: these are the learner's own days.
  String _backlogDays(BuildContext context, AppLocalizations l10n) {
    final weekday = DateFormat.E(Localizations.localeOf(context).toString());
    final from = view.backlogFrom;
    final to = view.backlogTo;
    if (from == null || to == null) return l10n.todayBacklog(view.backlog);
    final first = weekday.format(parsePlanDate(from));
    final last = weekday.format(parsePlanDate(to));
    return from == to
        ? l10n.todayBacklogDay(view.backlog, first)
        : l10n.todayBacklogRange(view.backlog, first, last);
  }
}
