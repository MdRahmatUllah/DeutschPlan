import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_chip.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/aurora_backdrop.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/domain/placement.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// S3 · the placement check. `Placement-android.html`, `placement.md`.
///
/// Up to twenty questions that walk the course (FR-S3-01), drawn with one
/// seed for the session (FR-S3-02). It only reads: nothing reaches
/// `word_state` (FR-S3-03), and closing it hands back nothing (FR-S3-04).
class PlacementScreen extends ConsumerStatefulWidget {
  const PlacementScreen({required this.onDone, super.key, this.seed});

  /// With the step to suggest, or null when the learner closed the check.
  final void Function(String? step) onDone;

  /// A test's fixed seed; a real session takes one from the clock.
  final int? seed;

  @override
  ConsumerState<PlacementScreen> createState() => PlacementScreenState();
}

class PlacementScreenState extends ConsumerState<PlacementScreen> {
  PlacementSession? _session;
  PlacementItem? _item;

  /// Set when the check is over: the result screen replaces the question.
  PlacementResult? _result;

  /// The item on screen, so a test can answer it right or wrong on purpose.
  @visibleForTesting
  PlacementItem? get currentItem => _item;

  /// The result once the check is over, so a test can read what it shows.
  @visibleForTesting
  PlacementResult? get currentResult => _result;
  int? _picked;
  bool _loading = true;

  /// Each step's words, read once — the walk comes back to the same steps.
  final Map<String, List<PlacementWord>> _pools =
      <String, List<PlacementWord>>{};

  @override
  void initState() {
    super.initState();
    // After the first frame: a check that cannot start ends at once, and
    // ending navigates — which cannot happen in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final steps = await ref.read(courseStepsProvider.future);
      _session = PlacementSession(
        steps: <String>[for (final step in steps) step.code],
        seed: widget.seed ?? ref.read(clockProvider)().microsecondsSinceEpoch,
        // Page 2's choice: Bangla meanings for a learner who reads them in
        // Bangla. Both keeps English, which keeps the options short.
        useBangla:
            ref.read(languagesProvider).meaning == MeaningLanguage.bangla,
      );
      await _advance();
    } on Object {
      // No course to read, no check to run: back to page 3 as a close would
      // be, with nothing chosen (FR-S3-04), rather than a blank screen.
      if (mounted) widget.onDone(null);
    }
  }

  Future<List<PlacementWord>> _pool(String step) async =>
      _pools[step] ??= await ref.read(contentDaoProvider).placementPool(step);

  /// Draws the next item, or ends the check. A step whose words cannot make
  /// one — too few of them — ends it there too, suggesting that step.
  Future<void> _advance() async {
    final session = _session!;
    if (!mounted) return;
    setState(() => _loading = true);

    PlacementItem? next;
    if (!session.finished) next = session.next(await _pool(session.step));
    if (!mounted) return;

    if (next == null) {
      setState(() {
        _result = session.result();
        _loading = false;
      });
      return;
    }
    setState(() {
      _item = next;
      _picked = null;
      _loading = false;
    });
  }

  void _submit() {
    // Two taps in one frame would answer twice: the button only greys out
    // once the next frame is built. And with the step's words already read,
    // the next item arrives between the two taps — so the second finds
    // nothing picked, not a check still loading, and would count as wrong.
    if (_loading || _picked == null) return;
    _loading = true;
    final item = _item!;
    _session!.answer(item, correct: _picked == item.answer);
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = _item;
    final answered = _session?.answered ?? 0;
    final result = _result;

    final body = result != null
        ? PlacementResultView(result: result, onDone: widget.onDone)
        : SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TopBar(
                  title: l10n.placementQuestionOf(
                    answered + 1,
                    PlacementSession.maxItems,
                  ),
                  closeLabel: l10n.placementClose,
                  onClose: () => widget.onDone(null),
                ),
                // The question on screen, as the artboard fills it: question 4 of
                // 20 is a fifth of the way.
                _Progress(fraction: (answered + 1) / PlacementSession.maxItems),
                Expanded(
                  child: item == null
                      ? const SizedBox()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                          child: _Question(
                            item: item,
                            picked: _picked,
                            onPick: _loading
                                ? null
                                : (index) => setState(() => _picked = index),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: DpButton(
                    label: l10n.placementNext,
                    onPressed: _picked == null || _loading ? null : _submit,
                  ),
                ),
              ],
            ),
          );

    return PlacementFrame(child: body);
  }
}

/// The paper both S3 screens sit on. Under glass it is the aurora, led by
/// page 3's Raspberry, which is where the check was opened from — glass has
/// no paper of its own, and without it the screen is black.
class PlacementFrame extends StatelessWidget {
  const PlacementFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AdaptiveScaffold(
      backgroundColor: tokens.isGlass
          ? tokens.surface.paper.withValues(alpha: 0)
          : tokens.surface.paper,
      body: tokens.isGlass
          ? AuroraBackdrop(leading: tokens.color.die, child: child)
          : child,
    );
  }
}

/// Close, and "Question 4 of 20".
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.closeLabel,
    required this.onClose,
  });

  final String title;
  final String closeLabel;
  final VoidCallback onClose;

  static const double side = 48;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: <Widget>[
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: closeLabel,
          excludeSemantics: true,
          onTap: onClose,
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.square(
              dimension: side,
              child: Icon(Icons.close, color: context.tokens.color.ink),
            ),
          ),
        ),
        Expanded(
          child: DpText(
            title,
            role: DpTextRole.bodyLarge,
            weight: 600,
            textAlign: TextAlign.center,
          ),
        ),
        // Balances the close button, so the title sits in the middle.
        const SizedBox(width: side + 8),
      ],
    ),
  );
}

/// The Raspberry bar under the top bar: how far through the twenty.
class _Progress extends StatelessWidget {
  const _Progress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: tokens.surface.muted),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: ColoredBox(color: tokens.color.die),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One item: its tag, its prompt, the word or sentence, and the options.
class _Question extends ConsumerWidget {
  const _Question({
    required this.item,
    required this.picked,
    required this.onPick,
  });

  final PlacementItem item;
  final int? picked;
  final void Function(int)? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    final word = item.word;

    final (tag, ask) = switch (item.kind) {
      PlacementKind.meaning => (
        l10n.placementTagMeaning(item.level),
        l10n.placementAskMeaning,
      ),
      PlacementKind.article => (
        l10n.placementTagArticle(item.level),
        l10n.placementAskArticle,
      ),
      PlacementKind.gap => (
        l10n.placementTagGap(item.level),
        l10n.placementAskGap,
      ),
    };

    // The gender colour on the article, as every German noun in the app is
    // written. An article item hides it: that is the question.
    final articleColour = switch (word.article) {
      'der' => tokens.color.derText,
      'die' => tokens.color.dieText,
      'das' => tokens.color.dasText,
      _ => tokens.color.ink,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DpChip(label: tag, kind: DpChipKind.status),
        const SizedBox(height: 10),
        DpText(ask, role: DpTextRole.body, color: tokens.color.textSecondary),
        const SizedBox(height: 10),
        if (item.kind == PlacementKind.gap)
          DpText(item.sentence!, role: DpTextRole.title, weight: 600)
        else
          Row(
            children: <Widget>[
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (word.article != null &&
                          item.kind != PlacementKind.article)
                        TextSpan(
                          text: '${word.article} ',
                          style: TextStyle(color: articleColour),
                        ),
                      TextSpan(text: word.german),
                    ],
                  ),
                  style: DpText.styleFor(
                    tokens,
                    DpTextRole.display,
                    color: tokens.color.ink,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              DpSpeakerButton(
                size: 48,
                semanticLabel: l10n.placementPronounce,
                onPressed: () => ref.read(systemTtsProvider).speak(word.german),
              ),
            ],
          ),
        const SizedBox(height: 20),
        for (final (index, option) in item.options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              selected: picked == index,
              button: true,
              inMutuallyExclusiveGroup: true,
              child: DpSurface(
                kind: DpSurfaceKind.bar,
                selected: picked == index,
                radius: tokens.shape.button,
                onTap: onPick == null ? null : () => onPick!(index),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DpText(
                      option,
                      role: DpTextRole.bodyLarge,
                      weight: 600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        DpText(
          l10n.placementRule,
          role: DpTextRole.caption,
          color: tokens.color.textSecondary,
        ),
      ],
    );
  }
}

/// S3's result. `PlacementResult-android.html`.
///
/// The score, the step to suggest, why, how each area went, and the two ways
/// out: take the suggestion back to page 3, or go back and choose.
class PlacementResultView extends StatelessWidget {
  const PlacementResultView({
    required this.result,
    required this.onDone,
    super.key,
  });

  final PlacementResult result;
  final void Function(String? step) onDone;

  /// Lime from nine in ten, Sun below — the artboard's 9/10 and 5/5 are
  /// Lime and its 4/5 is Sun.
  static bool strong(int correct, int total) =>
      total > 0 && correct / total >= 0.9;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;
    // A score pill: Lime when the area went well, Sun when it went partly.
    Color fill(int correct, int total) =>
        strong(correct, total) ? tokens.color.easy : tokens.color.accent;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(
            title: l10n.placementResultTitle,
            closeLabel: l10n.placementClose,
            onClose: () => onDone(null),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DpSurface(
                      // The paper card has the artboard's 2 px ink edge; the
                      // glass one is a plain panel.
                      selected: !tokens.isGlass,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        children: <Widget>[
                          DpPill(
                            label: l10n.placementScore(
                              result.correct,
                              result.answered,
                            ),
                            fill: fill(result.correct, result.answered),
                            small: true,
                          ),
                          const SizedBox(height: 14),
                          DpText(
                            l10n.placementSuggest.toUpperCase(),
                            semanticsLabel: l10n.placementSuggest,
                            role: DpTextRole.caption,
                            weight: 700,
                            letterSpacing: 0.6,
                            color: tokens.color.textSecondary,
                          ),
                          const SizedBox(height: 14),
                          DpText(
                            result.step,
                            role: DpTextRole.display,
                            weight: 700,
                          ),
                          const SizedBox(height: 14),
                          DpText(
                            l10n.placementRationale(result.step),
                            role: DpTextRole.body,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: <Widget>[
                              for (final area in result.areas)
                                DpPill(
                                  label: area.area == PlacementSession.articles
                                      ? l10n.placementAreaArticles(
                                          area.correct,
                                          area.total,
                                        )
                                      : l10n.placementAreaWords(
                                          area.area,
                                          area.correct,
                                          area.total,
                                        ),
                                  fill: fill(area.correct, area.total),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // BR-COURSE-04: starting further on marks nothing known.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DpText(
                        l10n.placementBrowsable,
                        role: DpTextRole.caption,
                        color: tokens.color.textSecondary,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DpButton(
                  label: l10n.placementUse(result.step),
                  onPressed: () => onDone(result.step),
                ),
                const SizedBox(height: 8),
                DpButton(
                  label: l10n.placementChooseMyself,
                  onPressed: () => onDone(null),
                  kind: DpButtonKind.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
