import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/quiz/quiz_names.dart';
import 'package:sogda/features/quiz/quiz_setup_sheet.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/router/routes.dart';

part 'step_quiz.g.dart';

/// The step's latest finished quiz, for L2's last quiz card.
@riverpod
Stream<LastQuiz?> lastStepQuiz(Ref ref, String code) =>
    ref.watch(examRepositoryProvider).watchLastStepQuiz(code);

/// The quiz a tile starts (FR-L2-04): from this step's learned words, in
/// the learner's meaning direction unless it is *Forms* (#667).
QuizArgs stepQuiz(
  String code, {
  required int length,
  String direction = 'de>en',
}) => QuizArgs(
  direction: direction,
  source: 'stepLearned',
  sourceRef: code,
  length: length,
  seed: math.Random().nextInt(1 << 31),
);

/// L2 · Quiz (`step-detail.md`, `QuizSetup-android.html`): Quick 10 ·
/// Standard 20 · Long 30 · Forms · Custom over this step's learned words,
/// and the last quiz. Closed, with the reason, until ten are learned.
class StepQuizTab extends ConsumerWidget {
  const StepQuizTab({required this.step, super.key});

  final StepProgress step;

  /// How many of the step's words must be learned before it quizzes.
  static const int minimumLearned = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final learned = step.introduced;
    final open = learned >= minimumLearned;
    final last = ref.watch(lastStepQuizProvider(step.code)).value;

    void start(int length, [String? direction]) => QuizRoute.open(
      context,
      stepQuiz(
        step.code,
        length: length,
        direction: direction ?? meaningDirection(ref),
      ),
    );

    final lengths = <(String, int)>[
      (l10n.quizQuick, 10),
      (l10n.quizStandard, 20),
      (l10n.quizLong, 30),
    ];
    final forms = QuizTile(
      title: l10n.quizForms,
      subtitle: l10n.quizFormsLine,
      onTap: open ? () => start(20, 'forms') : null,
    );
    final custom = QuizTile(
      title: l10n.quizCustom,
      subtitle: l10n.quizCustomLine,
      onTap: open ? () => unawaited(_custom(context)) : null,
    );
    // Past 130 % text three tiles abreast break "Standard" mid-word (#165,
    // #396): they stack, full width.
    final stacked = SgScript.large(context);

    return ListView(
      key: PageStorageKey<String>('step-quiz-${step.code}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: <Widget>[
        SgText(
          open ? l10n.quizTilesCaption.toUpperCase() : l10n.quizLocked(learned),
          role: SgTextRole.caption,
          weight: open ? 700 : 400,
          letterSpacing: open ? 0.6 : null,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 10),
        if (stacked)
          for (final (label, length) in lengths) ...<Widget>[
            QuizTile(
              title: label,
              subtitle: l10n.quizQuestions(length),
              onTap: open ? () => start(length) : null,
            ),
            const SizedBox(height: 10),
          ]
        else ...<Widget>[
          Row(
            children: <Widget>[
              for (final (i, (label, length)) in lengths.indexed) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: QuizTile(
                    title: label,
                    subtitle: l10n.quizQuestions(length),
                    centred: true,
                    onTap: open ? () => start(length) : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (stacked) ...<Widget>[forms, const SizedBox(height: 10), custom] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: forms),
                const SizedBox(width: 10),
                Expanded(child: custom),
              ],
            ),
          ),
        if (last != null) ...<Widget>[
          const SizedBox(height: 10),
          LastQuizCard(
            quiz: last,
            languages:
                ref.watch(courseLanguagesProvider).value ?? baseLanguages,
          ),
        ],
      ],
    );
  }

  /// L7's custom quiz sheet: the quiz it builds starts here, from the tab
  /// that opened it, once the sheet has closed.
  Future<void> _custom(BuildContext context) async {
    final args = await QuizSetupSheet.show(context, step.code);
    if (args != null && context.mounted) QuizRoute.open(context, args);
  }
}

/// A quiz tile: its name and what it holds. Greyed and inert while the
/// step has too few learned words.
class QuizTile extends StatelessWidget {
  const QuizTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
    this.centred = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onTap != null;
    final align = centred ? TextAlign.center : TextAlign.start;
    final tile = SgSurface(
      kind: SgSurfaceKind.bar,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: centred
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          SgText(
            title,
            role: SgTextRole.bodyLarge,
            weight: 600,
            textAlign: align,
            color: enabled ? null : tokens.color.textSecondary,
          ),
          const SizedBox(height: 4),
          SgText(
            subtitle,
            role: SgTextRole.caption,
            textAlign: align,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: enabled ? tile : Opacity(opacity: 0.5, child: tile),
    );
  }
}

/// "Last quiz · 16 / 20" beside its score, coloured as L9 colours a result:
/// Lime from 80 %, Sun from 50 %, Coral under. Halves are L9's too: 8.5 is
/// not 9, nor its colour (#335).
class LastQuizCard extends StatelessWidget {
  const LastQuizCard({
    required this.quiz,
    super.key,
    this.languages = baseLanguages,
  });

  final LastQuiz quiz;

  /// The course's languages, whose own names name a quiz's (#1120).
  final List<CourseLanguageName> languages;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final share = quiz.outOf == 0 ? 0.0 : quiz.score / quiz.outOf;
    final colour = quizColour(tokens.color, share);
    final kind = quizKindName(l10n, quiz.length);
    final date = DateFormat(
      'EEE d MMM',
      Localizations.localeOf(context).toString(),
      // Its local day: `finished_at` is a UTC instant (#391's review).
    ).format(DateTime.parse(quiz.finishedAt).toLocal());

    return SgSurface(
      kind: SgSurfaceKind.bar,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.color.ink, width: 1.5),
            ),
            // "27.5" at 200 % text is wider than the badge: it shrinks to
            // fit rather than wrap out of sight (#335, as #314's ring).
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SgText(
                  // "১৬" in Bangla, as the line beside it (#690 LQ-6).
                  l10n.digits(quizPoints(quiz.score)),
                  role: SgTextRole.label,
                  weight: 700,
                  color: tokens.color.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SgText(
                  l10n.quizLast(
                    l10n.digits(quizPoints(quiz.score)),
                    l10n.digits(quizPoints(quiz.outOf)),
                  ),
                  role: SgTextRole.body,
                  weight: 600,
                ),
                const SizedBox(height: 1),
                SgText(
                  // A Forms quiz is its own direction: "Forms · Sun 20 Sep",
                  // not "Forms · Forms · …".
                  quiz.direction == 'forms'
                      ? l10n.quizLastLineForms(date)
                      : l10n.quizLastLine(
                          kind,
                          quizDirectionName(l10n, quiz.direction, languages),
                          date,
                        ),
                  role: SgTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
