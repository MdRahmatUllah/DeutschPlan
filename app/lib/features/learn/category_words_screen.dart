import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/components/sg_progress_ring.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/learn/categories_screen.dart';
import 'package:sogda/features/learn/step_quiz.dart';
import 'package:sogda/features/learn/step_words.dart';
import 'package:sogda/features/quiz/quiz_setup_sheet.dart'
    show meaningDirection;
import 'package:sogda/features/words/word_row.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/router/routes.dart';

part 'category_words_screen.g.dart';

/// L6's rows: every word of category [id], suspended ones included, by step,
/// then frequency, then reading order (FR-L6-01).
@riverpod
Stream<List<StepWord>> categoryWords(Ref ref, int id) => ref
    .watch(wordRepositoryProvider)
    .watchCategory(id)
    .map((words) => withMeanings(ref, words));

/// L6's level chips: All · A1 · A2 · B1 · B2+, where B2+ is B2 to C2.
enum LevelFilter {
  all(<String>{}),
  a1(<String>{'A1'}),
  a2(<String>{'A2'}),
  b1(<String>{'B1'}),
  b2Plus(<String>{'B2', 'C1', 'C2'});

  const LevelFilter(this.levels);

  final Set<String> levels;

  /// The chip's label: course text, the same in every UI language.
  String get code => switch (this) {
    LevelFilter.all => '',
    LevelFilter.b2Plus => 'B2+',
    _ => levels.single,
  };

  bool holds(StepWord row) =>
      this == LevelFilter.all || levels.contains(row.word.word.levelCode);
}

/// FR-L6-02: the quiz L6's *Quiz* starts, from the category's learned words,
/// in the learner's meaning direction (#667).
QuizArgs categoryQuiz(int id, {String direction = 'deEn'}) => QuizArgs(
  direction: direction,
  source: 'category',
  sourceRef: '$id',
  seed: math.Random().nextInt(1 << 31),
);

/// "A1.1 → C2.2" over [rows], in their order; one step alone.
String stepRange(List<StepWord> rows) {
  final first = rows.first.word.word.sublevelCode;
  final last = rows.last.word.word.sublevelCode;
  return first == last ? first : '$first → $last';
}

/// L6 · Category words (`categories.md`, `CategoryWords-android.html`): one
/// category across all the steps, under a level filter, with *Quiz*.
class CategoryWordsScreen extends ConsumerStatefulWidget {
  const CategoryWordsScreen({required this.id, super.key});

  final int id;

  @override
  ConsumerState<CategoryWordsScreen> createState() =>
      _CategoryWordsScreenState();
}

class _CategoryWordsScreenState extends ConsumerState<CategoryWordsScreen> {
  LevelFilter _filter = LevelFilter.all;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final category = ref
        .watch(categoriesProvider)
        .value
        ?.where((category) => category.id == widget.id)
        .firstOrNull;
    final wordsState = ref.watch(categoryWordsProvider(widget.id));
    final words = wordsState.value;
    final learned = (category?.learning ?? 0) + (category?.done ?? 0);

    final Widget body;
    if (words == null) {
      body = wordsState.hasError
          ? SgLoadFailed(
              message: l10n.learnLoadFailed,
              onRetry: () => ref.invalidate(categoryWordsProvider(widget.id)),
            )
          : const SizedBox.expand();
    } else {
      final shown = words.where(_filter.holds).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (category != null && words.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SgText(
                    l10n.categoryWordsLine(category.words, stepRange(words)),
                    role: SgTextRole.label,
                    weight: 400,
                    color: tokens.color.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  SgSegmentedBar(
                    done: category.done,
                    learning: category.learning,
                    todo: category.todo,
                  ),
                ],
              ),
            ),
          // Sized by its chips, not a fixed height: at 200 % text they grow,
          // and a fixed box would cut them (#314).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 8 above and below: a 32 dp chip's 48 dp target fits inside
            // the scroll view, which cuts what reaches past it (#853).
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: <Widget>[
                for (final filter in LevelFilter.values) ...<Widget>[
                  SgChip(
                    label: filter == LevelFilter.all
                        ? l10n.stepFilterAll
                        : filter.code,
                    kind: SgChipKind.filter,
                    selected: _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
                  // A1 and A2 are narrow chips whose 48 dp targets reach
                  // about 6 dp past them: 14 keeps neighbours apart (#853).
                  const SizedBox(width: 14),
                ],
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: SgText(
                      l10n.stepWordsNone,
                      role: SgTextRole.body,
                      color: tokens.color.textSecondary,
                    ),
                  )
                : WordListPanel(
                    // Built as it scrolls, every row the height of the first:
                    // 64 dp, or more at large text (#314). Past 130 % a row
                    // stacks and wraps to its own height (#550). The key
                    // keeps the place across a trip to W1 and back.
                    child: ListView.builder(
                      key: PageStorageKey<String>('category-${widget.id}'),
                      padding: EdgeInsets.zero,
                      // Its panel ends at the last row (#282): the extent is
                      // the prototype's times the count, so nothing more is built.
                      shrinkWrap: WordListPanel.shrinkWrap(
                        context,
                        shown.length,
                      ),
                      prototypeItem: shown.isEmpty || SgScript.large(context)
                          ? null
                          : WordRow(
                              word: shown.first.word,
                              meaning: shown.first.meaning,
                              step: shown.first.word.word.sublevelCode,
                              last: false,
                              onPanel: true,
                            ),
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final row = shown[index];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => WordRoute.open(context, row.word.uid),
                          child: WordRow(
                            word: row.word,
                            meaning: row.meaning,
                            step: row.word.word.sublevelCode,
                            last: index == shown.length - 1,
                            onPanel: true,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      );
    }

    final scaffold = AdaptiveScaffold(
      title: category?.name ?? '',
      leading: AdaptiveBackButton(
        label: l10n.categoriesBack,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: <Widget>[
        // Closed until the category has words to quiz, as L2's tiles are.
        SgButton(
          label: l10n.stepTabQuiz,
          kind: SgButtonKind.text,
          expand: false,
          onPressed: learned < StepQuizTab.minimumLearned
              ? null
              : () => QuizRoute.open(
                  context,
                  categoryQuiz(
                    widget.id,
                    direction: meaningDirection(ref).name,
                  ),
                ),
        ),
        // The artboard's 8 dp bar inset and the link's own 10.
        const SizedBox(width: 18),
      ],
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: body,
    );
    return tokens.isGlass
        ? AuroraBackdrop(leading: tokens.color.accent, child: scaffold)
        : scaffold;
  }
}
