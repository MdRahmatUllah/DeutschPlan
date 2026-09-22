import 'package:deutschplan/router/deep_links.dart';
import 'package:deutschplan/router/route_guards.dart';
import 'package:deutschplan/router/routes.dart';
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

  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: $appRoutes,
    redirect: (context, state) {
      // A `deutschplan://` link is not a location: `deutschplan://exam/A1.2`
      // names a step, and `/exam/:attemptId` in the table is the runner for
      // one attempt. Resolved first, then the result goes round again and
      // meets the guards like any other navigation.
      if (state.uri.scheme == deepLinkScheme) {
        // An exam in progress is the one screen a link does not take over.
        //
        // Redirected back to where the learner already is, not `null`:
        // returning null means "carry on with the incoming location", and the
        // incoming location is a `deutschplan://` URI that matches no route —
        // so the link would land on Today through `onException` anyway. The
        // first version of this guard did exactly that.
        final current = router.routerDelegate.currentConfiguration.uri;
        if (!interruptible(current.path)) return current.toString();

        return resolveDeepLink(state.uri);
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
