import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The six directions L7 offers. Forms has its own tile on L2.
const List<QuizDirection> customDirections = <QuizDirection>[
  QuizDirection.deEn,
  QuizDirection.deBn,
  QuizDirection.enDe,
  QuizDirection.articles,
  QuizDirection.listening,
  QuizDirection.mixed,
];

/// BR-QUIZ-01's lengths.
const List<int> quizLengths = <int>[10, 20, 30];

/// The quiz L7's *Start* builds, for any of its combinations.
QuizArgs customQuiz({
  required QuizDirection direction,
  required int length,
  required QuizSource source,
  required String step,
  required bool timer,
  int? category,
  int? seed,
}) => QuizArgs(
  direction: direction.name,
  source: source.name,
  sourceRef: switch (source) {
    QuizSource.stepLearned => step,
    // A wrong call fails here, not as a quietly empty quiz for category "null".
    QuizSource.category =>
      category == null ? throw ArgumentError.notNull('category') : '$category',
    QuizSource.allLearned || QuizSource.compareSet => null,
  },
  length: length,
  timer: timer,
  seed: seed ?? math.Random().nextInt(1 << 31),
);

/// L7 · Custom quiz (`quiz.md`, `QuizSetup-android.html`): direction, length,
/// source and timer, then *Start quiz · 20 questions*. Opened from L2's
/// *Custom* tile; pops the [QuizArgs] it built, and the tab starts the quiz.
class QuizSetupSheet extends ConsumerStatefulWidget {
  const QuizSetupSheet({required this.step, super.key});

  /// The step whose Quiz tab opened it.
  final String step;

  /// The artboard's sheet: 560 dp, the button at its foot.
  static const double height = 560;

  /// Opens the sheet over [context] and resolves to the quiz it built, or
  /// null if it was dismissed.
  static Future<QuizArgs?> show(BuildContext context, String step) {
    // The sheet is a route of its own; it carries the opener's providers
    // with it, wherever the scope sits above the navigator.
    final container = ProviderScope.containerOf(context);
    return Adaptive.showSheet<QuizArgs>(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: QuizSetupSheet(step: step),
      ),
    );
  }

  @override
  ConsumerState<QuizSetupSheet> createState() => _QuizSetupSheetState();
}

class _QuizSetupSheetState extends ConsumerState<QuizSetupSheet> {
  QuizDirection _direction = QuizDirection.deEn;
  int _length = 20;
  QuizSource _source = QuizSource.stepLearned;
  bool _timer = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // The third source is the step's main category — the one most of its
    // words fall in, as L2's category chips put first.
    final category = ref
        .watch(stepCategoriesProvider(widget.step))
        .value
        ?.firstOrNull;

    Widget section(String label, List<Widget> chips) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DpText(
          label.toUpperCase(),
          role: DpTextRole.caption,
          weight: 700,
          letterSpacing: 0.6,
          color: tokens.color.textSecondary,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );

    DpChip chip(
      String label, {
      required bool selected,
      required VoidCallback onTap,
    }) => DpChip(
      label: label,
      kind: DpChipKind.filter,
      selected: selected,
      onTap: onTap,
    );

    return SizedBox(
      height: math.min(
        QuizSetupSheet.height,
        MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: CustomScrollView(
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: tokens.surface.muted,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  DpText(l10n.quizSetupTitle, role: DpTextRole.title),
                  const SizedBox(height: 4),
                  section(l10n.quizSetupDirection, <Widget>[
                    for (final direction in customDirections)
                      chip(
                        quizDirectionName(l10n, direction.name),
                        selected: _direction == direction,
                        onTap: () => setState(() => _direction = direction),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  section(l10n.quizSetupLength, <Widget>[
                    for (final length in quizLengths)
                      chip(
                        '$length',
                        selected: _length == length,
                        onTap: () => setState(() => _length = length),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  section(l10n.quizSetupSource, <Widget>[
                    chip(
                      l10n.quizSourceStep,
                      selected: _source == QuizSource.stepLearned,
                      onTap: () =>
                          setState(() => _source = QuizSource.stepLearned),
                    ),
                    chip(
                      l10n.quizSourceAll,
                      selected: _source == QuizSource.allLearned,
                      onTap: () =>
                          setState(() => _source = QuizSource.allLearned),
                    ),
                    if (category != null)
                      chip(
                        category.name,
                        selected: _source == QuizSource.category,
                        onTap: () =>
                            setState(() => _source = QuizSource.category),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            DpText(
                              l10n.quizSetupTimer,
                              role: DpTextRole.body,
                              weight: 500,
                            ),
                            const SizedBox(height: 1),
                            DpText(
                              _timer
                                  ? l10n.quizSetupTimerOn
                                  : l10n.quizSetupTimerOff,
                              role: DpTextRole.caption,
                              color: tokens.color.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AdaptiveSwitch(
                        value: _timer,
                        semanticLabel: l10n.quizSetupTimer,
                        onChanged: (on) => setState(() => _timer = on),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(height: 16),
                  DpButton(
                    label: l10n.quizStart(l10n.quizQuestions(_length)),
                    onPressed: () => Navigator.of(context).pop(
                      customQuiz(
                        direction: _direction,
                        length: _length,
                        source: _source,
                        step: widget.step,
                        category: category?.id,
                        timer: _timer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
