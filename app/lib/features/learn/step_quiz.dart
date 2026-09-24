import 'dart:async';
import 'dart:math' as math;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/plan_engine.dart' show parsePlanDate;
import 'package:deutschplan/features/quiz/quiz_setup_sheet.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'step_quiz.g.dart';

/// The step's latest finished quiz, for L2's last quiz card.
@riverpod
Stream<LastQuiz?> lastStepQuiz(Ref ref, String code) =>
    ref.watch(examRepositoryProvider).watchLastStepQuiz(code);

/// The quiz a tile starts (FR-L2-04): from this step's learned words,
/// DE → EN unless it is *Forms*.
QuizArgs stepQuiz(
  String code, {
  required int length,
  String direction = 'deEn',
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

    void start(int length, [String direction = 'deEn']) => QuizRoute.open(
      context,
      stepQuiz(step.code, length: length, direction: direction),
    );

    return ListView(
      key: PageStorageKey<String>('step-quiz-${step.code}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: <Widget>[
        DpText(
          open ? l10n.quizTilesCaption.toUpperCase() : l10n.quizLocked(learned),
          role: DpTextRole.caption,
          weight: open ? 700 : 400,
          letterSpacing: open ? 0.6 : null,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            for (final (i, (label, length)) in <(String, int)>[
              (l10n.quizQuick, 10),
              (l10n.quizStandard, 20),
              (l10n.quizLong, 30),
            ].indexed) ...<Widget>[
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
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: QuizTile(
                  title: l10n.quizForms,
                  subtitle: l10n.quizFormsLine,
                  onTap: open ? () => start(20, 'forms') : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuizTile(
                  title: l10n.quizCustom,
                  subtitle: l10n.quizCustomLine,
                  onTap: open ? () => unawaited(_custom(context)) : null,
                ),
              ),
            ],
          ),
        ),
        if (last != null) ...<Widget>[
          const SizedBox(height: 10),
          LastQuizCard(quiz: last),
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
    final tile = DpSurface(
      kind: DpSurfaceKind.bar,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        crossAxisAlignment: centred
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          DpText(
            title,
            role: DpTextRole.bodyLarge,
            weight: 600,
            textAlign: align,
            color: enabled ? null : tokens.color.textSecondary,
          ),
          const SizedBox(height: 4),
          DpText(
            subtitle,
            role: DpTextRole.caption,
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
/// Lime from 80 %, Sun from 50 %, Coral under.
class LastQuizCard extends StatelessWidget {
  const LastQuizCard({required this.quiz, super.key});

  final LastQuiz quiz;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final share = quiz.outOf == 0 ? 0.0 : quiz.score / quiz.outOf;
    final colour = share >= 0.8
        ? tokens.color.easy
        : share >= 0.5
        ? tokens.color.learning
        : tokens.color.again;
    final kind = switch (quiz.length) {
      10 => l10n.quizQuick,
      20 => l10n.quizStandard,
      30 => l10n.quizLong,
      _ => l10n.quizCustom,
    };
    final date = DateFormat(
      'EEE d MMM',
      Localizations.localeOf(context).toString(),
    ).format(parsePlanDate(quiz.finishedAt.substring(0, 10)));

    return DpSurface(
      kind: DpSurfaceKind.bar,
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
            child: DpText(
              '${quiz.score}',
              role: DpTextRole.label,
              weight: 700,
              color: tokens.color.onAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DpText(
                  l10n.quizLast(quiz.score, quiz.outOf),
                  role: DpTextRole.body,
                  weight: 600,
                ),
                const SizedBox(height: 1),
                DpText(
                  // A Forms quiz is its own direction: "Forms · Sun 20 Sep",
                  // not "Forms · Forms · …".
                  quiz.direction == 'forms'
                      ? l10n.quizLastLineForms(date)
                      : l10n.quizLastLine(
                          kind,
                          quizDirectionName(l10n, quiz.direction),
                          date,
                        ),
                  role: DpTextRole.caption,
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

/// A quiz direction as the app names it: "DE → EN", "Articles".
String quizDirectionName(AppLocalizations l10n, String direction) =>
    switch (direction) {
      'deEn' => 'DE → EN',
      'deBn' => 'DE → বাংলা',
      'enDe' => 'EN → DE',
      'articles' => l10n.quizDirectionArticles,
      'listening' => l10n.quizDirectionListening,
      'forms' => l10n.quizForms,
      _ => l10n.quizDirectionMixed,
    };
