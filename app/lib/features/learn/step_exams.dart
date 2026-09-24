import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_pill.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/domain/exam_generator.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'step_exams.g.dart';

/// What L10 draws for a step: each sat seed's line, the attempts to resume
/// by seed, and the two settings the hub shows.
typedef ExamHub = ({
  List<SeedSummary> seeds,

  /// Seed → the unfinished attempt's id (FR-L10-02).
  Map<int, int> resume,

  /// `exam_pass_percent` (BR-EXAM-04).
  int passPercent,

  /// `listening_questions` (FR-L10-04).
  bool listening,

  /// The seeds whose paper shares grammar topics with another mock's
  /// (`Exam.reused`): a step with fewer than twelve topics can't keep
  /// three papers apart.
  Set<int> reused,
});

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
  final settings = ref.watch(settingsProvider);
  // Followed: the Learn tab stays alive while Settings moves the pass mark
  // or turns listening off.
  final changes = settings.changes
      .where(
        (key) =>
            key == SettingKeys.examPassPercent ||
            key == SettingKeys.listeningQuestions,
      )
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
  final exams = ref.watch(examRepositoryProvider);
  final seeds = ref.watch(examSeedsProvider(code).future);
  final resume = ref.watch(examResumeProvider(code).future);
  final listening = settings.read(SettingKeys.listeningQuestions);
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
    passPercent: settings.read(SettingKeys.examPassPercent),
    listening: listening,
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
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    if (!step.unlocked && !step.passed) {
      // ponytail: the locked hub is #128; until then the tab names itself.
      return Center(
        child: DpText(
          l10n.stepTabExams,
          role: DpTextRole.body,
          color: tokens.color.textSecondary,
        ),
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
        ExamContents(listening: hub.listening, passPercent: hub.passPercent),
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

/// "What's in these exams": BR-EXAM-03's sections with their counts, as
/// the learner's setting makes the paper, and the disclaimer.
class ExamContents extends StatelessWidget {
  const ExamContents({
    required this.listening,
    required this.passPercent,
    super.key,
  });

  final bool listening;
  final int passPercent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final l10n = AppLocalizations.of(context);
    String name(ExamSection section) => switch (section) {
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
            l10n.examHubDisclaimer(passPercent),
            role: DpTextRole.caption,
            color: tokens.color.textSecondary,
          ),
        ],
      ),
    );
  }
}
