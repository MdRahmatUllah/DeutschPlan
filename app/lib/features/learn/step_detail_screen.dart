import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show parsePlanDate;
import 'package:deutschplan/domain/plan_stats.dart' show courseDays;
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/learn/step_exams.dart';
import 'package:deutschplan/features/learn/step_grammar.dart';
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// L2 · Step detail (`docs/04-screens/step-detail.md`, `StepDetail-android.html`):
/// everything in one step. A Sun header — the code, its level, words and
/// topics, the step's bar and its pace — over the four inner tabs.
class StepDetailScreen extends ConsumerStatefulWidget {
  const StepDetailScreen({required this.code, super.key, this.tab});

  final String code;

  /// The tab a deep entry point asked for (`?tab=`); Words otherwise.
  final StepTab? tab;

  @override
  ConsumerState<StepDetailScreen> createState() => _StepDetailScreenState();
}

class _StepDetailScreenState extends ConsumerState<StepDetailScreen> {
  late StepTab _tab = widget.tab ?? StepTab.words;

  @override
  void didUpdateWidget(StepDetailScreen old) {
    super.didUpdateWidget(old);
    // The same route, reached again with another ?tab=.
    if (widget.tab != null && widget.tab != old.tab) _tab = widget.tab!;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(stepProgressProvider);
    final steps = state.value;
    final step = steps
        ?.where((candidate) => candidate.code == widget.code)
        .firstOrNull;

    final Widget body;
    if (step != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StepHeader(step: step),
          ColoredBox(
            color: tokens.isGlass
                ? tokens.surface.paper.withValues(alpha: 0)
                : tokens.surface.paper,
            child: AdaptiveTabBar<StepTab>(
              tabs: <StepTab, String>{
                StepTab.words: l10n.stepTabWords,
                StepTab.grammar: l10n.stepTabGrammar,
                StepTab.quiz: l10n.stepTabQuiz,
                StepTab.exams: l10n.stepTabExams,
              },
              value: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
          Expanded(
            child: StepTabBody(step: step, tab: _tab),
          ),
        ],
      );
    } else if (steps != null) {
      // A code the course does not have — a stale link, a typo.
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
            message: l10n.stepNotFound(widget.code),
            retryLabel: l10n.stepBackToCourse,
            onRetry: () => context.jumpToTab(const LearnRoute()),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DpErrorPanel(
            message: l10n.learnLoadFailed,
            retryLabel: l10n.retry,
            onRetry: () => ref.invalidate(stepProgressProvider),
          ),
        ),
      );
    } else {
      body = const SizedBox.expand();
    }

    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.accent, child: body)
          : body,
    );
  }
}

/// L2's header: the bar with back and search, "A2.1" beside its level,
/// words and topics, the step's bar and its pace line (FR-L2-01).
class StepHeader extends StatelessWidget {
  const StepHeader({required this.step, super.key});

  final StepProgress step;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final cupertino = context.isCupertino;
    // Glass tints a white panel, so the ink is the page's; Sun takes the
    // ink made for it, in dark mode too.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final name = CourseLevel.name(step.levelCode);
    final counts = l10n.stepHeaderCounts(step.words, step.grammar);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: MediaQuery.paddingOf(context).top),
        // The bar's height, or the back button's when larger text makes
        // its label taller (#404).
        SizedBox(
          height: math.max(
            cupertino
                ? AdaptiveScaffold.cupertinoBarHeight
                : AdaptiveScaffold.materialBarHeight,
            AdaptiveBackButton.heightOf(context, label: l10n.tabLearn),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 4),
              AdaptiveBackButton(
                label: l10n.tabLearn,
                colour: cupertino ? null : ink,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: cupertino
                    ? DpText(
                        step.code,
                        role: DpTextRole.bodyLarge,
                        weight: 600,
                        color: ink,
                        textAlign: TextAlign.center,
                      )
                    : const SizedBox.shrink(),
              ),
              IconButton(
                tooltip: l10n.stepSearch,
                icon: Icon(Icons.search, color: ink),
                onPressed: () =>
                    context.jumpToTab(SearchRoute(step: step.code)),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  DpText(
                    step.code,
                    role: DpTextRole.display,
                    weight: 700,
                    color: ink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DpText(
                      name == null ? counts : '$name · $counts',
                      role: DpTextRole.body,
                      weight: 600,
                      color: ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DpSegmentedBar(
                done: step.done,
                learning: step.learning,
                todo: step.todo,
                // L1's course bar on Sun (#449): the artboard's Lime Done and
                // Sun Learning vanish on a Sun field (Learning is Sun).
                colours: (
                  done: ink,
                  learning: tokens.color.onAccentMark,
                  todo: tokens.color.onAccentTrack,
                ),
              ),
              const SizedBox(height: 8),
              DpText(
                paceLine(l10n, Localizations.localeOf(context), step),
                role: DpTextRole.label,
                weight: 500,
                color: ink,
              ),
            ],
          ),
        ),
      ],
    );

    return tokens.isGlass
        ? DpSurface(
            kind: DpSurfaceKind.tint(tokens.color.accent),
            radius: 0,
            child: content,
          )
        : ColoredBox(color: tokens.color.accent, child: content);
  }
}

/// FR-L2-01's line: when the step began and how long its To-do words will
/// take at its pace, or when it was completed and which mock passed.
String paceLine(AppLocalizations l10n, Locale locale, StepProgress step) {
  String day(String date) =>
      DateFormat('d MMM', locale.toString()).format(parsePlanDate(date));
  if (step.completedOn case final completed?) {
    return step.passedSeed == null
        ? l10n.stepCompleted(day(completed))
        : l10n.stepCompletedPassed(day(completed), step.passedSeed!);
  }
  // FR-L2-01: To-do words ÷ daily_new × (7 ÷ study days), rounded up. A
  // pace with no study days has no end; say none rather than divide by it.
  final days =
      courseDays(
        words: step.todo,
        dailyNew: step.dailyNew,
        studyDaysMask: step.studyDaysMask,
      ) ??
      0;
  if (step.startedOn case final started?) {
    return days == 0
        ? l10n.stepStartedAllIntroduced(day(started))
        : l10n.stepStarted(day(started), days, step.dailyNew);
  }
  return l10n.stepNotStarted(days, step.dailyNew);
}

/// What each inner tab holds.
class StepTabBody extends StatelessWidget {
  const StepTabBody({required this.step, required this.tab, super.key});

  final StepProgress step;
  final StepTab tab;

  @override
  Widget build(BuildContext context) => switch (tab) {
    StepTab.words => StepWordsTab(step: step),
    StepTab.grammar => StepGrammarTab(code: step.code),
    StepTab.quiz => StepQuizTab(step: step),
    StepTab.exams => StepExamsTab(step: step),
  };
}
