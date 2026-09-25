import 'dart:async';

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/words/word_row.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'step_words.g.dart';

/// A word of the step and its meaning in the learner's meaning language.
typedef StepWord = ({WordWithState word, String meaning});

/// L2's Words tab: every word of [code] in teaching order, suspended ones
/// included, as a stream — a word rated elsewhere changes its chip here.
@riverpod
Stream<List<StepWord>> stepWords(Ref ref, String code) => ref
    .watch(wordRepositoryProvider)
    .watchStep(code)
    .map((words) => withMeanings(ref, words));

/// [words] with their meanings in the learner's meaning language: English
/// where the course has no Bangla.
List<StepWord> withMeanings(Ref ref, List<WordWithState> words) {
  final bangla =
      ref.read(settingsProvider).read(SettingKeys.meaningLanguage) ==
      MeaningLanguage.bangla;
  return <StepWord>[
    for (final word in words)
      (
        word: word,
        meaning: bangla
            ? word.word.bangla ?? word.word.english
            : word.word.english,
      ),
  ];
}

/// The categories [code]'s words fall in, the biggest first: the chips
/// after the status ones.
@riverpod
Future<List<({int id, String name})>> stepCategories(Ref ref, String code) =>
    ref.watch(contentDaoProvider).stepCategories(code);

/// The Words tab's status chips.
enum WordFilter { all, todo, learning, done }

/// FR-L2-02: a status AND a category. *All* keeps suspended words, greyed;
/// a status chip shows only its own.
List<StepWord> filterWords(
  List<StepWord> words, {
  required WordFilter status,
  int? category,
}) => <StepWord>[
  for (final row in words)
    if ((category == null || row.word.word.categoryId == category) &&
        switch (status) {
          WordFilter.all => true,
          WordFilter.todo => row.word.status == WordStatus.todo,
          WordFilter.learning => row.word.status == WordStatus.learning,
          WordFilter.done => row.word.status == WordStatus.done,
        })
      row,
];

/// L2 · Words (`step-detail.md`): the status and category chips over the
/// step's words, and — when the step is not the active one — the banner
/// that starts it (FR-L2-03).
class StepWordsTab extends ConsumerStatefulWidget {
  const StepWordsTab({required this.step, super.key});

  final StepProgress step;

  @override
  ConsumerState<StepWordsTab> createState() => _StepWordsTabState();
}

class _StepWordsTabState extends ConsumerState<StepWordsTab> {
  WordFilter _status = WordFilter.all;
  int? _category;
  bool _starting = false;

  /// FR-L2-03: the current enrollment completes today and this step's
  /// opens at Settings' pace. Today's plan is left alone (BR-PLAN-08).
  ///
  /// Asked first: going back later re-enrols the old step from that day,
  /// its start date and pace overwritten, so a stray tap is not free.
  Future<void> _start(String? active) async {
    if (_starting) return;
    final l10n = AppLocalizations.of(context);
    final code = widget.step.code;
    final go = await Adaptive.showConfirm(
      context: context,
      title: l10n.stepStartConfirmTitle(code),
      message: active == null
          ? l10n.stepStartConfirmFirst
          : l10n.stepStartConfirm(active),
      confirmLabel: l10n.stepStart,
      cancelLabel: l10n.stepStartCancel,
    );
    if (go != true || !mounted) return;
    setState(() => _starting = true);
    final settings = ref.read(settingsProvider);
    try {
      await ref
          .read(planEngineProvider)
          .switchStep(
            widget.step.code,
            ref.read(todayProvider),
            dailyNew: settings.read(SettingKeys.dailyNew),
            studyDaysMask: settings.read(SettingKeys.studyDaysMask),
          );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final code = widget.step.code;
    final words = ref.watch(stepWordsProvider(code)).value;
    final categories =
        ref.watch(stepCategoriesProvider(code)).value ??
        const <({int id, String name})>[];
    final active = ref
        .watch(stepProgressProvider)
        .value
        ?.where((step) => step.active)
        .firstOrNull;
    final shown = words == null
        ? const <StepWord>[]
        : filterWords(words, status: _status, category: _category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!widget.step.active)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: StartBanner(
              message: active == null
                  ? l10n.stepStartBannerFirst(code)
                  : l10n.stepStartBanner(active.code, code),
              onStart: _starting ? null : () => unawaited(_start(active?.code)),
            ),
          ),
        // Sized by its chips, not a fixed height: at 200 % text they grow,
        // and a fixed box would cut them (#314).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              for (final (filter, label) in <(WordFilter, String)>[
                (WordFilter.all, l10n.stepFilterAll),
                (WordFilter.todo, l10n.wordStatusToDo),
                (WordFilter.learning, l10n.wordStatusLearning),
                (WordFilter.done, l10n.wordStatusDone),
              ]) ...<Widget>[
                DpChip(
                  label: label,
                  kind: DpChipKind.filter,
                  selected: _status == filter,
                  onTap: () => setState(() => _status = filter),
                ),
                const SizedBox(width: 8),
              ],
              for (final category in categories) ...<Widget>[
                DpChip(
                  label: category.name,
                  kind: DpChipKind.filter,
                  selected: _category == category.id,
                  // A second tap lets the category go again.
                  onTap: () => setState(
                    () => _category = _category == category.id
                        ? null
                        : category.id,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: words == null
              ? const SizedBox.expand()
              : shown.isEmpty
              ? Center(
                  child: DpText(
                    l10n.stepWordsNone,
                    role: DpTextRole.body,
                    color: tokens.color.textSecondary,
                  ),
                )
              : WordListPanel(
                  // FR-L2-02: built as it scrolls, every row the height of
                  // the first: 64 dp, or more at large text (#314). The key
                  // keeps the place across a trip to W1 and back.
                  child: ListView.builder(
                    key: PageStorageKey<String>('step-words-$code'),
                    padding: EdgeInsets.zero,
                    // Its panel ends at the last row (#282): the extent is
                    // the prototype's times the count, so nothing more is built.
                    shrinkWrap: true,
                    prototypeItem: shown.isEmpty
                        ? null
                        : WordRow(
                            word: shown.first.word,
                            meaning: shown.first.meaning,
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
}

/// "You're in A1.2 — start A2.1 now?" with *Start*.
class StartBanner extends StatelessWidget {
  const StartBanner({required this.message, required this.onStart, super.key});

  final String message;

  /// Null while a start is under way.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    return DpSurface(
      kind: DpSurfaceKind.tint(tokens.color.accent),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(child: DpText(message, role: DpTextRole.body, weight: 600)),
          const SizedBox(width: 12),
          DpButton(
            label: l10n.stepStart,
            compact: true,
            expand: false,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}
