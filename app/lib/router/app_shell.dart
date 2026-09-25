import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/router/back_behaviour.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The four tab stacks and the bar that switches them.
///
/// `StatefulShellRoute.indexedStack` keeps every branch alive, which is what
/// "tabs keep state" means: coming back to Learn finds the same scroll
/// position and the same pushed route, not a rebuilt screen.
///
/// The re-tap behaviour is the part worth reading. `navigation.md`: "re-tap
/// scrolls to top, second re-tap pops to root." Both, in that order — a
/// re-tap that popped straight to root would throw away a screen the learner
/// is reading just because they touched the tab they were already on.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// How long the scroll-to-top takes. Short: it is an acknowledgement of the
  /// tap, not a journey.
  static const Duration scrollToTop = Duration(milliseconds: 250);

  /// Below this the list counts as already at the top, and the second re-tap
  /// behaviour takes over. A list a few pixels down should not eat a tap.
  static const double topThreshold = 8;

  void _onSelected(BuildContext context, int index) {
    if (index != navigationShell.currentIndex) {
      // `initialLocation: false` keeps the branch where it was — switching to
      // Learn should find the step the learner had open, not /learn.
      navigationShell.goBranch(index);
      return;
    }

    if (_scrollToTop(context)) return;
    _popToRoot(context);
  }

  /// Returns true when there was something to scroll.
  bool _scrollToTop(BuildContext context) {
    final position = _topScrollPosition(context);
    if (position == null) return false;
    if (position.pixels <= position.minScrollExtent + topThreshold) {
      return false;
    }

    // #164: reduce motion jumps rather than scrolls.
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(position.minScrollExtent);
    } else {
      position.animateTo(
        position.minScrollExtent,
        duration: scrollToTop,
        curve: Curves.easeOut,
      );
    }
    return true;
  }

  /// The scroll position of the visible branch's topmost route.
  ///
  /// Positions without content dimensions are skipped, and that part is not
  /// cosmetic: a pushed route leaves the tab root's controller with clients
  /// but no laid-out viewport, and asking one for `minScrollExtent` throws.
  /// Taking the last match keeps the answer right if a route is ever pushed
  /// that does not cover the one below it.
  ScrollPosition? _topScrollPosition(BuildContext context) {
    ScrollPosition? found;

    for (final element in _visibleElements<PrimaryScrollController>(context)) {
      final controller = (element.widget as PrimaryScrollController).controller;
      if (controller == null || !controller.hasClients) continue;
      for (final position in controller.positions) {
        if (position.hasContentDimensions && position.hasPixels) {
          found = position;
        }
      }
    }
    return found;
  }

  void _popToRoot(BuildContext context) {
    final element = _visibleElements<Navigator>(context).firstOrNull;
    if (element is! StatefulElement) return;
    final state = element.state as NavigatorState;
    if (!state.canPop()) return;
    state.popUntil((route) => route.isFirst);
  }

  /// Every [T] below this shell that is actually on screen, in tree order.
  ///
  /// `IndexedStack` keeps every branch alive — that is what "tabs keep state"
  /// means — and wraps the ones that are not showing in an `Offstage`. Their
  /// scroll controllers still have clients, so a search that did not skip
  /// them would scroll the wrong tab: the learner taps Today and Learn jumps
  /// to the top behind it.
  List<Element> _visibleElements<T extends Widget>(BuildContext context) {
    final found = <Element>[];

    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is Visibility && !widget.visible) return;

      if (widget is T) found.add(element);
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  /// The four branch roots, in branch order. A location that is one of these
  /// is a tab root; anything else inside the shell is pushed on top of one.
  static const List<String> tabRoots = <String>[
    '/today',
    '/learn',
    '/search',
    '/me',
  ];

  /// Whether the visible branch has nothing pushed on it.
  ///
  /// Read from the location rather than from the branch navigator, because
  /// `PopScope.canPop` is a *snapshot taken when this widget builds* — and
  /// pushing a route inside a branch does not rebuild the shell. Reading the
  /// navigator gave the answer for the stack as it was one route ago, which
  /// made predictive back offer to close the app from a pushed screen.
  /// `GoRouterState.of` rebuilds on every navigation, so this one is current.
  static bool onTabRoot(String location) => tabRoots.contains(location);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = context.tokens;

    final location = GoRouterState.of(context).uri.path;

    return ShellBackHandler(
      onTabRoot: () => onTabRoot(location),
      isFirstTab: () => navigationShell.currentIndex == 0,
      goToFirstTab: () => navigationShell.goBranch(0),
      child: AdaptiveScaffold(
        backgroundColor: tokens.surface.paper,
        body: navigationShell,
        bottomBar: AdaptiveNavBar(
          currentIndex: navigationShell.currentIndex,
          onSelected: (index) => _onSelected(context, index),
          destinations: <AdaptiveNavDestination>[
            AdaptiveNavDestination(
              icon: Icons.today_outlined,
              selectedIcon: Icons.today,
              label: l10n.tabToday,
              colour: tokens.color.primary,
              onColour: tokens.color.onPrimary,
            ),
            AdaptiveNavDestination(
              icon: Icons.school_outlined,
              selectedIcon: Icons.school,
              label: l10n.tabLearn,
              colour: tokens.color.accent,
              onColour: tokens.color.onAccent,
            ),
            AdaptiveNavDestination(
              icon: Icons.search_outlined,
              selectedIcon: Icons.search,
              label: l10n.tabSearch,
              colour: tokens.color.die,
              onColour: tokens.color.onAccent,
            ),
            AdaptiveNavDestination(
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: l10n.tabMe,
              colour: tokens.color.der,
              onColour: tokens.color.onDer,
            ),
          ],
        ),
      ),
    );
  }
}
