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
    // otherwise be walked through setup again and re-enrolled.
    return await guards.isEnrolled() ? '/today' : null;
  }

  if (location.startsWith('/exam/')) {
    final attemptId = int.tryParse(state.pathParameters['attemptId'] ?? '');
    if (attemptId == null) return examFallback;
    return await guards.hasExamAttempt(attemptId) ? null : examFallback;
  }

  if (location == '/study') {
    // `/study` carries its cards in `extra`, which does not survive process
    // death — so a resumed `/study` has nothing to show. Sending it to Today
    // is what turns that into "your session ended" rather than a blank card
    // stack.
    final args = state.extra;
    if (args is! SessionArgs || args.wordUids.isEmpty) return studyFallback;
  }

  return null;
}

/// Where a guarded route sends the learner instead.
///
/// The tab root, not the previous screen: a redirect fires on a fresh launch
/// too, when there is no previous screen to go back to.
const String examFallback = '/learn';
const String studyFallback = '/today';
