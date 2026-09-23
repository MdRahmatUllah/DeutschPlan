import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show parsePlanDate;
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backlog_screen.g.dart';

/// A backlog word, the day it was planned for, and its meaning in the
/// learner's meaning language.
typedef BacklogWord = ({String planDate, WordWithState word, String meaning});

/// What a row action did, so its *Undo* can take it back.
enum BacklogAction { known, suspended, removed }

/// T4's rows (FR-T4-01): the uncompleted new plan rows from before today,
/// newest day first (BR-PLAN-05), with their words. A stream, so a word
/// studied from here leaves the list as it is rated.
@riverpod
class Backlog extends _$Backlog {
  @override
  Stream<List<BacklogWord>> build() {
    final words = ref.watch(wordRepositoryProvider);
    final bangla =
        ref.watch(settingsProvider).read(SettingKeys.meaningLanguage) ==
        MeaningLanguage.bangla;
    return ref
        .watch(planRepositoryProvider)
        .watchBacklog(ref.watch(todayProvider))
        .asyncMap(
          (rows) async => <BacklogWord>[
            for (final row in rows)
              if (await words.find(row.wordUid) case final found?)
                (
                  planDate: row.planDate,
                  word: found,
                  // English where the course has no Bangla.
                  meaning: bangla
                      ? found.word.bangla ?? found.word.english
                      : found.word.english,
                ),
          ],
        );
  }

  /// FR-T4-04: *Mark known*, *Suspend* or *Remove from course* (suspend and
  /// complete the plan row).
  Future<void> act(BacklogAction action, BacklogWord row) async {
    final uid = row.word.word.uid;
    final rating = ref.read(ratingServiceProvider);
    switch (action) {
      case BacklogAction.known:
        await rating.markKnown(
          uid,
          planDate: row.planDate,
          kind: PlanKind.newWord,
        );
      case BacklogAction.suspended:
        await rating.suspend(uid);
      case BacklogAction.removed:
        await rating.suspend(uid);
        await _complete(row, at: ref.read(clockProvider)().toUtc());
    }
    // A suspension touches word_state, which the plan stream does not watch.
    ref.invalidateSelf();
  }

  /// The row action's *Undo*.
  Future<void> undo(BacklogAction action, BacklogWord row) async {
    final uid = row.word.word.uid;
    final rating = ref.read(ratingServiceProvider);
    switch (action) {
      case BacklogAction.known:
        await rating.undo();
      case BacklogAction.suspended:
        await rating.resume(uid);
      case BacklogAction.removed:
        await _complete(row, at: null);
        await rating.resume(uid);
    }
    ref.invalidateSelf();
  }

  Future<void> _complete(BacklogWord row, {required DateTime? at}) => ref
      .read(planRepositoryProvider)
      .complete(
        planDate: row.planDate,
        uid: row.word.word.uid,
        kind: PlanKind.newWord,
        at: at?.toIso8601String(),
      );
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
    final rows = ref.watch(backlogProvider).value;
    return AdaptiveScaffold(
      backgroundColor: tokens.surface.paper,
      body: rows == null
          ? const SizedBox.shrink()
          : _Backlog(rows: rows, today: ref.watch(todayProvider)),
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
    final weekday = DateFormat.E(locale);
    final dates = days.keys.toList();
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
                    DpText(l10n.backlogTitle, role: DpTextRole.title),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpText(
                      // Empty, the headline is the screen's name alone.
                      rows.isEmpty
                          ? l10n.backlogTitle
                          : l10n.backlogCount(rows.length),
                      role: DpTextRole.headline,
                    ),
                    if (intro != null) ...<Widget>[
                      const SizedBox(height: 4),
                      DpText(
                        intro,
                        role: DpTextRole.label,
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
            child: DpSurface(
              kind: DpSurfaceKind.bar,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DpButton(
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
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: DpText(
                        l10n
                            .backlogDay(
                              DateFormat(
                                'EEE d MMM',
                                locale,
                              ).format(parsePlanDate(date)),
                              words.length,
                            )
                            .toUpperCase(),
                        role: DpTextRole.caption,
                        weight: 700,
                        letterSpacing: 0.6,
                        color: tokens.color.textSecondary,
                      ),
                    ),
                    DpButton(
                      label: l10n.backlogStudyDay,
                      kind: DpButtonKind.text,
                      expand: false,
                      onPressed: _study(context, words),
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
          DpText(
            l10n.backlogEmptyTitle,
            role: DpTextRole.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          DpText(
            l10n.backlogEmptyBody,
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          DpButton(
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
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DpText(l10n.backlogPause, role: DpTextRole.body, weight: 500),
              const SizedBox(height: 1),
              DpText(
                l10n.backlogPauseNote,
                role: DpTextRole.caption,
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
              DpButton(
                label: label,
                kind: DpButtonKind.text,
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
    await notifier.act(action, row);
    if (!context.mounted) return;
    DpUndo.show(
      context,
      message: switch (action) {
        BacklogAction.known => l10n.studyKnown(name),
        BacklogAction.suspended => l10n.backlogSuspended(name),
        BacklogAction.removed => l10n.backlogRemoved(name),
      },
      onUndo: () => unawaited(notifier.undo(action, row)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final word = row.word.word;
    final (status, dot) = switch (row.word.status) {
      WordStatus.todo => (l10n.wordStatusToDo, tokens.surface.muted),
      WordStatus.learning => (l10n.wordStatusLearning, tokens.color.learning),
      WordStatus.done => (l10n.wordStatusDone, tokens.color.easy),
      WordStatus.suspended => (
        l10n.wordStatusSuspended,
        tokens.color.textSecondary,
      ),
    };

    final content = Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: l10n.backlogMarkKnown): () =>
            unawaited(_run(context, ref, BacklogAction.known)),
        CustomSemanticsAction(label: l10n.backlogSuspend): () =>
            unawaited(_run(context, ref, BacklogAction.suspended)),
        CustomSemanticsAction(label: l10n.backlogRemove): () =>
            unawaited(_run(context, ref, BacklogAction.removed)),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => WordRoute.open(context, word.uid),
        onLongPress: () => unawaited(_actions(context, ref)),
        child: Container(
          height: 64,
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          decoration: BoxDecoration(
            color: tokens.surface.card,
            border: last
                ? null
                : Border(bottom: BorderSide(color: tokens.surface.outline)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DpHeadword(
                      word.german,
                      article: word.article,
                      role: DpTextRole.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    DpText(
                      row.meaning,
                      role: DpTextRole.label,
                      weight: 400,
                      maxLines: 1,
                      color: tokens.color.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DpChip(label: status, kind: DpChipKind.status, statusColour: dot),
              _Play(word: spokenForm(word)),
            ],
          ),
        ),
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

/// The row's 40 dp speaker.
class _Play extends ConsumerWidget {
  const _Play({required this.word});

  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).summaryPlay(word),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final speed = ref.read(settingsProvider).read(SettingKeys.ttsSpeed);
          unawaited(ref.read(systemTtsProvider).speak(word, rate: speed));
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.volume_up, size: 22, color: tokens.color.ink),
        ),
      ),
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
                  GestureDetector(
                    onTap: () {
                      setState(() => _open = 0);
                      run();
                    },
                    child: Container(
                      width: _TrailingActions.width,
                      alignment: Alignment.center,
                      // Oat, Sun and Lagoon: no red, even for Remove
                      // (FR-T4-05).
                      color: switch (i) {
                        0 => tokens.color.primary,
                        1 => tokens.color.accent,
                        _ => tokens.surface.muted,
                      },
                      child: DpText(
                        label,
                        role: DpTextRole.label,
                        textAlign: TextAlign.center,
                        color: tokens.color.onAccent,
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
