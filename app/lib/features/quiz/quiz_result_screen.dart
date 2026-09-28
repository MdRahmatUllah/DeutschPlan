import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/exam_repository.dart'
    show QuizMistakeRowsResult, QuizResult;
import 'package:sogda/domain/quiz_builder.dart' show QuizDirection;
import 'package:sogda/features/quiz/quiz_names.dart';
import 'package:sogda/features/quiz/quiz_screen.dart' show quizTitle;
import 'package:sogda/features/study/write_guard.dart';
import 'package:sogda/features/words/word_row.dart' show WordPlayButton;
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/router/routes.dart';

part 'quiz_result_screen.g.dart';

/// L9's run, read back from `quiz_attempts` and `quiz_answers`.
@riverpod
Future<QuizResult?> quizResult(Ref ref, int attemptId) =>
    ref.watch(quizRunServiceProvider).result(attemptId);

/// L9 · Quiz result (`quiz.md`, `QuizResult-android.html`, #126), shown by
/// L8 in place of the run it finished: the score on its colour, the time and
/// the kind, the mistakes, and *Retry mistakes* · *Add mistakes to
/// revision* · *Done*.
class QuizResultView extends ConsumerStatefulWidget {
  const QuizResultView({
    required this.attemptId,
    required this.args,
    super.key,
  });

  final int attemptId;

  /// The run's own args: its title, and the direction and timer a retry
  /// keeps.
  final QuizArgs args;

  @override
  ConsumerState<QuizResultView> createState() => _QuizResultViewState();
}

class _QuizResultViewState extends ConsumerState<QuizResultView> {
  /// *Add mistakes to revision* is done once.
  bool _added = false;

  /// FR-L9-01: a new quiz from the mistakes, in place of this one.
  ///
  /// A compare quiz's retry is its set again, as many items as it had
  /// mistakes: its items are sentences, and a uid names only the member.
  // ponytail: the same set, not the missed sentences; carry their ords in
  // the ref if a retry should ask exactly those.
  void _retry(List<String> uids) => QuizRoute.instead(
    context,
    QuizArgs(
      direction: widget.args.direction,
      source: 'compareSet',
      sourceRef: widget.args.direction == QuizDirection.compare.name
          ? widget.args.sourceRef
          : uids.join(','),
      length: uids.length,
      timer: widget.args.timer,
      seed: math.Random().nextInt(1 << 31),
    ),
  );

  /// FR-L9-01: the mistakes rated Again and due tomorrow, explicitly.
  Future<void> _addToRevision(List<QuizMistakeRowsResult> mistakes) async {
    setState(() => _added = true);
    // #647: a write that fails says so, with Retry and Export (#174), and
    // the button comes back; it used to stay greyed out, saying nothing.
    final written = await guardWrite(context, () async {
      await ref.read(quizRunServiceProvider).addToRevision(
        <({String uid, String? verdict})>[
          for (final m in mistakes) (uid: m.uid, verdict: m.verdict),
        ],
        today: ref.read(todayProvider),
      );
      return true;
    });
    if (!mounted) return;
    if (!written) {
      setState(() => _added = false);
      return;
    }
    SgToast.show(
      context,
      AppLocalizations.of(context).quizAddedToRevision(mistakes.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final resultState = ref.watch(quizResultProvider(widget.attemptId));
    final result = resultState.value;
    final close = Navigator.of(context).pop;

    final Widget content;
    if (result == null) {
      // An attempt that isn't there reads as null: no blank page either.
      content = resultState.hasError || resultState.hasValue
          ? SgLoadFailed(
              message: l10n.learnLoadFailed,
              onRetry: () =>
                  ref.invalidate(quizResultProvider(widget.attemptId)),
              onBack: close,
            )
          : const SizedBox.expand();
    } else {
      final attempt = result.attempt;
      final share = attempt.maxPoints == 0
          ? 0.0
          : attempt.scorePoints / attempt.maxPoints;
      final colour = quizColour(tokens.color, share);
      final uids = <String>[for (final m in result.mistakes) m.uid];
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Score(
            colour: colour,
            score: l10n.quizResultScore(
              l10n.digits(quizPoints(attempt.scorePoints)),
              l10n.digits(quizPoints(attempt.maxPoints)),
            ),
            line: l10n.quizResultLine(
              // Down, never up: 79.5 % is not the 80 % that turns it Lime.
              (share * 100).floor(),
              _time(l10n, attempt.startedAt, attempt.finishedAt),
              quizTitle(l10n, widget.args),
            ),
            closeLabel: l10n.quizClose,
            onClose: close,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 14),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SgText(
                    (uids.isEmpty
                            ? l10n.quizResultNoMistakes
                            : l10n.quizResultMistakes(uids.length))
                        .toUpperCase(),
                    role: SgTextRole.caption,
                    weight: 700,
                    letterSpacing: 0.6,
                    color: tokens.color.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (uids.isNotEmpty)
                  SgSurface(
                    kind: SgSurfaceKind.bar,
                    radius: 0,
                    child: Column(
                      children: <Widget>[
                        for (final (index, mistake) in result.mistakes.indexed)
                          _MistakeRow(
                            mistake: mistake,
                            last: index == result.mistakes.length - 1,
                            compare:
                                widget.args.direction ==
                                QuizDirection.compare.name,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (uids.isNotEmpty) ...<Widget>[
                  SgButton(
                    label: l10n.quizRetryMistakes(uids.length),
                    onPressed: () => _retry(uids),
                  ),
                  const SizedBox(height: 8),
                  SgButton(
                    label: l10n.quizAddToRevision,
                    kind: SgButtonKind.secondary,
                    onPressed: _added
                        ? null
                        : () => unawaited(_addToRevision(result.mistakes)),
                  ),
                  const SizedBox(height: 8),
                ],
                SgButton(
                  label: l10n.done,
                  kind: SgButtonKind.text,
                  onPressed: close,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final scaffold = AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: content,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}

/// "4 min 12 s", from the attempt's start to its finish.
String _time(AppLocalizations l10n, String started, String? finished) {
  final seconds = finished == null
      ? 0
      : math.max(
          0,
          DateTime.parse(finished)
              .difference(DateTime.parse(started))
              .inSeconds,
        );
  return l10n.quizResultTime(seconds ~/ 60, seconds % 60);
}

/// The score block, on the result's colour: close, "16 / 20", and its line.
class _Score extends StatelessWidget {
  const _Score({
    required this.colour,
    required this.score,
    required this.line,
    required this.closeLabel,
    required this.onClose,
  });

  final Color colour;
  final String score;
  final String line;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Semantics(
              button: true,
              label: closeLabel,
              onTap: onClose,
              excludeSemantics: true,
              child: AdaptiveTooltip(
                message: closeLabel,
                child: SgPressable(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  // The artboards: a back arrow on Android, a cross on iOS.
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      context.isCupertino ? Icons.close : Icons.arrow_back,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SgText(score, role: SgTextRole.display, weight: 700, color: ink),
          const SizedBox(height: 6),
          SgText(line, role: SgTextRole.body, weight: 600, color: ink),
        ],
      ),
    );
    return tokens.isGlass
        ? SgSurface(kind: SgSurfaceKind.tint(colour), radius: 0, child: content)
        : ColoredBox(color: colour, child: content);
  }
}

/// "die Kaution — you wrote: die Kausion", or "… · article" when only the
/// article was wrong, with the word to hear.
class _MistakeRow extends StatelessWidget {
  const _MistakeRow({
    required this.mistake,
    required this.last,
    this.compare = false,
  });

  final QuizMistakeRowsResult mistake;
  final bool last;

  /// A compare quiz's (W2): the member it asked for, which its word — the
  /// set word, for a member with none of its own — does not always name.
  final bool compare;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final given = mistake.given ?? '';
    final wrote = given.isEmpty
        ? l10n.quizResultNoAnswer
        : mistake.verdict == 'wrongArticle'
        ? l10n.quizResultWroteArticle(given)
        : l10n.quizResultWrote(given);
    // A word a content update removed shows what the quiz expected.
    final german = compare
        ? mistake.expected
        : mistake.german ?? mistake.expected;
    // The article is the word's: not for a set word standing in.
    final article = !compare || mistake.german == mistake.expected
        ? mistake.article
        : null;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: tokens.surface.outline)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgHeadword(
                  german,
                  article: article,
                  role: SgTextRole.bodyLarge,
                  weight: 600,
                ),
                const SizedBox(height: 2),
                SgText(
                  wrote,
                  role: SgTextRole.label,
                  weight: 400,
                  color: tokens.color.wrongText,
                ),
              ],
            ),
          ),
          WordPlayButton(word: article == null ? german : '$article $german'),
        ],
      ),
    );
  }
}
