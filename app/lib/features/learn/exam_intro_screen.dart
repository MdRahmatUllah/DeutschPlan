import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_feedback.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/aurora_backdrop.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/domain/exam_generator.dart';
import 'package:sogda/features/learn/step_exams.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/l10n/ui_digits.dart';
import 'package:sogda/router/routes.dart';

part 'exam_intro_screen.g.dart';

/// What L11 shows of a mock: its best finished score, the pass mark,
/// whether the paper has listening, and the timer's default.
typedef ExamIntro = ({
  SeedSummary? best,
  int passPercent,
  bool listening,
  bool timer,
});

@riverpod
Future<ExamIntro> examIntro(Ref ref, String step, int seed) async {
  final settings = ref.watch(settingsProvider);
  // Followed, as L10's hub is: the Learn tab keeps L11 alive while Settings
  // moves the pass mark, listening or the timer's default.
  final changes = settings.changes
      .where(
        (key) =>
            key == SettingKeys.examPassPercent ||
            key == SettingKeys.listeningQuestions ||
            key == SettingKeys.examTimerDefault,
      )
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  final seeds = await ref.watch(examSeedsProvider(step).future);
  return (
    best: seeds.where((s) => s.seed == seed).firstOrNull,
    passPercent: settings.read(SettingKeys.examPassPercent),
    listening: settings.read(SettingKeys.listeningQuestions),
    timer: settings.read(SettingKeys.examTimerDefault),
  );
}

/// FR-L10-03's *Begin exam*: the paper and the attempt, in
/// `ExamRepository.start`. The state is whether one is being begun, so a
/// second tap while it runs begins nothing.
@riverpod
class ExamStart extends _$ExamStart {
  @override
  bool build() => false;

  /// The attempt's id, or null when one is already being begun. [timer] is
  /// L11's switch, kept as `exam_timer` for L12 to read, fresh or resumed.
  Future<int?> begin(String step, int seed, {required bool timer}) async {
    if (state) return null;
    state = true;
    try {
      final settings = ref.read(settingsProvider);
      final exams = ref.read(examRepositoryProvider);
      // The unfinished attempt `begin` abandons for this one (#671).
      final replaced = <int>[
        for (final a in await exams.inProgressBySeed(step).get())
          if (a.seed == seed) a.id,
      ];
      final id = await exams.start(
        step: step,
        seed: seed,
        listening: settings.read(SettingKeys.listeningQuestions),
        // #1120: in the learner's first meaning language.
        lang: meaningChoiceOf(settings).primary,
        startedAt: ref.read(clockProvider)().toUtc().toIso8601String(),
      );
      // Only once the attempt exists: a failed start must not change the
      // timer another mock resumes with.
      await settings.write(SettingKeys.examTimer, timer);
      // Its recording goes: nothing opens an abandoned attempt again. Best
      // effort, since the new attempt is begun either way.
      try {
        await ref.read(modelRepositoryProvider).deleteRecordings(replaced);
      } on Object catch (error) {
        debugPrint('exam: old recording not deleted: $error');
      }
      return id;
    } finally {
      state = false;
    }
  }
}

/// L11 · Exam intro (`exam-hub.md`, `ExamIntro-android.html`): the mock
/// before it starts — its size, the pass mark and the best so far, the
/// sections in order, the rules, the timer, and *Begin exam*.
class ExamIntroScreen extends ConsumerStatefulWidget {
  const ExamIntroScreen({required this.step, required this.seed, super.key});

  final String step;
  final int seed;

  @override
  ConsumerState<ExamIntroScreen> createState() => _ExamIntroScreenState();
}

class _ExamIntroScreenState extends ConsumerState<ExamIntroScreen> {
  /// The switch, once the learner has moved it; the setting's until then.
  bool? _timer;

  Future<void> _begin(bool timer) async {
    final l10n = AppLocalizations.of(context);
    try {
      final id = await ref
          .read(examStartProvider.notifier)
          .begin(widget.step, widget.seed, timer: timer);
      if (id != null && mounted) ExamRoute.open(context, id);
      // Any throw, not only an Exception: a deep link's seed outside 1..3
      // fails the paper with a RangeError (#694 CC-3).
    } on Object catch (error) {
      debugPrint('exam start: $error');
      if (mounted) SgToast.show(context, l10n.examIntroFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final introState = ref.watch(examIntroProvider(widget.step, widget.seed));
    final intro = introState.value;
    final busy = ref.watch(examStartProvider);
    final title = l10n.examIntroTitle(widget.step, widget.seed);

    final Widget body;
    if (intro == null) {
      body = introState.hasError
          ? SgLoadFailed(
              message: l10n.learnLoadFailed,
              onRetry: () =>
                  ref.invalidate(examIntroProvider(widget.step, widget.seed)),
            )
          : const SizedBox.expand();
    } else {
      final timer = _timer ?? intro.timer;
      final best = intro.best;
      final line = <String>[
        l10n.examHubLine(examQuestions, examMinutes),
        l10n.examIntroPassMark(intro.passPercent),
        if (best != null && best.finished > 0)
          // Down, as L10's card: a fail never reads as the mark.
          l10n.examIntroBest(best.bestPercent.floor(), best.attempts),
      ].join(' · ');
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: <Widget>[
          SgText(title, role: SgTextRole.headline),
          const SizedBox(height: 4),
          SgText(
            line,
            role: SgTextRole.caption,
            color: tokens.color.textSecondary,
          ),
          const SizedBox(height: 12),
          _Card(
            heading: l10n.examIntroSections,
            child: _Sections(listening: intro.listening),
          ),
          const SizedBox(height: 12),
          _Card(
            heading: l10n.examIntroRules,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final rule in <String>[
                  l10n.examIntroRuleFeedback,
                  l10n.examIntroRuleFlag,
                  l10n.examIntroRulePause,
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.check,
                          size: 18,
                          color: tokens.color.correctText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: SgText(rule, role: SgTextRole.body)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SgText(
                        l10n.examIntroTimer,
                        role: SgTextRole.body,
                        weight: 500,
                      ),
                      const SizedBox(height: 1),
                      SgText(
                        l10n.examIntroTimerLine(examMinutes),
                        role: SgTextRole.caption,
                        color: tokens.color.textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AdaptiveTapTarget(
                  child: AdaptiveSwitch(
                    value: timer,
                    semanticLabel: l10n.examIntroTimer,
                    onChanged: (on) => setState(() => _timer = on),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SgButton(
            label: l10n.examIntroBegin,
            onPressed: busy ? null : () => _begin(timer),
          ),
        ],
      );
    }

    final scaffold = AdaptiveScaffold(
      // ExamIntro-ios: "‹ A1.2" and "Mock 2" in the bar, the step and mock in
      // the heading. Android's bar has room for both.
      title: context.isCupertino ? l10n.examHubMock(widget.seed) : title,
      leading: AdaptiveBackButton(
        label: widget.step,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
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

/// A card with an upper-case heading.
class _Card extends StatelessWidget {
  const _Card({required this.heading, required this.child});

  final String heading;
  final Widget child;

  @override
  Widget build(BuildContext context) => SgSurface(
    kind: SgSurfaceKind.bar,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: SgText(
            heading.toUpperCase(),
            role: SgTextRole.caption,
            weight: 700,
            letterSpacing: 0.6,
            color: context.tokens.color.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

/// The paper's sections in order, two to a row, each with its questions;
/// Writing and Speaking marked self-assessed (BR-EXAM-06).
class _Sections extends StatelessWidget {
  const _Sections({required this.listening});

  final bool listening;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final sections = <(ExamSection, int)>[
      for (final section in ExamSection.values)
        if (sectionCount(section, listening: listening) case final n when n > 0)
          (section, n),
    ];

    Widget cell((ExamSection, int) entry) {
      final (section, count) = entry;
      final selfAssessed = section.points > 1;
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: <Widget>[
            // The name takes the cell, the count its end. "self-assessed"
            // follows the name, and wraps under it where the two don't fit
            // (Speaking on a phone, Bangla, large text): nothing is cut.
            Expanded(
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  // The artboard's 14 px sits between label and body.
                  SgText(
                    examSectionName(l10n, section),
                    role: SgTextRole.label,
                    weight: 400,
                  ),
                  if (selfAssessed)
                    SgText(
                      l10n.examIntroSelfAssessed,
                      role: SgTextRole.caption,
                      color: tokens.color.textSecondary,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SgText(
              AppLocalizations.of(context).digits(count),
              role: SgTextRole.label,
              weight: 700,
            ),
          ],
        ),
      );
    }

    // Past 130 % text two columns broke "Vocabulary" mid-word (#165): one.
    if (SgScript.large(context)) {
      return Column(
        children: <Widget>[for (final entry in sections) cell(entry)],
      );
    }
    return Column(
      children: <Widget>[
        for (var i = 0; i < sections.length; i += 2)
          Row(
            children: <Widget>[
              Expanded(child: cell(sections[i])),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < sections.length
                    ? cell(sections[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}
