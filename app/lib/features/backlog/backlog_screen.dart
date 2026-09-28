import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/plan_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/plan_engine.dart'
    show PlanDate, daysBetween, parsePlanDate;
import 'package:sogda/features/study/study_back.dart' show meaningLine;
import 'package:sogda/features/study/study_card.dart';
import 'package:sogda/features/words/word_row.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/cross_tab.dart';
import 'package:sogda/router/routes.dart';

part 'backlog_screen.g.dart';

/// A backlog word, the day it was planned for, and its meaning in the
/// learner's meaning language.
typedef BacklogWord = ({String planDate, WordWithState word, String meaning});

/// What a row action did, so its *Undo* can take it back.
enum BacklogAction { known, suspended, removed }

/// How T1's Backlog card and T4's header name the backlog's days (#821):
/// by weekday while the oldest is within the last six days, where each
/// weekday names one day ("Tue–Wed"); by date past that, where "Wed–Wed" or
/// "Mon to Thu" would name several ("30 Sep–15 Oct"). In the UI's language.
DateFormat backlogDayFormat(String locale, PlanDate oldest, PlanDate today) =>
    daysBetween(oldest, today) <= 6
    ? DateFormat.E(locale)
    : DateFormat.MMMd(locale);

/// T4's rows (FR-T4-01): the uncompleted new plan rows from before today,
/// newest day first (BR-PLAN-05), with their words. A stream, so a word
/// studied from here leaves the list as it is rated, and a word suspended or
/// resumed from W1 over it shows its new status (#368).
@riverpod
class Backlog extends _$Backlog {
  @override
  Stream<List<BacklogWord>> build() {
    final words = ref.watch(wordRepositoryProvider);
    final meaning = ref
        .watch(settingsProvider)
        .read(SettingKeys.meaningLanguage);
    return ref
        .watch(planRepositoryProvider)
        .watchBacklogWithStates(ref.watch(todayProvider))
        .asyncMap((rows) async {
          // One read for every row's word (#664), not one per row: this runs
          // again after each rating of a *Study all* session T4 sits under.
          final found = await words.findAll(<String>{
            for (final row in rows) row.wordUid,
          });
          return <BacklogWord>[
            for (final row in rows)
              if (found[row.wordUid] case final word?)
                (
                  planDate: row.planDate,
                  word: word,
                  meaning: meaningLine(word.word, meaning),
                ),
          ];
        });
  }

  /// The words with an action still being written: a second tap, from the
  /// iOS trailing buttons or a screen reader's actions, writes nothing (#689
  /// TD-7).
  final Set<String> _busy = <String>{};

  /// FR-T4-04: *Mark known*, *Suspend* or *Remove from course* (suspend and
  /// complete the plan row). Returns the action's *Undo*, bound to the
  /// services read here: its bar outlives T4, and this notifier with it
  /// (#679). Null when the word's last action is still being written.
  Future<Future<void> Function()?> act(
    BacklogAction action,
    BacklogWord row,
  ) async {
    final uid = row.word.word.uid;
    if (!_busy.add(uid)) return null;
    // Suspending a suspended word changes nothing, so its *Undo* must not
    // resume it (#728).
    final wasSuspended = row.word.isSuspended;
    final rating = ref.read(ratingServiceProvider);
    final plans = ref.read(planRepositoryProvider);
    final clock = ref.read(clockProvider);
    Future<void> complete({required DateTime? at}) => plans.complete(
      planDate: row.planDate,
      uid: uid,
      kind: PlanKind.newWord,
      at: at?.toIso8601String(),
    );
    int? entry;
    try {
      switch (action) {
        case BacklogAction.known:
          entry = await rating.markKnown(
            uid,
            planDate: row.planDate,
            kind: PlanKind.newWord,
          );
        case BacklogAction.suspended:
          await rating.suspend(uid);
        case BacklogAction.removed:
          await rating.suspend(uid);
          await complete(at: clock().toUtc());
      }
    } finally {
      _busy.remove(uid);
    }
    return () async {
      switch (action) {
        case BacklogAction.known:
          // Only this rating: another made since, of this word too, stays
          // (#728, #888).
          await rating.undo(entry: entry);
        case BacklogAction.suspended:
          if (!wasSuspended) await rating.resume(uid);
        case BacklogAction.removed:
          await complete(at: null);
          if (!wasSuspended) await rating.resume(uid);
      }
    };
  }
}

/// BR-PLAN-07's switch, as T4 shows it. Writing it changes nothing today:
/// the plan engine reads it at the next generation (FR-T4-03).
@riverpod
class BacklogPause extends _$BacklogPause {
  @override
  bool build() =>
      ref.watch(settingsProvider).read(SettingKeys.pauseNewWhenBacklog);

  Future<void> set({required bool on}) async {
    await ref.read(settingsProvider).write(SettingKeys.pauseNewWhenBacklog, on);
    state = on;
  }
}

/// T4 · Backlog (`backlog.md`): the missed and skipped new words, held
/// without pressure — no overdue styling and no red (FR-T4-05).
class BacklogScreen extends ConsumerWidget {
  const BacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final rowsState = ref.watch(backlogProvider);
    final rows = rowsState.value;
    return AdaptiveScaffold(
      backgroundColor: tokens.surface.paper,
      body: rows != null
          ? _Backlog(rows: rows, today: ref.watch(todayProvider))
          : rowsState.hasError
          ? SgLoadFailed(
              message: AppLocalizations.of(context).backlogLoadFailed,
              onRetry: () => ref.invalidate(backlogProvider),
              onBack: () => Navigator.of(context).maybePop(),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _Backlog extends ConsumerWidget {
  const _Backlog({required this.rows, required this.today});

  final List<BacklogWord> rows;
  final String today;

  /// FR-T4-02: exactly these words, as one "Backlog" block.
  /// The words there are to study: a suspended one stays listed, as
  /// FR-T4-04 says, but is not studied (BR-STATUS-03).
  static List<BacklogWord> _open(List<BacklogWord> words) => <BacklogWord>[
    for (final row in words)
      if (row.word.status != WordStatus.suspended) row,
  ];

  /// FR-T4-02: exactly these words, as one "Backlog" block. Null when none
  /// of them can be studied, so the button holds.
  VoidCallback? _study(BuildContext context, List<BacklogWord> words) {
    final open = _open(words);
    if (open.isEmpty) return null;
    return () => StudyRoute.open(
      context,
      SessionArgs(
        planDate: today,
        blocks: <SessionBlock>[
          SessionBlock(SessionBlockKind.backlog, <String>[
            for (final row in open) row.word.word.uid,
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();

    // Grouped by the day each was planned for, newest first.
    final days = <String, List<BacklogWord>>{};
    for (final row in rows) {
      (days[row.planDate] ??= <BacklogWord>[]).add(row);
    }
    final dates = days.keys.toList();
    final weekday = dates.isEmpty
        ? DateFormat.E(locale)
        : backlogDayFormat(locale, dates.last, today);
    final intro = switch (dates.length) {
      0 => null,
      1 => l10n.backlogIntroDay(weekday.format(parsePlanDate(dates.single))),
      2 => l10n.backlogIntroTwo(
        weekday.format(parsePlanDate(dates.last)),
        weekday.format(parsePlanDate(dates.first)),
      ),
      _ => l10n.backlogIntroRange(
        weekday.format(parsePlanDate(dates.last)),
        weekday.format(parsePlanDate(dates.first)),
      ),
    };

    // The Oat header, under the status bar.
    final header = ColoredBox(
      color: tokens.surface.muted,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: 56,
                child: Row(
                  children: <Widget>[
                    AdaptiveBackButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 4),
                    SgText(l10n.backlogTitle, role: SgTextRole.title),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SgText(
                      // Empty, the headline is the screen's name alone.
                      rows.isEmpty
                          ? l10n.backlogTitle
                          : l10n.backlogCount(rows.length),
                      role: SgTextRole.headline,
                    ),
                    if (intro != null) ...<Widget>[
                      const SizedBox(height: 4),
                      SgText(
                        intro,
                        role: SgTextRole.label,
                        weight: 400,
                        color: tokens.color.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // #109: nothing waiting.
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          header,
          const Expanded(child: BacklogEmpty()),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        header,
        ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            // The artboard's outlined panel: no hard shadow on this screen.
            child: SgSurface(
              kind: SgSurfaceKind.bar,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SgButton(
                    label: l10n.backlogStudyAll(_open(rows).length),
                    onPressed: _study(context, rows),
                  ),
                  const SizedBox(height: 12),
                  const _PauseRow(),
                ],
              ),
            ),
          ),
          for (final MapEntry(key: date, value: words) in days.entries) ...[
            Padding(
              // 16 at the end too: *Study this day* is a text button with no
              // padding of its own, and at 4 its label ran into the gutter
              // (#854; 12 dp past it in Bangla at 200 %).
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              // The artboard's 40, grown with the text size: a fixed 40 cut
              // the day's line at 150 % (#165). And a minimum: in Bangla at
              // 200 % the line wraps, and a grown 40 cut it (#580).
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: SgScript.grow(context, 40),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SgText(
                        l10n
                            .backlogDay(
                              DateFormat(
                                'EEE d MMM',
                                locale,
                              ).format(parsePlanDate(date)),
                              words.length,
                            )
                            .toUpperCase(),
                        role: SgTextRole.caption,
                        weight: 700,
                        letterSpacing: 0.6,
                        color: tokens.color.textSecondary,
                      ),
                    ),
                    // Held to the row's 40, as before: only the day's line,
                    // wrapping in Bangla at 200 %, makes the row taller. But
                    // never under the 48 dp (44 pt) a finger needs: a target
                    // takes no taps past its parent's box (#689 TD-14).
                    SizedBox(
                      height: math.max(
                        SgScript.grow(context, 40),
                        AdaptiveTapTarget.minimumOf(context).height,
                      ),
                      child: SgButton(
                        label: l10n.backlogStudyDay,
                        kind: SgButtonKind.text,
                        expand: false,
                        onPressed: _study(context, words),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surface.card,
                border: Border.symmetric(
                  horizontal: BorderSide(color: tokens.surface.outline),
                ),
              ),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < words.length; i++)
                    BacklogRow(row: words[i], last: i == words.length - 1),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

/// T4's empty state (`BacklogEmpty`): the tray with its Lime tick,
/// "Nothing waiting. Nice.", where these words come from, and the way back.
class BacklogEmpty extends StatelessWidget {
  const BacklogEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: CustomPaint(
              size: const Size(140, 110),
              painter: EmptyTrayPainter(
                ink: tokens.color.ink,
                tick: tokens.color.easy,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SgText(
            l10n.backlogEmptyTitle,
            role: SgTextRole.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SgText(
            l10n.backlogEmptyBody,
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SgButton(
            label: l10n.backlogBackToToday,
            // The tab's root, not whatever opened T4.
            onPressed: () => context.jumpToTab(const TodayRoute()),
          ),
        ],
      ),
    );
  }
}

/// The empty tray from the artboard: a 3 px ink outline with a Lime tick,
/// drawn on a 140 × 110 grid.
class EmptyTrayPainter extends CustomPainter {
  const EmptyTrayPainter({required this.ink, required this.tick});

  final Color ink;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 140, size.height / 110);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(20, 60)
          ..lineTo(34, 30)
          ..lineTo(106, 30)
          ..lineTo(120, 60)
          ..lineTo(120, 94)
          ..lineTo(20, 94)
          ..close(),
        line,
      )
      ..drawPath(
        Path()
          ..moveTo(20, 60)
          ..lineTo(54, 60)
          ..lineTo(62, 72)
          ..lineTo(78, 72)
          ..lineTo(86, 60)
          ..lineTo(120, 60),
        line,
      )
      ..drawCircle(const Offset(108, 26), 14, Paint()..color = tick)
      ..drawCircle(const Offset(108, 26), 14, line)
      ..drawPath(
        Path()
          ..moveTo(101, 26)
          ..lineTo(106, 31)
          ..lineTo(115, 21),
        line,
      );
  }

  @override
  bool shouldRepaint(EmptyTrayPainter old) =>
      old.ink != ink || old.tick != tick;
}

/// "Pause new words until this is clear" (FR-T4-03).
class _PauseRow extends ConsumerWidget {
  const _PauseRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // The row is the switch, as a settings row is (#345), and a node of its
    // own (#912): the toggle merged up into the card, over *Study all*.
    return Semantics(
      container: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgText(l10n.backlogPause, role: SgTextRole.body, weight: 500),
                const SizedBox(height: 1),
                SgText(
                  l10n.backlogPauseNote,
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AdaptiveSwitch(
            value: ref.watch(backlogPauseProvider),
            semanticLabel: l10n.backlogPauseLabel,
            onChanged: (on) =>
                unawaited(ref.read(backlogPauseProvider.notifier).set(on: on)),
          ),
        ],
      ),
    );
  }
}

/// A backlog word: the headword in its article's colour, its meaning, its
/// status and play. A tap opens the word; a long-press — and on iOS a
/// trailing swipe — offers the row actions (FR-T4-04).
class BacklogRow extends ConsumerWidget {
  const BacklogRow({required this.row, required this.last, super.key});

  final BacklogWord row;
  final bool last;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final action = await Adaptive.showSheet<BacklogAction>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (action, label) in <(BacklogAction, String)>[
              (BacklogAction.known, l10n.backlogMarkKnown),
              (BacklogAction.suspended, l10n.backlogSuspend),
              (BacklogAction.removed, l10n.backlogRemove),
            ])
              SgButton(
                label: label,
                kind: SgButtonKind.text,
                onPressed: () => Navigator.of(sheet).pop(action),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    await _run(context, ref, action);
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    BacklogAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(backlogProvider.notifier);
    final name = spokenForm(row.word.word);
    final undo = await notifier.act(action, row);
    if (undo == null || !context.mounted) return;
    unawaited(
      SgUndo.show(
        context,
        message: switch (action) {
          BacklogAction.known => l10n.studyKnown(name),
          BacklogAction.suspended => l10n.backlogSuspended(name),
          BacklogAction.removed => l10n.backlogRemoved(name),
        },
        onUndo: () => unawaited(undo()),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final content = Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: l10n.backlogMarkKnown): () =>
            unawaited(_run(context, ref, BacklogAction.known)),
        CustomSemanticsAction(label: l10n.backlogSuspend): () =>
            unawaited(_run(context, ref, BacklogAction.suspended)),
        CustomSemanticsAction(label: l10n.backlogRemove): () =>
            unawaited(_run(context, ref, BacklogAction.removed)),
      },
      child: SgTappable(
        onTap: () => WordRoute.open(context, row.word.uid),
        onLongPress: () => unawaited(_actions(context, ref)),
        child: WordRow(word: row.word, meaning: row.meaning, last: last),
      ),
    );

    if (!context.isCupertino) return content;
    return _TrailingActions(
      actions: <(String, VoidCallback)>[
        (
          l10n.backlogMarkKnown,
          () => unawaited(_run(context, ref, BacklogAction.known)),
        ),
        (
          l10n.backlogSuspend,
          () => unawaited(_run(context, ref, BacklogAction.suspended)),
        ),
        (
          l10n.backlogRemove,
          () => unawaited(_run(context, ref, BacklogAction.removed)),
        ),
      ],
      child: content,
    );
  }
}

/// iOS's trailing swipe: drag the row left to uncover its actions.
class _TrailingActions extends StatefulWidget {
  const _TrailingActions({required this.actions, required this.child});

  final List<(String, VoidCallback)> actions;
  final Widget child;

  /// Each action's width.
  static const double width = 88;

  @override
  State<_TrailingActions> createState() => _TrailingActionsState();
}

class _TrailingActionsState extends State<_TrailingActions> {
  double _open = 0;

  double get _full => _TrailingActions.width * widget.actions.length;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Each fill with its own ink (#735). Lagoon, Sun and Oat: no red, even
    // for Remove (FR-T4-05).
    final colours = <(Color, Color)>[
      (tokens.color.primary, tokens.color.onPrimary),
      (tokens.color.accent, tokens.color.onAccent),
      (tokens.surface.muted, tokens.color.ink),
    ];
    return GestureDetector(
      onHorizontalDragUpdate: (d) =>
          setState(() => _open = (_open - d.delta.dx).clamp(0, _full)),
      onHorizontalDragEnd: (_) =>
          setState(() => _open = _open > _full / 2 ? _full : 0),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                for (final (i, (label, run)) in widget.actions.indexed)
                  // Under the row until a swipe shows them: the row's long
                  // press and its semantics actions do the same three (#1021;
                  // a key reaches none yet, #1039).
                  // ponytail: allow-bare-tap
                  GestureDetector(
                    onTap: () {
                      setState(() => _open = 0);
                      run();
                    },
                    child: Container(
                      width: _TrailingActions.width,
                      alignment: Alignment.center,
                      color: colours[i].$1,
                      child: SgText(
                        label,
                        role: SgTextRole.label,
                        textAlign: TextAlign.center,
                        color: colours[i].$2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Transform.translate(offset: Offset(-_open, 0), child: widget.child),
        ],
      ),
    );
  }
}
