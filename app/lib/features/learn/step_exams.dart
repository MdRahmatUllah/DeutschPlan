import 'dart:math' as math;

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/components/dp_progress_ring.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/domain/plan_stats.dart' show courseDays;
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_screen.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/cross_tab.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'step_exams.g.dart';

/// What L10 draws for an unlocked step: each sat seed's line, and the
/// attempts to resume by seed.
typedef ExamHub = ({
  List<SeedSummary> seeds,

  /// Seed → the unfinished attempt's id (FR-L10-02).
  Map<int, int> resume,

  /// The seeds whose paper shares grammar topics with another mock's
  /// (`Exam.reused`): a step with fewer than twelve topics can't keep
  /// three papers apart.
  Set<int> reused,
});

/// The three settings L10 shows, locked or not.
typedef ExamRules = ({
  /// `exam_pass_percent` (BR-EXAM-04).
  int passPercent,

  /// `exam_unlock_percent` (BR-EXAM-01), for the locked hub.
  int unlockPercent,

  /// `listening_questions` (FR-L10-04).
  bool listening,
});

/// [ExamRules], followed: the Learn tab stays alive while Settings moves
/// them. Apart from [examHub] so that a locked tab — most steps, most of the
/// time — draws at once, not after papers nobody will see.
@riverpod
ExamRules examRules(Ref ref) {
  final settings = ref.watch(settingsProvider);
  final changes = settings.changes
      .where(
        (key) =>
            key == SettingKeys.examPassPercent ||
            key == SettingKeys.examUnlockPercent ||
            key == SettingKeys.listeningQuestions,
      )
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  return (
    passPercent: settings.read(SettingKeys.examPassPercent),
    unlockPercent: settings.read(SettingKeys.examUnlockPercent),
    listening: settings.read(SettingKeys.listeningQuestions),
  );
}

@riverpod
Stream<List<SeedSummary>> examSeeds(Ref ref, String code) =>
    ref.watch(examRepositoryProvider).watchSeeds(code);

/// Keys rather than the attempts: drift's row class can't be a provider's
/// type.
@riverpod
Stream<Map<int, int>> examResume(Ref ref, String code) => ref
    .watch(examRepositoryProvider)
    .watchResumable(code)
    .map((open) => <int, int>{for (final e in open.entries) e.key: e.value.id});

/// L10's figures, as the attempts change: a mock finished, left or begun
/// moves its card without the hub asking.
@riverpod
Future<ExamHub> examHub(Ref ref, String code) async {
  // Listening alone changes the papers; the pass mark moving need not
  // draw them again.
  final listening = ref.watch(
    examRulesProvider.select((rules) => rules.listening),
  );
  final exams = ref.watch(examRepositoryProvider);
  final seeds = ref.watch(examSeedsProvider(code).future);
  final resume = ref.watch(examResumeProvider(code).future);
  final summaries = await seeds;
  final open = await resume;

  // BR-EXAM-02, honestly: a paper not sat yet reuses what buildExam says
  // it would (about 100 ms on real data); a stored one, whatever it shares
  // with the other stored papers.
  final sat = await exams.satRefs(code);
  final pool = await exams.pool(code);
  Set<String> topics(Set<String> refs) => <String>{
    for (final ref in refs)
      if (ref.contains('#')) ref.split('#').first,
  };
  bool shares(int seed) => sat.entries.any(
    (other) =>
        other.key != seed &&
        topics(other.value).intersection(topics(sat[seed]!)).isNotEmpty,
  );
  return (
    seeds: summaries,
    resume: open,
    reused: <int>{
      for (var seed = 1; seed <= 3; seed++)
        if (sat.containsKey(seed)
            ? shares(seed)
            : buildExam(
                pool,
                seed: seed,
                listening: listening,
                sat: sat,
              ).reused)
          seed,
    },
  );
}

/// How many questions a paper has: BR-EXAM-03's, Writing and Speaking left
/// out. 40 with listening or without (FR-L10-04).
final int examQuestions = <ExamSection>[
  for (final s in ExamSection.values)
    if (s != ExamSection.writing && s != ExamSection.speaking) s,
].fold(0, (sum, s) => sum + sectionCount(s, listening: true));

/// ponytail: the artboard's "≈ 20 min" for 40 questions, fixed. The timer
/// (#130) is the real number; derive this from it if they part.
const int examMinutes = 20;

/// L10 · Mock exam hub (`exam-hub.md`, `ExamHub-android.html`): L2's Exams
/// tab once the step's exams are unlocked (BR-EXAM-01). Three mocks with
/// their best score or *Not attempted*, *Start* or *Resume*, and what is in
/// them.
class StepExamsTab extends ConsumerWidget {
  const StepExamsTab({required this.step, super.key});

  final StepProgress step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(examRulesProvider);

    // FR-L10-01: locked until enough of the step is introduced, and a
    // passed step stays open.
    if (!step.unlocked && !step.passed) {
      return ListView(
        key: PageStorageKey<String>('step-exams-${step.code}'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: <Widget>[
          LockedExams(step: step, unlockPercent: rules.unlockPercent),
          const SizedBox(height: 14),
          ExamContents(
            listening: rules.listening,
            passPercent: rules.passPercent,
            locked: true,
          ),
        ],
      );
    }

    final hub = ref.watch(examHubProvider(step.code)).value;
    if (hub == null) return const SizedBox.expand();

    return ListView(
      key: PageStorageKey<String>('step-exams-${step.code}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: <Widget>[
        for (var seed = 1; seed <= 3; seed++) ...<Widget>[
          if (seed > 1) const SizedBox(height: 10),
          MockCard(
            seed: seed,
            summary: hub.seeds.where((s) => s.seed == seed).firstOrNull,
            resume: hub.resume[seed],
            reused: hub.reused.contains(seed),
            onStart: () => ExamIntroRoute.open(context, step.code, seed),
            onResume: (id) => ExamRoute.open(context, id),
          ),
        ],
        const SizedBox(height: 14),
        ExamContents(
          listening: rules.listening,
          passPercent: rules.passPercent,
        ),
      ],
    );
  }
}

/// One mock's card: its best score, how often it was sat, and the way in.
class MockCard extends StatelessWidget {
  const MockCard({
    required this.seed,
    required this.summary,
    required this.resume,
    required this.onStart,
    required this.onResume,
    super.key,
    this.reused = false,
  });

  final int seed;

  /// The seed's line, or null before it has been sat.
  final SeedSummary? summary;

  /// The attempt to resume, if one is unfinished.
  final int? resume;

  /// Its paper shares grammar topics with another mock's.
  final bool reused;
  final VoidCallback onStart;
  final ValueChanged<int> onResume;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    final line = summary;
    final attempts = line?.attempts ?? 0;
    // Down, never up: a fail at 69.8 % must not read as the 70 % mark.
    final best = (line?.bestPercent ?? 0).floor();

    // FR-L10-02: the best finished score. An attempt left unfinished counts
    // as an attempt with no score (FR-L12-04), and so has no pill.
    final Widget? status = switch (line) {
      SeedSummary(everPassed: true) => DpPill(
        label: l10n.examHubPassed(best),
        fill: tokens.color.easy,
        icon: Icons.check,
      ),
      SeedSummary(finished: > 0) => DpPill(
        label: l10n.examHubNotYet(best),
        fill: tokens.color.again,
      ),
      // Begun but never finished: Resume says it all.
      _ when attempts == 0 && resume == null => DpText(
        l10n.examHubNotAttempted,
        role: DpTextRole.caption,
        color: tokens.color.textSecondary,
      ),
      _ => null,
    };
    final details = <String>[
      l10n.examHubLine(examQuestions, examMinutes),
      if (attempts > 0) l10n.examHubAttempts(attempts),
      // BR-EXAM-02, said once, on the last of the three, and only where it
      // is true; a paper that reuses says so instead.
      if (reused)
        l10n.examHubShares
      else if (seed == 3)
        l10n.examHubNoRepeats(seed),
    ].join(' · ');
    final open = resume;

    return DpSurface(
      kind: DpSurfaceKind.bar,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    DpText(
                      l10n.examHubMock(seed),
                      role: DpTextRole.bodyLarge,
                      weight: 600,
                    ),
                    ?status,
                  ],
                ),
                const SizedBox(height: 6),
                DpText(
                  details,
                  role: DpTextRole.caption,
                  color: tokens.color.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DpButton(
            label: open == null ? l10n.examHubStart : l10n.examHubResume,
            compact: true,
            expand: false,
            onPressed: open == null ? onStart : () => onResume(open),
          ),
        ],
      ),
    );
  }
}

/// A section's name, as L10, L11 and the runner say it.
String examSectionName(AppLocalizations l10n, ExamSection section) =>
    switch (section) {
      ExamSection.vocabulary => l10n.examSectionVocabulary,
      ExamSection.reverse => l10n.examSectionReverse,
      ExamSection.articles => l10n.examSectionArticles,
      ExamSection.wordForms => l10n.examSectionWordForms,
      ExamSection.gapFill => l10n.examSectionGapFill,
      ExamSection.grammar => l10n.examSectionGrammar,
      ExamSection.listening => l10n.examSectionListening,
      ExamSection.writing => l10n.examSectionWriting,
      ExamSection.speaking => l10n.examSectionSpeaking,
    };

/// "What's in these exams": BR-EXAM-03's sections with their counts, as
/// the learner's setting makes the paper, and the disclaimer.
class ExamContents extends StatelessWidget {
  const ExamContents({
    required this.listening,
    required this.passPercent,
    super.key,
    this.locked = false,
  });

  final bool listening;
  final int passPercent;

  /// The locked hub also says where the threshold is changed.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    String name(ExamSection section) => examSectionName(l10n, section);
    final sections = <String>[
      for (final section in ExamSection.values)
        if (sectionCount(section, listening: listening) case final count
            when count > 0)
          // One task each: named without a count, as the artboard does.
          section.count == 1 && section.points > 1
              ? name(section)
              : l10n.examHubSection(name(section), count),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: DpText(
              l10n.examHubContents.toUpperCase(),
              role: DpTextRole.caption,
              weight: 700,
              letterSpacing: 0.6,
              color: tokens.color.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DpText(sections, role: DpTextRole.label, weight: 400),
          const SizedBox(height: 6),
          DpText(
            <String>[
              l10n.examHubDisclaimer(passPercent),
              if (locked) l10n.examHubThreshold,
            ].join(' '),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// FR-L10-01's locked hub: how much of the step is introduced of what
/// unlocks its mocks, how long that is at the step's pace, and *Study now*.
class LockedExams extends ConsumerWidget {
  const LockedExams({
    required this.step,
    required this.unlockPercent,
    super.key,
  });

  final StepProgress step;

  /// BR-EXAM-01's `exam_unlock_percent`.
  final int unlockPercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    // Sun's own ink on paper and dark; the page's under glass, as L2's
    // header does.
    final ink = tokens.isGlass ? tokens.color.ink : tokens.color.onAccent;
    final goal = StepProgress.unlockTarget(
      todo: step.todo,
      introduced: step.introduced,
      percent: unlockPercent,
    );
    final left = math.max(0, goal - step.introduced);
    // FR-L10-01: the words left at the step's pace, over its study days.
    final days = courseDays(
      words: left,
      dailyNew: step.dailyNew,
      studyDaysMask: step.studyDaysMask,
    );
    final today = ref.watch(todayViewProvider).value;
    final blocks = today == null ? const <SessionBlock>[] : openBlocks(today);

    return DpSurface(
      // Solid Sun on paper and dark; a Sun wash under glass, as the glass
      // artboard draws it.
      kind: DpSurfaceKind.tint(
        tokens.color.accent,
        opacity: tokens.isGlass ? 0.22 : 1,
      ),
      // The ink border and hard shadow of a raised card on paper; a plain
      // panel edge under glass.
      selected: !tokens.isGlass,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline, size: 20, color: ink),
              const SizedBox(width: 10),
              Expanded(
                child: DpText(
                  l10n.examHubUnlocksWhen(unlockPercent, step.code),
                  role: DpTextRole.bodyLarge,
                  weight: 600,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The line under it says the same; a screen reader hears it once.
          ExcludeSemantics(
            child: DpSegmentedBar(
              done: step.introduced,
              learning: 0,
              todo: left,
              height: 10,
              // Sun's own ink over Sun's track, in dark too: the page's ink,
              // which dark draws light, was 1.3:1 on Sun (#449).
              colours: (
                done: ink,
                learning: ink,
                todo: tokens.color.onAccentTrack,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DpText(
            <String>[
              l10n.examHubIntroduced(step.introduced, goal),
              if (days != null && days > 0)
                l10n.examHubDaysAt(days, step.dailyNew),
            ].join(' · '),
            role: DpTextRole.label,
            color: ink,
          ),
          // FR-L10-01's *Study now*: today's session, as L1's *Study* opens
          // it, or Today itself once the day is done. Only on the step being
          // studied: today's session is that step's, and L1 offers *Study*
          // on its tile alone. Its own semantics node: folded into the
          // card's, the whole card would read as one button.
          if (step.active) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              child: Builder(
                builder: (button) => DpButton(
                  label: l10n.examHubStudyNow,
                  // A raised white (dark: card) button on Sun, as Day
                  // complete's; under glass the call to action stays Lagoon.
                  colour: tokens.isGlass ? null : tokens.surface.cardStrong,
                  onColour: tokens.isGlass ? null : tokens.color.ink,
                  onPressed: blocks.isEmpty || today == null
                      ? () => context.jumpToTab(const TodayRoute())
                      : () => StudyRoute.open(
                          context,
                          SessionArgs(
                            blocks: blocks,
                            planDate: today.date,
                            origin: originOf(button),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
