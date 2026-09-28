import 'package:sogda/router/deep_links.dart';
import 'package:sogda/router/route_guards.dart';
import 'package:sogda/router/routes.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:go_router/go_router.dart';

/// The route table of `docs/01-architecture/navigation.md`.
///
/// Built from the generated `$appRoutes` rather than by hand, so a typed
/// route that is declared and never registered is impossible — the generator
/// produces both from the same annotations.
///
/// Back behaviour (#69) and deep links (#70) are wired into this object by
/// their own issues; what is here is the table, the shell and the guards.
GoRouter buildRouter({String initialLocation = '/today', RouteGuards? guards}) {
  final checks = guards ?? RouteGuards.permissive();

  // The router refers to itself: the deep-link branch has to know where the
  // learner already is before deciding whether to move them.
  late final GoRouter router;
  // The speaking links so far: each *Pronounce* is a new arrival (#442).
  var arrivals = 0;

  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    // #747: a launch link that isn't a URI at all (`sogda://[::1/x`, from a
    // web page: the filter is BROWSABLE) threw from here and failed the start,
    // and every Retry, until the app was killed. It is dropped, and the app
    // opens where bootstrap says. So is one that parses but can't be read
    // (#980), whose redirect threw and left no location at all.
    overridePlatformDefaultLocation: switch (Uri.tryParse(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    )) {
      final launch? => !readable(launch),
      null => true,
    },
    routes: $appRoutes,
    // An arrival from outside (a link, a tapped reminder, another app's URI)
    // never takes over a running exam, FR-L12-04's leave being a decision
    // (#676), nor setup when nobody is enrolled yet (#674). Blocked here,
    // before any redirect, so the stack stays as it is: a redirect can only
    // `go` somewhere, which rebuilds the stack without the exam pushed over
    // its step (`ExamRoute.open`), or setup's pushed pages. And [current] is
    // the top route, a push included, where the configuration's own `uri` is
    // the stack's base: `/learn/step/…` under that exam, `/onboarding/1`
    // under setup's page 3.
    onEnter: (context, current, next, router) async {
      if (!arrival(next.uri)) return const Allow();
      final top = current.uri.path;
      // #935: only while the attempt runs. Its results (L13) and review
      // (L14) are the same route, with nothing a link could cost them.
      if (!interruptible(top)) {
        final id = int.tryParse(
          current.uri.pathSegments.elementAtOrNull(1) ?? '',
        );
        if (id == null || await checks.isExamRunning(id)) {
          return const Block.stop();
        }
      }
      if (top.startsWith('/onboarding') && !await checks.isEnrolled()) {
        return const Block.stop();
      }
      return const Allow();
    },
    redirect: (context, state) async {
      // A `sogda://` link is not a location: `sogda://exam/A1.2`
      // names a step, and `/exam/:attemptId` in the table is the runner for
      // one attempt. Resolved first, then the result goes round again and
      // meets the guards like any other navigation.
      //
      // #613: a scheme or a host is an arrival from outside the app, never
      // one of its own locations. MainActivity is exported, and Flutter hands
      // any intent's data over as the route, so another app's `x://h/exam/7`
      // would otherwise match the table by its path.
      if (arrival(state.uri)) {
        // A running exam, or setup with nobody enrolled, never gets here:
        // [onEnter] has blocked the arrival. *Restart setup* (enrolled) is
        // not held, so its arrival does (#933).
        //
        // #674: with nobody enrolled there is nothing to link into. A cold
        // start from a link (the widget, placed before the first launch)
        // takes the link over bootstrap's first location, and skipped setup:
        // setup, from its first page.
        if (!await checks.isEnrolled()) {
          return const OnboardingRoute(page: '1').location;
        }
        if (state.uri.scheme != deepLinkScheme) return fallbackLocation;

        final resolved = resolveDeepLink(state.uri);
        return wantsSpeech(Uri.parse(resolved))
            ? numbered(resolved, ++arrivals)
            : resolved;
      }
      return guardRedirect(state, checks);
    },
    // A link that matches nothing is a stale notification or a stale widget,
    // not something to show the learner a framework page about — and not
    // something to show them a blank screen about either. Redirecting rather
    // than rendering an error screen is what puts the tab bar back: they end
    // up on Today with somewhere to go, which is the whole difference between
    // a dead end and a wrong turn.
    //
    // #70 replaces this with the deep-link handling, which will know the
    // difference between a link it cannot parse and one it can.
    onException: (context, state, router) => router.go(fallbackLocation),
  );

  return router;
}

/// Where an unmatched link lands. Today, because it is the one screen that is
/// always meaningful and always has the tab bar under it.
const String fallbackLocation = '/today';

/// #613: a scheme or a host is an arrival from outside the app (a link, a
/// tapped reminder, another app's URI), never one of its own locations.
bool arrival(Uri uri) => uri.hasScheme || uri.hasAuthority;
