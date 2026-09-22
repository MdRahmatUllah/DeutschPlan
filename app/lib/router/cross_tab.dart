import 'package:deutschplan/router/app_shell.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Jumps from one tab to a screen in another. `navigation.md`:
///
/// > **Cross-tab jumps** (`T1 → L2`, `M1 → L10` …) switch the branch, then
/// > push, so back walks the target tab's natural parents.
///
/// Today's step chip, the grammar card, the exam card and the Me badges all
/// do this, and they all do it through here — one name for the intent, and
/// one place the promise about back is written down and tested.
///
/// **It is thin, and that is the finding rather than a shortcut.** `go` on a
/// typed nested route already builds the whole parent stack in the target
/// branch: I measured the trail from Today for four shapes, and
/// `/me/settings/reminder` walks back through `/me/settings` and `/me` to
/// `/today`. There is no switching code to write. What this adds is the
/// name, the check below, and `cross_tab_test.dart` — which is what stops
/// the behaviour regressing silently, since nothing else asserted it.
extension CrossTabNavigation on BuildContext {
  /// Opens [destination] in its own tab.
  ///
  /// [destination] must be a route inside one of the four branches. A
  /// full-screen route — `/study`, `/quiz`, `/exam/:id` — is not a cross-tab
  /// jump: it covers the tab bar and closing it returns to the opener, which
  /// is the opposite of what this promises about back. Pushing one through
  /// here would be a category error, so it is an assert rather than a comment.
  void jumpToTab(GoRouteData destination) {
    assert(
      isTabDestination(destination.location),
      '${destination.location} is not inside a tab. A full-screen route is '
      'opened with `go`/`push` directly — it covers the tab bar, and closing '
      'it returns to the opener rather than walking a tab\'s parents.',
    );

    destination.go(this);
  }
}

/// Whether a location lives inside one of the four branches.
///
/// `/learn` counts and so does `/learn/step/A1.1`; `/learnt` does not, which
/// is why this compares path segments rather than using `startsWith`.
bool isTabDestination(String location) {
  final path = Uri.parse(location).path;
  return AppShell.tabRoots.any(
    (root) => path == root || path.startsWith('$root/'),
  );
}
