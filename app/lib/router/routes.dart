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

import 'package:deutschplan/features/splash/splash_screen.dart';
import 'package:deutschplan/router/app_shell.dart';
import 'package:deutschplan/router/back_behaviour.dart';
import 'package:deutschplan/router/deep_links.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/placeholder_screen.dart';
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
  const SessionArgs({required this.wordUids, this.planDate});

  /// The cards this session will show, in order.
  final List<String> wordUids;

  /// The day whose plan they came from, when they came from one.
  final String? planDate;
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
      const PlaceholderScreen(title: 'Today', screen: 'T1');
}

class BacklogRoute extends GoRouteData with $BacklogRoute {
  const BacklogRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Backlog', screen: 'T4');
}

class LearnRoute extends GoRouteData with $LearnRoute {
  const LearnRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Learn', screen: 'L1');
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
  const OnboardingRoute({required this.page});

  final String page;

  @override
  Widget build(BuildContext context, GoRouterState state) => PlaceholderScreen(
    title: 'Welcome',
    screen: page == 'placement' ? 'S3' : 'S2',
    detail: page,
  );
}

@TypedGoRoute<StudyRoute>(path: '/study')
class StudyRoute extends GoRouteData with $StudyRoute {
  const StudyRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final args = state.extra as SessionArgs?;
    return PlaceholderScreen(
      title: 'Study',
      screen: 'T2',
      detail: '${args?.wordUids.length ?? 0} cards',
    );
  }
}

@TypedGoRoute<SentencesRoute>(path: '/sentences')
class SentencesRoute extends GoRouteData with $SentencesRoute {
  const SentencesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Sentences', screen: 'T5');
}

@TypedGoRoute<DayCompleteRoute>(path: '/day-complete')
class DayCompleteRoute extends GoRouteData with $DayCompleteRoute {
  const DayCompleteRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PlaceholderScreen(title: 'Day complete', screen: 'T6');
}

@TypedGoRoute<GrammarPracticeRoute>(path: '/grammar-practice')
class GrammarPracticeRoute extends GoRouteData with $GrammarPracticeRoute {
  const GrammarPracticeRoute();

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
