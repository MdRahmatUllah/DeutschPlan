import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/router/routes.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:go_router/go_router.dart';

/// What the router has to ask the database before it opens a route.
///
/// Functions rather than a repository, so the router can be built and tested
/// without one — and so bootstrap decides what "an exam attempt exists" means
/// rather than the routing layer growing a second opinion about it.
@immutable
class RouteGuards {
  const RouteGuards({required this.hasExamAttempt, required this.isEnrolled});

  /// The real ones. Through the repositories, not the database: only
  /// `lib/data/` touches drift (project-structure.md, layering rule 2), and
  /// the router asking SQL questions of its own is how a second opinion about
  /// what "an attempt exists" means gets started.
  factory RouteGuards.of({
    required ExamRepository exams,
    required PlanRepository plan,
  }) =>
      RouteGuards(hasExamAttempt: exams.exists, isEnrolled: plan.hasEnrollment);

  /// Everything allowed. What a test that is not about the guards uses, and
  /// what the router falls back to when nobody supplied any — a router with
  /// no database behind it cannot answer, and refusing every route would be a
  /// worse answer than allowing them.
  factory RouteGuards.permissive() => RouteGuards(
    hasExamAttempt: (_) async => true,
    isEnrolled: () async => false,
  );

  /// Whether that attempt is in `exam_attempts`.
  ///
  /// FR-L12-01 resumes an exam from its id alone, so the id is the only thing
  /// a deep link or a restored process carries — and an id for an attempt
  /// that was never created, or was wiped by a data reset, would open a
  /// runner with no questions in it.
  final Future<bool> Function(int attemptId) hasExamAttempt;

  /// Whether the learner has started a step. Onboarding is for those who
  /// have not.
  final Future<bool> Function() isEnrolled;
}

/// `navigation.md`'s guards, in one place.
///
/// - `/exam/*` and `/study` require an existing attempt or session; without
///   one they go to the tab root rather than opening an empty screen.
/// - `/onboarding/*` goes to `/today` once enrolled.
///
/// Returning `null` means "carry on", which is what every route that is not
/// guarded does.
Future<String?> guardRedirect(GoRouterState state, RouteGuards guards) async {
  final location = state.uri.path;

  if (location.startsWith('/onboarding')) {
    // Onboarding is reachable from a deep link and from the first launch. A
    // learner who has already started a step and taps a stale link would
    // otherwise be walked through setup again and re-enrolled. Restart setup
    // is the one way back in, and says so in its query.
    if (state.uri.queryParameters['restart'] == 'true') return null;
    return await guards.isEnrolled() ? '/today' : null;
  }

  if (location.startsWith('/exam/')) {
    final attemptId = int.tryParse(state.pathParameters['attemptId'] ?? '');
    if (attemptId == null) return examFallback;
    return await guards.hasExamAttempt(attemptId) ? null : examFallback;
  }

  // Guarded by what the route *needs*, not by a list of paths. `extra` does
  // not survive process death, so every route that carries its work in one
  // has the same failure: restored, it opens with nothing to show.
  // `navigation.md` names only `/study` under Guards, but `/quiz` and
  // `/grammar-practice` are the same shape, and finding that out when those
  // screens are real is finding it out too late.
  if (needsSession[location] case final fallback?) {
    return _hasWork(location, state.extra) ? null : fallback;
  }

  return null;
}

/// The routes whose work rides on `extra`, and where each goes without it.
///
/// Today for a study session — it reads as "your session ended" rather than
/// as a blank card stack. Learn for the two that are started from a step.
const Map<String, String> needsSession = <String, String>{
  '/study': studyFallback,
  '/quiz': '/learn',
  '/grammar-practice': '/learn',
};

/// Whether [extra] is the argument that route needs, and not an empty one.
///
/// An empty list is the same as nothing: a session with no cards and a
/// practice run with no topics both open a screen with nothing on it.
bool _hasWork(String location, Object? extra) => switch ((location, extra)) {
  ('/study', final SessionArgs args) => args.wordUids.isNotEmpty,
  ('/quiz', final QuizArgs args) => args.length > 0,
  ('/grammar-practice', final GrammarPracticeArgs args) =>
    args.topicUids.isNotEmpty,
  _ => false,
};

/// Where a guarded route sends the learner instead.
///
/// The tab root, not the previous screen: a redirect fires on a fresh launch
/// too, when there is no previous screen to go back to.
const String examFallback = '/learn';
const String studyFallback = '/today';
