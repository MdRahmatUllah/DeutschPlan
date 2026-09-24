import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart'
    show QuizMistakeRowsResult, QuizResult;
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/quiz/quiz_screen.dart' show quizTitle;
import 'package:deutschplan/features/words/word_row.dart' show WordPlayButton;
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
  void _retry(List<String> uids) => QuizRoute.instead(
    context,
    QuizArgs(
      direction: widget.args.direction,
      source: 'compareSet',
      sourceRef: uids.join(','),
      length: uids.length,
      timer: widget.args.timer,
      seed: math.Random().nextInt(1 << 31),
    ),
  );

  /// FR-L9-01: the mistakes due tomorrow, explicitly.
  Future<void> _addToRevision(List<String> uids) async {
    setState(() => _added = true);
    await ref
        .read(quizRunServiceProvider)
        .addToRevision(uids, today: ref.read(todayProvider));
    if (!mounted) return;
    DpToast.show(
      context,
      AppLocalizations.of(context).quizAddedToRevision(uids.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final result = ref.watch(quizResultProvider(widget.attemptId)).value;
    final close = Navigator.of(context).pop;

    final Widget content;
    if (result == null) {
      content = const SizedBox.expand();
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
              _points(attempt.scorePoints),
              _points(attempt.maxPoints),
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
                  child: DpText(
                    (uids.isEmpty
                            ? l10n.quizResultNoMistakes
                            : l10n.quizResultMistakes(uids.length))
                        .toUpperCase(),
                    role: DpTextRole.caption,
                    weight: 700,
                    letterSpacing: 0.6,
                    color: tokens.color.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (uids.isNotEmpty)
                  DpSurface(
                    kind: DpSurfaceKind.bar,
                    radius: 0,
                    child: Column(
                      children: <Widget>[
                        for (final (index, mistake) in result.mistakes.indexed)
                          _MistakeRow(
                            mistake: mistake,
                            last: index == result.mistakes.length - 1,
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
                  DpButton(
                    label: l10n.quizRetryMistakes(uids.length),
                    onPressed: () => _retry(uids),
                  ),
                  const SizedBox(height: 8),
                  DpButton(
                    label: l10n.quizAddToRevision,
                    kind: DpButtonKind.secondary,
                    onPressed: _added
                        ? null
                        : () => unawaited(_addToRevision(uids)),
                  ),
                  const SizedBox(height: 8),
                ],
                DpButton(
                  label: l10n.done,
                  kind: DpButtonKind.text,
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

/// "16", or "15.5": a quiz scores in halves (BR-ANS-04).
String _points(double points) => points == points.roundToDouble()
    ? '${points.round()}'
    : points.toStringAsFixed(1);

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
              excludeSemantics: true,
              child: GestureDetector(
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
          DpText(score, role: DpTextRole.display, weight: 700, color: ink),
          const SizedBox(height: 6),
          DpText(line, role: DpTextRole.body, weight: 600, color: ink),
        ],
      ),
    );
    return tokens.isGlass
        ? DpSurface(kind: DpSurfaceKind.tint(colour), radius: 0, child: content)
        : ColoredBox(color: colour, child: content);
  }
}

/// "die Kaution — you wrote: die Kausion", or "… · article" when only the
/// article was wrong, with the word to hear.
class _MistakeRow extends StatelessWidget {
  const _MistakeRow({required this.mistake, required this.last});

  final QuizMistakeRowsResult mistake;
  final bool last;

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
    final german = mistake.german ?? mistake.expected;
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
                DpHeadword(
                  german,
                  article: mistake.article,
                  role: DpTextRole.bodyLarge,
                  weight: 600,
                ),
                const SizedBox(height: 2),
                DpText(
                  wrote,
                  role: DpTextRole.label,
                  weight: 400,
                  color: tokens.color.wrongText,
                ),
              ],
            ),
          ),
          WordPlayButton(
            word: mistake.article == null
                ? german
                : '${mistake.article} $german',
          ),
        ],
      ),
    );
  }
}
