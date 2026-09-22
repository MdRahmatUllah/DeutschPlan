import 'package:deutschplan/router/routes.dart';
import 'package:go_router/go_router.dart';

/// The route table of `docs/01-architecture/navigation.md`.
///
/// Built from the generated `$appRoutes` rather than by hand, so a typed
/// route that is declared and never registered is impossible — the generator
/// produces both from the same annotations.
///
/// Guards (#68), back behaviour (#69) and deep links (#70) are wired into this
/// object by their own issues; what is here is the table and the shell.
GoRouter buildRouter({String initialLocation = '/today'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: $appRoutes,
  // A link that matches nothing is a stale notification or a stale widget,
  // not something to show the learner a framework page about — and not
  // something to show them a blank screen about either. Redirecting rather
  // than rendering an error screen is what puts the tab bar back: they end up
  // on Today with somewhere to go, which is the whole difference between a
  // dead end and a wrong turn.
  //
  // #70 replaces this with the deep-link handling, which will know the
  // difference between a link it cannot parse and one it can.
  onException: (context, state, router) => router.go(fallbackLocation),
);

/// Where an unmatched link lands. Today, because it is the one screen that is
/// always meaningful and always has the tab bar under it.
const String fallbackLocation = '/today';
