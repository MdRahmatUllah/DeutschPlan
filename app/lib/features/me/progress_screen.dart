import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/progress_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart'
    show PlanDate, addDays, daysBetween, parsePlanDate;
import 'package:deutschplan/domain/progress_stats.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'progress_screen.g.dart';

/// What M2 draws for one of its views (`progress.md`).
typedef ProgressView = ({
  List<ProgressBar> bars,

  /// Each bar's retention, null where there were no revisions.
  List<double?> retention,

  /// The view's retention over all its revisions; null with none.
  double? retentionOverall,

  /// `desired_retention`, the dashed line.
  double target,

  /// Days until retention shows (`progress.md`: after 30 days of data);
  /// null once it does.
  int? retentionDaysLeft,

  ProgressTotals totals,
  int streak,
  int best,
});

@riverpod
Future<ProgressView> progressView(Ref ref, ProgressRange range) async {
  final repo = ref.watch(progressRepositoryProvider);
  final engine = ref.watch(planEngineProvider);
  final today = ref.watch(todayProvider);
  final target = ref.watch(settingsProvider).read(SettingKeys.desiredRetention);
  final days = await repo.days();
  final ratings = await repo.revisionRatings();
  final bars = progressBars(range, today, days);

  List<int> ratingsOf(ProgressBar bar) => range == ProgressRange.all
      ? <int>[
          for (final e in ratings.entries)
            if (e.key.startsWith(bar.start.substring(0, 8))) ...e.value,
        ]
      : ratings[bar.start] ?? const <int>[];

  final first = days
      .where((d) => d.reviews + d.newWords > 0)
      .map((d) => d.day)
      .fold<PlanDate?>(
        null,
        (min, d) => min == null || d.compareTo(min) < 0 ? d : min,
      );
  return (
    bars: bars,
    retention: <double?>[for (final bar in bars) retention(ratingsOf(bar))],
    retentionOverall: retention(<int>[
      for (final bar in bars) ...ratingsOf(bar),
    ]),
    target: target,
    retentionDaysLeft: retentionReady(first, today)
        ? null
        : daysBetween(today, addDays(first ?? today, 30)),
    totals: await repo.totals(),
    streak: await engine.streak(today),
    best: await engine.bestStreak(today),
  );
}

/// M2 · Progress detail (`progress.md`, the Progress artboard): Week, Month
/// or All — the cards per day, retention against the target, each step's
/// bar, and the totals.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  // ponytail: the chosen view is the screen's, gone when it closes.
  ProgressRange _range = ProgressRange.week;

  /// What is on screen, and the range it is for: kept while the next range
  /// loads, so the cards don't drop out and the list jump.
  ({ProgressRange range, ProgressView view})? _last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final progress = ref.watch(progressViewProvider(_range));
    if (progress.value case final fresh?) _last = (range: _range, view: fresh);
    final shown = progress.hasError ? null : _last;
    final steps = ref.watch(stepProgressProvider).value;

    final scaffold = AdaptiveScaffold(
      title: l10n.progressTitle,
      leading: AdaptiveBackButton(
        label: l10n.tabMe,
        colour: context.isCupertino ? null : tokens.color.ink,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          AdaptiveSegmented<ProgressRange>(
            segments: <ProgressRange, String>{
              ProgressRange.week: l10n.progressWeek,
              ProgressRange.month: l10n.progressMonth,
              ProgressRange.all: l10n.progressAll,
            },
            value: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          if (shown case (:final range, :final view)) ...<Widget>[
            const SizedBox(height: 12),
            _CardsChart(range: range, view: view),
            const SizedBox(height: 12),
            _RetentionChart(range: range, view: view),
          ] else if (progress.hasError) ...<Widget>[
            const SizedBox(height: 24),
            DpErrorPanel(
              message: l10n.meLoadFailed,
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(progressViewProvider(_range)),
            ),
          ],
          if (steps != null && steps.any(_shown)) ...<Widget>[
            const SizedBox(height: 12),
            _ByStep(steps: steps.where(_shown).toList()),
          ],
          if (shown case (:final view, range: _)) ...<Widget>[
            const SizedBox(height: 12),
            _Totals(view: view),
          ],
        ],
      ),
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.der, child: scaffold)
        : scaffold;
  }

  /// A step begun, or passed: the rows the artboard lists.
  static bool _shown(StepProgress step) =>
      step.startedOn != null || step.passed;
}

/// The period in words: "this week", "last 30 days", "all time".
String _period(AppLocalizations l10n, ProgressRange range) => switch (range) {
  ProgressRange.week => l10n.progressPeriodWeek,
  ProgressRange.month => l10n.progressPeriodMonth,
  ProgressRange.all => l10n.progressPeriodAll,
};

/// A bar's name: the weekday ("Mo"), the day of the month, or the month.
String _when(BuildContext context, ProgressRange range, PlanDate start) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final date = parsePlanDate(start);
  return switch (range) {
    ProgressRange.week => switch (date.weekday) {
      DateTime.monday => l10n.weekdayShortMon,
      DateTime.tuesday => l10n.weekdayShortTue,
      DateTime.wednesday => l10n.weekdayShortWed,
      DateTime.thursday => l10n.weekdayShortThu,
      DateTime.friday => l10n.weekdayShortFri,
      DateTime.saturday => l10n.weekdayShortSat,
      _ => l10n.weekdayShortSun,
    },
    ProgressRange.month => DateFormat.MMMd(locale).format(date),
    ProgressRange.all => DateFormat.MMM(locale).format(date),
  };
}

/// A chart's card: the title, the line in its corner, the chart, a legend.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.corner,
    required this.child,
    this.legend = const <Widget>[],
  });

  final String title;
  final String corner;
  final Widget child;
  final List<Widget> legend;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final heading = Semantics(
      header: true,
      child: DpText(title, role: DpTextRole.body, weight: 700),
    );
    final cornerLine = DpText(
      corner,
      role: DpTextRole.caption,
      color: tokens.color.textSecondary,
    );
    return DpSurface(
      kind: DpSurfaceKind.bar,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Past 130 % text the corner line goes under the title: beside it,
          // it ran 84 dp off the card at 200 % (#165).
          if (DpScript.large(context)) ...<Widget>[heading, cornerLine] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(child: heading),
                cornerLine,
              ],
            ),
          const SizedBox(height: 12),
          child,
          if (legend.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 4, children: legend),
          ],
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.fill, required this.label});

  final Color fill;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: tokens.color.ink),
          ),
        ),
        const SizedBox(width: 6),
        // Wraps inside the legend's Wrap, which bounds it: at 200 % a key
        // ran off the card and broke "introduced" (#165).
        Flexible(child: DpText(label, role: DpTextRole.caption)),
      ],
    );
  }
}

/// "Cards per day": a bar a day (a month for All), revisions Lagoon under
/// new words Sun, each outlined in ink — the order and the legend carry it
/// without the colours.
class _CardsChart extends StatelessWidget {
  const _CardsChart({required this.range, required this.view});

  final ProgressRange range;
  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final bars = view.bars;
    final cards = bars.fold(0, (sum, b) => sum + b.reviews + b.newWords);
    final top = math.max(
      1,
      bars.fold(0, (most, b) => math.max(most, b.reviews + b.newWords)),
    );
    final side = BorderSide(color: tokens.color.ink);
    // A day with nothing done still shows where it is: a sliver.
    final sliver = top / 60;
    final width = switch (range) {
      ProgressRange.week => 22.0,
      ProgressRange.month => 6.0,
      ProgressRange.all => 14.0,
    };
    // Month's thirty days are named every seventh.
    bool named(int i) =>
        range != ProgressRange.month || (bars.length - 1 - i) % 7 == 0;

    return _ChartCard(
      title: range == ProgressRange.all
          ? l10n.progressCardsPerMonth
          : l10n.progressCardsPerDay,
      corner: l10n.progressCardsLine(_period(l10n, range), cards),
      legend: <Widget>[
        _Key(fill: tokens.color.primary, label: l10n.progressRevisions),
        _Key(fill: tokens.color.accent, label: l10n.progressNew),
      ],
      child: Semantics(
        label: <String>[
          for (final bar in bars)
            l10n.progressBar(
              _when(context, range, bar.start),
              bar.reviews,
              bar.newWords,
            ),
        ].join('\n'),
        child: ExcludeSemantics(
          child: SizedBox(
            height: 110,
            child: BarChart(
              BarChartData(
                maxY: top * 1.05,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      // Grown with the text size: a fixed 22 cut "Mo" at
                      // 150 % (#165).
                      reservedSize: MediaQuery.textScalerOf(context).scale(22),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= bars.length || !named(i)) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: DpText(
                            _when(context, range, bars[i].start),
                            role: DpTextRole.caption,
                            color: tokens.color.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: <BarChartGroupData>[
                  for (final (i, bar) in bars.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: <BarChartRodData>[
                        if (bar.reviews + bar.newWords == 0)
                          BarChartRodData(
                            toY: sliver,
                            width: width,
                            color: tokens.surface.outline,
                            borderRadius: BorderRadius.circular(2),
                          )
                        else
                          BarChartRodData(
                            toY: (bar.reviews + bar.newWords).toDouble(),
                            width: width,
                            color: tokens.color.primary,
                            borderRadius: BorderRadius.circular(3),
                            rodStackItems: <BarChartRodStackItem>[
                              BarChartRodStackItem(
                                0,
                                bar.reviews.toDouble(),
                                tokens.color.primary,
                                borderSide: side,
                              ),
                              BarChartRodStackItem(
                                bar.reviews.toDouble(),
                                (bar.reviews + bar.newWords).toDouble(),
                                tokens.color.accent,
                                borderSide: side,
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ),
      ),
    );
  }
}

/// FR-M2-01: retention, the share of revisions remembered, against the
/// dashed target — or, before 30 days of data, when it will show.
class _RetentionChart extends StatelessWidget {
  const _RetentionChart({required this.range, required this.view});

  final ProgressRange range;
  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final target = (view.target * 100).round();
    final overall = view.retentionOverall;
    final left = view.retentionDaysLeft;
    final period = _period(l10n, range);

    final Widget body;
    if (left != null) {
      body = DpText(
        l10n.progressRetentionLater(math.max(1, left)),
        role: DpTextRole.caption,
        color: tokens.color.textSecondary,
      );
    } else {
      final points = <FlSpot>[
        for (final (i, value) in view.retention.indexed)
          if (value != null) FlSpot(i.toDouble(), value),
      ];
      final low = math.min(
        view.target,
        points.fold(1.0, (min, p) => math.min(min, p.y)),
      );
      body = Semantics(
        label: <String>[
          for (final (i, value) in view.retention.indexed)
            if (value != null)
              l10n.progressRetentionPoint(
                _when(context, range, view.bars[i].start),
                (value * 100).round(),
              ),
        ].join('\n'),
        child: ExcludeSemantics(
          child: SizedBox(
            height: 64,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(1, view.bars.length - 1).toDouble(),
                minY: math.max(0, low - 0.05),
                maxY: 1,
                lineTouchData: const LineTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: <HorizontalLine>[
                    HorizontalLine(
                      y: view.target,
                      color: tokens.color.textSecondary,
                      strokeWidth: 1.5,
                      dashArray: <int>[5, 4],
                    ),
                  ],
                ),
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: points,
                    color: tokens.color.primary,
                    barWidth: 3,
                    dotData: FlDotData(
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 4,
                        color: tokens.color.primary,
                        strokeColor: tokens.color.ink,
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ),
      );
    }

    return _ChartCard(
      title: l10n.progressRetention,
      corner: overall == null
          ? l10n.progressRetentionNone(period, target)
          : l10n.progressRetentionLine((overall * 100).round(), period, target),
      legend: left != null
          ? const <Widget>[]
          : <Widget>[
              _Key(fill: tokens.color.primary, label: l10n.progressRemembered),
              _Key(
                fill: tokens.color.textSecondary,
                label: l10n.progressTarget,
              ),
            ],
      child: body,
    );
  }
}

/// "By step": each begun step's words, done in Lime and learning in Sun,
/// and the way to its L2.
class _ByStep extends StatelessWidget {
  const _ByStep({required this.steps});

  final List<StepProgress> steps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    return DpSurface(
      kind: DpSurfaceKind.bar,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: DpText(
              l10n.progressByStep.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          for (final step in steps)
            Semantics(
              container: true,
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.jumpToTab(LearnStepRoute(code: step.code)),
                child: ConstrainedBox(
                  // accessibility-performance.md: 48 dp on Android, 44 pt
                  // on iOS.
                  constraints: BoxConstraints(
                    minHeight: context.isCupertino ? 44 : 48,
                  ),
                  child: Row(
                    children: <Widget>[
                      DpChip(label: step.code),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DpSegmentedBar(
                          done: step.done,
                          learning: step.learning,
                          todo: math.max(
                            0,
                            step.words - step.done - step.learning,
                          ),
                          colours: (
                            done: tokens.color.easy,
                            learning: tokens.color.accent,
                            todo: tokens.surface.track,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DpText(
                        l10n.progressStepCount(step.done, step.words),
                        role: DpTextRole.caption,
                        color: tokens.color.textSecondary,
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
        ],
      ),
    );
  }
}

/// The totals: study time, words introduced, reviews, streak and best.
class _Totals extends StatelessWidget {
  const _Totals({required this.view});

  final ProgressView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    final minutes = view.totals.seconds ~/ 60;
    Widget total(String value, String label) => Expanded(
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DpText(value, role: DpTextRole.title, weight: 700),
            DpText(
              label,
              role: DpTextRole.caption,
              color: tokens.color.textSecondary,
            ),
          ],
        ),
      ),
    );
    final totals = <Widget>[
      total(
        minutes >= 60
            ? l10n.progressHours(minutes ~/ 60, minutes % 60)
            : l10n.progressMinutes(minutes),
        l10n.progressStudyTime,
      ),
      total(number.format(view.totals.introduced), l10n.progressIntroduced),
      total(number.format(view.totals.reviews), l10n.progressReviews),
      total(
        l10n.progressStreakBest(view.streak, view.best),
        l10n.progressStreakLabel,
      ),
    ];
    return DpSurface(
      kind: DpSurfaceKind.bar,
      radius: 16,
      padding: const EdgeInsets.all(14),
      // Past 130 % text two to a row: four abreast broke "introduced"
      // mid-word at 150 % (#165).
      child: DpScript.large(context)
          ? Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: totals.sublist(0, 2),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: totals.sublist(2),
                ),
              ],
            )
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: totals),
    );
  }
}
