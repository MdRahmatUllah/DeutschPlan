import 'package:deutschplan/router/routes.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
  // A route that does not exist is a bug in a link, not something to show the
  // learner a framework page about. #70 replaces this with the deep-link
  // handling; until then it lands on Today rather than on a red screen.
  errorBuilder: (context, state) => const SizedBox.shrink(),
  redirect: (context, state) => state.matchedLocation.isEmpty ? '/today' : null,
);
