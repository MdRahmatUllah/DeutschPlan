/// Every path in `docs/01-architecture/navigation.md`, as a typed route.
///
/// Typed rather than string literals so a renamed path is a compile error
/// instead of a screen nobody can reach: `LearnStepRoute(code: 'A1.1').go(ctx)`
/// stops building the moment the path changes, and a `context.go('/lern/...')`
/// never would.
///
/// The screens are placeholders. They are replaced one at a time as each
/// screen's issue lands; what is real here is the table, the branches and the
/// presentation of each route.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:deutschplan/features/onboarding/onboarding_meaning_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_pace_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_shell.dart';
import 'package:deutschplan/features/onboarding/onboarding_start_page.dart';
import 'package:deutschplan/features/onboarding/onboarding_voice_page.dart';
import 'package:deutschplan/features/onboarding/placement_screen.dart';
import 'package:deutschplan/features/onboarding/onboarding_notifier.dart';
import 'package:deutschplan/features/onboarding/setup_flow.dart';
import 'package:deutschplan/features/onboarding/onboarding_welcome_page.dart';
import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/back_behaviour.dart';
import 'package:deutschplan/router/deep_links.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/features/today/today_screen.dart';
import 'package:deutschplan/features/backlog/backlog_screen.dart';
import 'package:deutschplan/features/day_complete/day_complete_screen.dart';
import 'package:deutschplan/features/learn/learn_screen.dart';
import 'package:deutschplan/features/sentences/sentences_screen.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/router/placeholder_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

part 'routes.g.dart';

/// The root navigator, above the shell.
///
/// Every full-screen route names it as its parent, which is what makes it
/// cover the tab bar instead of appearing inside a tab. It lives here rather
/// than beside the router because the routes are what reference it, and the
/// other way round is a cycle.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Ephemeral arguments, passed as `extra`.
///
/// `navigation.md`: "Session args are passed as `extra` **only** for ephemeral
/// data (which cards); anything that must survive process death (an exam
/// attempt) is keyed by an id in the path." `extra` does not survive a restore
/// from process death — it is not serialised into the platform's saved state —
/// so a route that needs its argument back after the OS kills the app has to
/// carry an id instead. That is why `/exam/:attemptId` has one and `/study`
/// does not.
@immutable
class SessionArgs {
  const SessionArgs({required this.blocks, this.planDate, this.origin});

  /// The session's blocks, in the order it plays them: Revise, New, Grammar
  /// (BR-PLAN-02). A block's banner plays as it starts (FR-T2-06).
  final List<SessionBlock> blocks;

  /// The day whose plan they came from, when they came from one.
  final String? planDate;

  /// Where on screen the session was opened from, for Android's container
  /// transform. Not part of the session: the same blocks opened from the
  /// button or from a card are one session.
  final Rect? origin;

  /// Every word card, in order. Grammar topics are practice sets, not words.
  List<String> get wordUids => <String>[
    for (final block in blocks)
      if (block.kind != SessionBlockKind.grammar) ...block.uids,
  ];

  // Value equality: these key the study session's notifier.
  @override
  bool operator ==(Object other) =>
      other is SessionArgs &&
      other.planDate == planDate &&
      listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(planDate, Object.hashAll(blocks));
}

/// What a session block holds.
enum SessionBlockKind {
  revise,
  newWords,
  grammar,

  /// T4's words, missed or skipped on earlier days (FR-T4-02): new words
  /// whose plan rows keep their own dates.
  backlog,
}

/// One block of a session.
@immutable
class SessionBlock {
  const SessionBlock(this.kind, this.uids);

  final SessionBlockKind kind;

  /// Word uids, or topic uids for [SessionBlockKind.grammar].
  final List<String> uids;

  @override
  bool operator ==(Object other) =>
      other is SessionBlock &&
      other.kind == kind &&
      listEquals(other.uids, uids);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(uids));
}

/// Which quiz to build. Ephemeral for the same reason [SessionArgs] is.
@immutable
class QuizArgs {
  const QuizArgs({
    required this.direction,
    required this.source,
    required this.seed,
    this.sourceRef,
    this.length = 10,
  });

  final String direction;
  final String source;
  final String? sourceRef;
  final int seed;
  final int length;
}

/// The topic a practice run is for.
@immutable
class GrammarPracticeArgs {
  const GrammarPracticeArgs({required this.topicUids});

  final List<String> topicUids;
}

/// L2's four tabs, as the `?tab=` query takes them.
enum StepTab { words, grammar, quiz, exams }

// --- The shell -------------------------------------------------------------

@TypedStatefulShellRoute<AppShellRoute>(
  branches: <TypedStatefulShellBranch<StatefulShellBranchData>>[
    TypedStatefulShellBranch<TodayBranch>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<TodayRoute>(
          path: '/today',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<BacklogRoute>(path: 'backlog'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<LearnBranch>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<LearnRoute>(
          path: '/learn',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<LearnStepRoute>(path: 'step/:code'),
            TypedGoRoute<GrammarLibraryRoute>(
              path: 'grammar',
              routes: <TypedRoute<RouteData>>[
                TypedGoRoute<GrammarTopicRoute>(path: ':uid'),
              ],
            ),
            TypedGoRoute<CategoriesRoute>(
              path: 'categories',
              routes: <TypedRoute<RouteData>>[
                TypedGoRoute<CategoryRoute>(path: ':id'),
              ],
            ),
            TypedGoRoute<ExamIntroRoute>(path: 'exam/:step/intro/:seed'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<SearchBranch>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<SearchRoute>(
          path: '/search',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<AddWordRoute>(path: 'add'),
            TypedGoRoute<EditCustomWordRoute>(path: 'add/:id'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<MeBranch>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<MeRoute>(
          path: '/me',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<ProgressRoute>(path: 'progress'),
            TypedGoRoute<SettingsRoute>(
              path: 'settings',
              routes: <TypedRoute<RouteData>>[
                TypedGoRoute<ReminderSettingsRoute>(path: 'reminder'),
              ],
            ),
            TypedGoRoute<ModelsRoute>(path: 'models'),
            TypedGoRoute<ExportImportRoute>(path: 'export'),
            TypedGoRoute<AboutRoute>(
              path: 'about',
              routes: <TypedRoute<RouteData>>[
                TypedGoRoute<LicencesRoute>(path: 'licences'),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
)
class AppShellRoute extends StatefulShellRouteData {
  const AppShellRoute();

  /// The root navigator, so a full-screen route can be pushed over the shell
  /// rather than inside a tab (`parentNavigatorKey: root`).
  static final GlobalKey<NavigatorState> $navigatorKey = rootNavigatorKey;

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => AppShell(navigationShell: navigationShell);
}

class TodayBranch extends StatefulShellBranchData {
  const TodayBranch();
}

class LearnBranch extends StatefulShellBranchData {
  const LearnBranch();
}

class SearchBranch extends StatefulShellBranchData {
  const SearchBranch();
}

class MeBranch extends StatefulShellBranchData {
  const MeBranch();
}

// --- Tab roots and their pushed routes --------------------------------------

class TodayRoute extends GoRouteData with $TodayRoute {
  const TodayRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const TodayScreen();
}

class BacklogRoute extends GoRouteData with $BacklogRoute {
  const BacklogRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const BacklogScreen();
}

class LearnRoute extends GoRouteData with $LearnRoute {
  const LearnRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LearnScreen();
}

class LearnStepRoute extends GoRouteData with $LearnStepRoute {
  const LearnStepRoute({required this.code, this.tab});

  /// The step, `A1.1` and so on. In the path, not in `extra`: a deep link and
  /// the widget both open this, and neither can pass an object.
  final String code;

  /// Which of L2's four tabs opens. A query rather than a path segment
  /// because it is a view of the same screen, and `/learn/step/A1.1` has to
  /// stay a valid link on its own.
  final StepTab? tab;

  @override
  Widget build(BuildContext context, GoRouterState state) => PlaceholderScreen(
    title: 'Step $code',
    screen: 'L2',
    detail: (tab ?? StepTab.words).name,
  );
}

class GrammarLibraryRoute extends GoRouteData with $GrammarLibraryRoute {
  const GrammarLibraryRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Grammar', screen: 'L3');
}

class GrammarTopicRoute extends GoRouteData with $GrammarTopicRoute {
  const GrammarTopicRoute({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: 'Topic', screen: 'L4', detail: uid);
}

class CategoriesRoute extends GoRouteData with $CategoriesRoute {
  const CategoriesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Categories', screen: 'L5');
}

class CategoryRoute extends GoRouteData with $CategoryRoute {
  const CategoryRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: 'Category', screen: 'L6', detail: '$id');
}

class ExamIntroRoute extends GoRouteData with $ExamIntroRoute {
  const ExamIntroRoute({required this.step, required this.seed});

  final String step;
  final int seed;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: 'Mock $seed', screen: 'L11', detail: step);
}

class SearchRoute extends GoRouteData with $SearchRoute {
  const SearchRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Search', screen: 'R1');
}

class AddWordRoute extends GoRouteData with $AddWordRoute {
  const AddWordRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Add a word', screen: 'R2');
}

class EditCustomWordRoute extends GoRouteData with $EditCustomWordRoute {
  const EditCustomWordRoute({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: 'My word', screen: 'R2', detail: '$id');
}

class MeRoute extends GoRouteData with $MeRoute {
  const MeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Me', screen: 'M1');
}

class ProgressRoute extends GoRouteData with $ProgressRoute {
  const ProgressRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Progress', screen: 'M2');
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Settings', screen: 'M3');
}

class ReminderSettingsRoute extends GoRouteData with $ReminderSettingsRoute {
  const ReminderSettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Reminder & days', screen: 'M5');
}

class ModelsRoute extends GoRouteData with $ModelsRoute {
  const ModelsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Voice & translation', screen: 'M4');
}

class ExportImportRoute extends GoRouteData with $ExportImportRoute {
  const ExportImportRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Export / import', screen: 'M6');
}

class AboutRoute extends GoRouteData with $AboutRoute {
  const AboutRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'About', screen: 'M9');
}

class LicencesRoute extends GoRouteData with $LicencesRoute {
  const LicencesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Licences', screen: 'M8');
}

// --- Full-screen routes over the shell --------------------------------------
//
// Declared outside the shell's branches, which is what puts them *over* the
// tab bar rather than inside a tab — `navigation.md`: "Modals never switch
// tabs; closing returns to the opener."
//
// They carried a `$parentNavigatorKey = rootNavigatorKey` as well, until
// planting showed removing it changed nothing: a route that is not in a
// branch is already on the root navigator, so naming it was a line that only
// looked load-bearing.

@TypedGoRoute<SplashRoute>(path: '/splash')
class SplashRoute extends GoRouteData with $SplashRoute {
  const SplashRoute();

  /// The gate rather than the screen: the progress line is a function of how
  /// long bootstrap has taken, and only the gate can know that.
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SplashProgressGate();
}

@TypedGoRoute<OnboardingRoute>(path: '/onboarding/:page')
class OnboardingRoute extends GoRouteData with $OnboardingRoute {
  const OnboardingRoute({required this.page, this.restart = false});

  final String page;

  /// Restart setup, from Settings (`onboarding.md`, States). A query
  /// parameter, so the guard can tell it from a stale link: an enrolled
  /// learner is sent to Today from `/onboarding/*` unless this is set.
  final bool restart;

  /// Settings → *Restart setup*: page 1 hidden, every page pre-filled with
  /// what the learner has now, and finishing changes the plan but not the
  /// history. Settings is M3's; this is what it calls.
  static Future<void> restartSetup(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final keep = container.listen(setupFlowProvider, (_, _) {});
    try {
      await container.read(setupFlowProvider.notifier).beginRestart();
    } finally {
      keep.close();
    }
    // Opened, not awaited: `push` completes when the page pops, which is the
    // end of setup — Settings would sit waiting on it the whole way through.
    if (context.mounted) {
      unawaited(
        const OnboardingRoute(page: '2', restart: true).push<void>(context),
      );
    }
  }

  /// A horizontal slide between pages, and the edge swipe back — #87's "system
  /// back / edge swipe goes to the previous page". `CupertinoPage` gives both
  /// on both platforms; Android's default zoom transition gives neither the
  /// slide nor the swipe.
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      CupertinoPage<void>(key: state.pageKey, child: build(context, state));

  /// `:page` is `1`…`5` for S2, or `placement` for S3 — one route because
  /// `navigation.md` gives them one path, and the placement check is reached
  /// from page 3 rather than being a tab of its own.
  @override
  Widget build(BuildContext context, GoRouterState state) {
    if (page == 'placement') {
      // Popped with the suggestion, which page 3 picks; popped with nothing
      // on close (FR-S3-04), which leaves page 3 as it was. Opened directly —
      // a deep link — there is no page 3 under it, so it goes there, and a
      // suggestion goes to the draft that page reads.
      return PlacementScreen(
        onDone: (step) {
          if (context.canPop()) {
            context.pop(step);
            return;
          }
          if (step != null) {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(onboardingProvider.notifier).chooseStep(step);
          }
          OnboardingRoute(
            page: OnboardingPage.startingPoint.slug,
            restart: restart,
          ).go(context);
        },
      );
    }

    // `push`, not `go`: each page sits on the one before it, so system back
    // returns there. Onboarding is outside the tab shell, so nothing else
    // would catch the press, and `go` would leave the page with nothing under
    // it — back would close the app. Restart setup carries on to each page.
    void next(OnboardingPage to) =>
        OnboardingRoute(page: to.slug, restart: restart).push<void>(context);

    return switch (OnboardingPage.parse(page)) {
      // A bad `:page` gets the start of setup rather than a blank screen. So
      // does page 1 in restart mode, which never links there itself.
      OnboardingPage.welcome || null => OnboardingWelcomePage(
        onStart: () => next(OnboardingPage.meaningLanguage),
      ),

      OnboardingPage.meaningLanguage => OnboardingMeaningPage(
        onContinue: () => next(OnboardingPage.startingPoint),
        onBack: () => _back(context, OnboardingPage.meaningLanguage),
      ),

      OnboardingPage.startingPoint => OnboardingStartPage(
        onContinue: () => next(OnboardingPage.dailyPace),
        onBack: () => _back(context, OnboardingPage.startingPoint),
        onSkip: () =>
            _finish(context, skippingFrom: OnboardingPage.startingPoint),
        // S3 pops with the step it suggests (#93, #94), or with nothing.
        // `restart` too: in restart setup the learner is enrolled, and the
        // guard would send a plain link to Today.
        onPlacement: () => OnboardingRoute(
          page: 'placement',
          restart: restart,
        ).push<String>(context),
      ),

      OnboardingPage.dailyPace => OnboardingPacePage(
        onContinue: () => next(OnboardingPage.reminderAndVoice),
        onBack: () => _back(context, OnboardingPage.dailyPace),
        onSkip: () => _finish(context, skippingFrom: OnboardingPage.dailyPace),
      ),

      OnboardingPage.reminderAndVoice => OnboardingVoicePage(
        onFinish: () => _finish(context),
        onBack: () => _back(context, OnboardingPage.reminderAndVoice),
        onSkip: () =>
            _finish(context, skippingFrom: OnboardingPage.reminderAndVoice),
      ),
    };
  }

  /// *Back*: the page underneath, which is the previous one when the learner
  /// walked here. A page opened directly — a deep link, restart setup — has
  /// nothing under it, and gets the previous page instead of a dead button;
  /// restart setup's first page has no previous, and leaves setup instead.
  void _back(BuildContext context, OnboardingPage from) {
    if (context.canPop()) {
      context.pop();
    } else if (restart && from == OnboardingPage.meaningLanguage) {
      const TodayRoute().go(context);
    } else {
      OnboardingRoute(page: from.previous!.slug, restart: restart).go(context);
    }
  }

  /// FR-S2-03 — and FR-S2-01's Skip, from [skippingFrom]: commit the draft,
  /// plan day 1, open Today. A failure leaves the learner where they are,
  /// and the page says so.
  static Future<void> _finish(
    BuildContext context, {
    OnboardingPage? skippingFrom,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    // Held for the whole finish: the notifier auto-disposes, and one with no
    // listener could go between the commit and the plan.
    final keep = container.listen(setupFlowProvider, (_, _) {});
    try {
      final done = await container
          .read(setupFlowProvider.notifier)
          .finish(skippingFrom: skippingFrom);
      if (done && context.mounted) {
        const TodayRoute().go(context);
        // After leaving, so the page does not redraw with the defaults on
        // its way out; a later restart starts from the learner's values.
        container.invalidate(onboardingProvider);
      }
    } finally {
      keep.close();
    }
  }
}

@TypedGoRoute<StudyRoute>(path: '/study')
class StudyRoute extends GoRouteData with $StudyRoute {
  const StudyRoute();

  /// Starts a session over the shell. Full-screen, so a plain push: closing
  /// it returns to whoever opened it.
  static void open(BuildContext context, SessionArgs args) =>
      unawaited(context.push<void>(const StudyRoute().location, extra: args));

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final args =
        state.extra as SessionArgs? ??
        const SessionArgs(blocks: <SessionBlock>[]);
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: StudyScreen(args: args),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, _, child) => StudyTransition(
        animation: animation,
        origin: args.origin,
        child: child,
      ),
    );
  }
}

/// How T2 arrives (`study-session.md`, Presentation): on Android a container
/// transform from the tapped card, on iOS a modal slide-up. Reduce motion is
/// a cross-fade on both.
class StudyTransition extends StatelessWidget {
  const StudyTransition({
    required this.animation,
    required this.child,
    super.key,
    this.origin,
  });

  final Animation<double> animation;
  final Widget child;

  /// The tapped card's rect, in global coordinates.
  final Rect? origin;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    if (context.isCupertino) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    }
    final from = origin;
    if (from == null) return FadeTransition(opacity: curved, child: child);

    // The session grows out of the card: its clip runs from the card's rect
    // to the screen, and its content fades in over the first half.
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        final screen = Offset.zero & MediaQuery.sizeOf(context);
        return ClipRRect(
          clipper: _GrowingClip(Rect.lerp(from, screen, t)!, 16 * (1 - t)),
          child: Opacity(opacity: (t * 2).clamp(0.0, 1.0), child: child),
        );
      },
      child: child,
    );
  }
}

class _GrowingClip extends CustomClipper<RRect> {
  const _GrowingClip(this.rect, this.radius);

  final Rect rect;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(_GrowingClip old) =>
      old.rect != rect || old.radius != radius;
}

@TypedGoRoute<SentencesRoute>(path: '/sentences')
class SentencesRoute extends GoRouteData with $SentencesRoute {
  const SentencesRoute();

  /// T5 over the shell, as [StudyRoute.open].
  static void open(BuildContext context) =>
      unawaited(context.push<void>(const SentencesRoute().location));

  /// T5 in place of the screen on top — T3's next step, so closing T5
  /// returns to Today rather than to a finished session.
  static void instead(BuildContext context) =>
      context.pushReplacement(const SentencesRoute().location);

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SentencesScreen();
}

@TypedGoRoute<DayCompleteRoute>(path: '/day-complete')
class DayCompleteRoute extends GoRouteData with $DayCompleteRoute {
  const DayCompleteRoute();

  /// T6 in place of the finished session (T3: "skipped entirely — T6 shown
  /// instead — when the day is complete and no sentences are open").
  static void instead(BuildContext context) =>
      context.pushReplacement(const DayCompleteRoute().location);

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DayCompleteScreen();
}

@TypedGoRoute<GrammarPracticeRoute>(path: '/grammar-practice')
class GrammarPracticeRoute extends GoRouteData with $GrammarPracticeRoute {
  const GrammarPracticeRoute();

  /// L15 over the shell, as [StudyRoute.open].
  static void open(BuildContext context, GrammarPracticeArgs args) => unawaited(
    context.push<void>(const GrammarPracticeRoute().location, extra: args),
  );

  /// L15 in place of the finished session: T3's next step.
  static void instead(BuildContext context, GrammarPracticeArgs args) => context
      .pushReplacement(const GrammarPracticeRoute().location, extra: args);

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final args = state.extra as GrammarPracticeArgs?;
    return PlaceholderScreen(
      title: 'Grammar practice',
      screen: 'L15',
      detail: '${args?.topicUids.length ?? 0} topics',
    );
  }
}

@TypedGoRoute<QuizRoute>(path: '/quiz')
class QuizRoute extends GoRouteData with $QuizRoute {
  const QuizRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final args = state.extra as QuizArgs?;
    return PlaceholderScreen(
      title: 'Quiz',
      screen: 'L8',
      detail: args?.direction ?? '',
    );
  }
}

/// The exam runner. `attemptId` is in the path and not in `extra` on purpose:
/// FR-L12-01 resumes an exam after the app is killed, and `extra` does not
/// survive that.
@TypedGoRoute<ExamRoute>(path: '/exam/:attemptId')
class ExamRoute extends GoRouteData with $ExamRoute {
  const ExamRoute({required this.attemptId});

  final int attemptId;

  @override
  Widget build(BuildContext context, GoRouterState state) => ExamBackGuard(
    // FR-L12-04: back asks rather than pops, and `canPop: false` is also
    // what turns off the iOS edge swipe for this route (#69).
    //
    // TODO(#119): *Leave* has to set `status = 'abandoned'` as well —
    // `ExamRepository.abandon(attemptId)` — or the hub keeps offering
    // *Resume* for an exam the learner walked out of. The runner owns the
    // attempt; this placeholder only navigates, and leaving that unsaid
    // would make a half-wired path look finished.
    onLeave: () => context.go(examFallback),
    child: PlaceholderScreen(
      title: 'Mock exam',
      screen: 'L12',
      detail: 'attempt $attemptId',
    ),
  );
}

/// Word detail. Shown as a sheet from a list; the route exists for deep links,
/// which is why the uid is in the path.
@TypedGoRoute<WordRoute>(path: '/word/:uid')
class WordRoute extends GoRouteData with $WordRoute {
  const WordRoute({required this.uid, this.speak});

  /// W1 over whatever is showing — T2's "open word details".
  static void open(BuildContext context, String uid) =>
      unawaited(context.push<void>(WordRoute(uid: uid).location));

  final String uid;

  /// `?speak=1` from the widget's *Pronounce* action (FR-X1-02). A query
  /// rather than a path segment because `/word/<uid>` has to stay a valid
  /// link on its own, and because it describes what to do on arrival rather
  /// than which word this is.
  final String? speak;

  @override
  Widget build(BuildContext context, GoRouterState state) => PlaceholderScreen(
    title: 'Word',
    screen: 'W1',
    // The typed field, not `state.uri`: a route that declared a parameter and
    // then read the raw location would have two answers to the same question,
    // which is the thing typed routes exist to prevent.
    // TODO(#136): W1 plays the headword on open when this is set.
    detail: speak == speakOn ? '$uid speak' : uid,
  );
}

@TypedGoRoute<CompareRoute>(path: '/compare/:uid')
class CompareRoute extends GoRouteData with $CompareRoute {
  const CompareRoute({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: 'Compare', screen: 'W2', detail: uid);
}
