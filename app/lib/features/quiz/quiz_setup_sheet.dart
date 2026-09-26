import 'dart:math' as math;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/quiz_store.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/features/learn/step_quiz.dart';
import 'package:deutschplan/features/learn/step_words.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_digits.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'quiz_setup_sheet.g.dart';

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

/// A category L7 can offer for a step (#337): the learned words a category
/// quiz draws from it, from any step, as `DriftQuizStore` draws them, and how
/// many of those are this step's.
typedef QuizCategory = ({
  int id,
  String name,
  List<QuizWord> learned,
  int inStep,
});

/// [step]'s categories, the step's biggest first, with their learned words.
@riverpod
Future<List<QuizCategory>> quizCategories(Ref ref, String step) async {
  final store = DriftQuizStore(
    ref.watch(wordRepositoryProvider),
    ref.watch(settingsProvider),
    ref.watch(contentDaoProvider),
  );
  return <QuizCategory>[
    for (final c in await ref.watch(stepCategoriesProvider(step).future))
      await store
          .learned(QuizSource.category, ref: '${c.id}')
          .then(
            (learned) => (
              id: c.id,
              name: c.name,
              learned: learned,
              inStep: learned.where((w) => w.step == step).length,
            ),
          ),
  ];
}

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
    // The third source (#337): of the step's categories, the one with the
    // most of this step's words learned, the step's biggest on a tie. Closed,
    // with the reason, until the chosen direction can ask as many of its
    // words as L2's quizzes need: Articles asks only nouns.
    final category = ref
        .watch(quizCategoriesProvider(widget.step))
        .value
        ?.fold<QuizCategory?>(
          null,
          (best, c) => best == null || c.inStep > best.inStep ? c : best,
        );
    final categoryLearned =
        category?.learned.where((w) => applies(_direction, w)).length ?? 0;
    final categoryOpen = categoryLearned >= StepQuizTab.minimumLearned;
    // A direction that closes it takes the quiz back to the step's words.
    final source = _source == QuizSource.category && !categoryOpen
        ? QuizSource.stepLearned
        : _source;

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
      required VoidCallback? onTap,
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
                        l10n.digits(length),
                        selected: _length == length,
                        onTap: () => setState(() => _length = length),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  section(l10n.quizSetupSource, <Widget>[
                    chip(
                      l10n.quizSourceStep,
                      selected: source == QuizSource.stepLearned,
                      onTap: () =>
                          setState(() => _source = QuizSource.stepLearned),
                    ),
                    chip(
                      l10n.quizSourceAll,
                      selected: source == QuizSource.allLearned,
                      onTap: () =>
                          setState(() => _source = QuizSource.allLearned),
                    ),
                    if (category != null && categoryOpen)
                      chip(
                        category.name,
                        selected: source == QuizSource.category,
                        onTap: () =>
                            setState(() => _source = QuizSource.category),
                      )
                    else if (category != null)
                      // Closed: dimmed and announced so, as L2's quiz tiles.
                      Semantics(
                        button: true,
                        enabled: false,
                        child: Opacity(
                          opacity: 0.5,
                          child: chip(
                            category.name,
                            selected: false,
                            onTap: null,
                          ),
                        ),
                      ),
                  ]),
                  if (category != null && !categoryOpen) ...<Widget>[
                    const SizedBox(height: 6),
                    DpText(
                      l10n.quizSourceLocked(category.name, categoryLearned),
                      role: DpTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                  ],
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
                      AdaptiveTapTarget(
                        child: AdaptiveSwitch(
                          value: _timer,
                          semanticLabel: l10n.quizSetupTimer,
                          onChanged: (on) => setState(() => _timer = on),
                        ),
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
                        source: source,
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
