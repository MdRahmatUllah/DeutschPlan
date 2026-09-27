import 'package:sogda/router/deep_links.dart';
import 'package:sogda/router/route_guards.dart';
import 'package:sogda/router/routes.dart';
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
    routes: $appRoutes,
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
      if (state.uri.hasScheme || state.uri.hasAuthority) {
        // An exam in progress is the one screen an arrival does not take over.
        //
        // Redirected back to where the learner already is, not `null`:
        // returning null means "carry on with the incoming location", and the
        // incoming location is a URI that matches no route —
        // so the link would land on Today through `onException` anyway. The
        // first version of this guard did exactly that.
        final current = router.routerDelegate.currentConfiguration.uri;
        if (!interruptible(current.path)) return current.toString();
        // #674: with nobody enrolled there is nothing to link into. A cold
        // start from a link (the widget, placed before the first launch)
        // takes the link over bootstrap's first location, and skipped setup:
        // setup from its first page, or the page the learner is on.
        if (!await checks.isEnrolled()) {
          return current.path.startsWith('/onboarding')
              ? current.toString()
              : const OnboardingRoute(page: '1').location;
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
