import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, immutable;
import 'package:material_ui/material_ui.dart';

/// Which platform's chrome to draw.
///
/// `docs/01-architecture/theming.md`: "Chrome follows the platform through
/// `Adaptive*` wrappers... Material 3 on Android, Cupertino on iOS. Content
/// components (word card, rating bar, ring, charts) are identical on both."
///
/// Only the chrome differs. Everything a learner reads or rates is the same
/// widget on both platforms, which is what keeps one set of screen files.
enum AdaptiveChrome {
  material,
  cupertino;

  static AdaptiveChrome forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => AdaptiveChrome.cupertino,
        _ => AdaptiveChrome.material,
      };
}

/// Overrides the chrome for a subtree. Goldens render both without an emulator.
class AdaptiveChromeScope extends InheritedWidget {
  const AdaptiveChromeScope({
    required this.chrome,
    required super.child,
    super.key,
  });

  final AdaptiveChrome chrome;

  static AdaptiveChrome of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AdaptiveChromeScope>();
    if (scope != null) return scope.chrome;
    return AdaptiveChrome.forPlatform(Theme.of(context).platform);
  }

  @override
  bool updateShouldNotify(AdaptiveChromeScope oldWidget) =>
      chrome != oldWidget.chrome;
}

extension AdaptiveContext on BuildContext {
  AdaptiveChrome get chrome => AdaptiveChromeScope.of(this);
  bool get isCupertino => chrome == AdaptiveChrome.cupertino;
}

/// A screen with a platform-appropriate top bar.
///
/// The bar is 56 dp on Android with a leading icon and a left-aligned title,
/// and 44 pt on iOS with a centred title — both read off the artboards.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.body,
    super.key,
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.bottomBar,
    this.backgroundColor,
  });

  final Widget body;
  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottomBar;
  final Color? backgroundColor;

  /// Android 56 dp, iOS 44 pt — the artboards draw exactly these.
  static const double materialBarHeight = 56;
  static const double cupertinoBarHeight = 44;

  /// The back affordance, supplied by default so ~20 pushed routes do not each
  /// rebuild it — and so the two platform treatments the artboards draw (an
  /// Android chevron, an iOS chevron with a 17 pt label) stay in one place.
  static Widget? _defaultBack(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || !route.canPop) return null;
    return AdaptiveBackButton(
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final background = backgroundColor ?? tokens.surface.paper;

    return Scaffold(
      backgroundColor: background,
      body: Column(
        children: <Widget>[
          if (title != null || leading != null || actions.isNotEmpty)
            SafeArea(bottom: false, child: _bar(context)),
          Expanded(
            child: bottomBar == null
                ? SafeArea(top: false, child: body)
                // The bar below takes the system inset, so the body — and a
                // tab's own scaffold inside it — must not take it again.
                : MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: body,
                  ),
          ),
          if (bottomBar != null)
            // Without the top inset: the body runs edge to edge, so the status
            // bar's height reaches down here, and Material's NavigationBar
            // pads its own top by it — a status bar's worth of empty bar.
            MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SafeArea(top: false, child: bottomBar!),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final cupertinoChrome = context.isCupertino;
    final height = cupertinoChrome ? cupertinoBarHeight : materialBarHeight;
    final back = leading ?? _defaultBack(context);

    final titleWidget = title == null
        ? const SizedBox.shrink()
        // One line, cut after the last whole word that fits: a category's
        // name can run to thirty letters, and a bar is one line tall.
        : DpText(title!, role: DpTextRole.title, maxLines: 1);

    if (!cupertinoChrome) {
      return SizedBox(
        height: height,
        child: Row(
          children: <Widget>[
            if (back != null) back else const SizedBox(width: 8),
            const SizedBox(width: 4),
            Expanded(child: titleWidget),
            ...actions,
          ],
        ),
      );
    }

    // iOS centres the title and lets the leading and trailing groups sit at the
    // edges, so a long title stays centred rather than shifting with the back
    // button's width — until it would run under one of them, when the toolbar
    // moves it clear and the one line stops short.
    return SizedBox(
      height: height,
      child: NavigationToolbar(
        leading: back,
        middle: titleWidget,
        trailing: actions.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: actions),
        middleSpacing: 8,
      ),
    );
  }
}

/// The back affordance, in whichever treatment the platform draws.
///
/// Android is a chevron alone; iOS is a chevron with the 17 pt label the
/// artboards show. Both are 44 pt wide, which clears the minimum tap target.
class AdaptiveBackButton extends StatelessWidget {
  const AdaptiveBackButton({
    required this.onPressed,
    super.key,
    this.label,
    this.colour,
  });

  final VoidCallback onPressed;

  /// The iOS label. Android ignores it — Material back buttons carry no text.
  final String? label;

  /// The link colour unless given: L2's arrow is ink on its Sun header.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cupertinoChrome = context.isCupertino;

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 44,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colour ?? tokens.color.link,
            padding: EdgeInsets.symmetric(horizontal: cupertinoChrome ? 8 : 12),
            minimumSize: const Size(44, 44),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                cupertinoChrome
                    ? cupertino.CupertinoIcons.back
                    : Icons.arrow_back,
                color: colour ?? tokens.color.link,
              ),
              if (cupertinoChrome && label != null) ...<Widget>[
                const SizedBox(width: 2),
                DpText(
                  label!,
                  role: DpTextRole.bodyLarge,
                  color: colour ?? tokens.color.link,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The on/off control. Lagoon when on in both chromes; the sizes differ.
class AdaptiveSwitch extends StatelessWidget {
  const AdaptiveSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Required, not optional. accessibility-performance.md: "every control
  /// labelled". Settings alone carries eight switches; an optional label is
  /// eight chances to ship one a screen reader announces as just "switch, on".
  final String semanticLabel;

  /// The visual TRACK, as the artboards draw it: Android 52×32 with a 2 px ink
  /// border, iOS 51×31 with none. The border is what makes the Android switch
  /// read as Paper & Ink rather than stock Material.
  ///
  /// The widget itself is larger, and deliberately so — Material pads the track
  /// out to a 48 dp tap target and Cupertino to 39 pt, which is what
  /// accessibility-performance.md asks for with "targets >= 48 dp / 44 pt".
  static const Size materialTrack = Size(52, 32);
  static const Size cupertinoTrack = Size(51, 31);

  /// The smallest tap target accessibility-performance.md allows.
  static const double minimumTapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final control = context.isCupertino
        ? cupertino.CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: tokens.color.primary,
          )
        : Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: tokens.surface.card,
            activeTrackColor: tokens.color.primary,
            inactiveTrackColor: tokens.surface.muted,
            trackOutlineColor: WidgetStatePropertyAll<Color>(tokens.color.ink),
            trackOutlineWidth: const WidgetStatePropertyAll<double>(2),
          );

    return Semantics(label: semanticLabel, child: control);
  }
}

/// A small set of mutually exclusive options — Week · Month · All, the meaning
/// language, the article picker.
class AdaptiveSegmented<T extends Object> extends StatelessWidget {
  const AdaptiveSegmented({
    required this.segments,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Ordered; the map's keys are the values and the strings are the labels.
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (context.isCupertino) {
      return cupertino.CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: tokens.surface.muted,
        thumbColor: tokens.surface.card,
        onValueChanged: (next) {
          if (next != null) onChanged(next);
        },
        children: <T, Widget>{
          for (final entry in segments.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: DpText(entry.value, role: DpTextRole.label),
            ),
        },
      );
    }

    return SegmentedButton<T>(
      segments: <ButtonSegment<T>>[
        for (final entry in segments.entries)
          ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
      ],
      selected: <T>{value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// A screen's inner tabs — L2's Words · Grammar · Quiz · Exams.
///
/// Android draws a Material `TabBar`: labels across the width, a 3 dp ink
/// indicator inset 12 from each side, a hairline under it. iOS draws the
/// sliding segmented control in a 16 pt gutter, as `AdaptiveSegmented` does.
class AdaptiveTabBar<T extends Object> extends StatefulWidget {
  const AdaptiveTabBar({
    required this.tabs,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// Ordered; the keys are the values and the strings the labels.
  final Map<T, String> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  State<AdaptiveTabBar<T>> createState() => _AdaptiveTabBarState<T>();
}

class _AdaptiveTabBarState<T extends Object> extends State<AdaptiveTabBar<T>>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: widget.tabs.length,
    initialIndex: _index,
    vsync: this,
  );

  int get _index => widget.tabs.keys.toList().indexOf(widget.value);

  @override
  void didUpdateWidget(AdaptiveTabBar<T> old) {
    super.didUpdateWidget(old);
    if (_controller.index != _index) _controller.animateTo(_index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (context.isCupertino) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SizedBox(
          width: double.infinity,
          child: AdaptiveSegmented<T>(
            segments: widget.tabs,
            value: widget.value,
            onChanged: widget.onChanged,
          ),
        ),
      );
    }
    final keys = widget.tabs.keys.toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.surface.outline)),
      ),
      child: TabBar(
        controller: _controller,
        onTap: (index) => widget.onChanged(keys[index]),
        labelColor: tokens.color.ink,
        unselectedLabelColor: tokens.color.textSecondary,
        // 14 on the artboard, between the label and body roles.
        labelStyle: DpText.styleFor(
          tokens,
          DpTextRole.label,
        ).copyWith(fontSize: 14),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: tokens.color.ink, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          insets: const EdgeInsets.symmetric(horizontal: 12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        tabs: <Widget>[
          for (final label in widget.tabs.values) Tab(height: 48, text: label),
        ],
      ),
    );
  }
}

/// Somewhere in a sheet or pane for its toasts to show.
///
/// A `DpToast` goes to the nearest `ScaffoldMessenger`, which draws it in the
/// page's `Scaffold`: under a sheet that covers the page, and under a pane's
/// scrim. This gives [child] a messenger and a transparent scaffold of its
/// own, so "No German voice…" and #141's Undo show above it. It fills its
/// space, so it suits a sheet or pane of a set height (W1's), not one that
/// sizes to its content.
class AdaptiveToastScope extends StatelessWidget {
  const AdaptiveToastScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: Scaffold(
      backgroundColor: context.tokens.surface.paper.withValues(alpha: 0),
      resizeToAvoidBottomInset: false,
      body: child,
    ),
  );
}

/// Platform-appropriate modal presentations.
///
/// These are functions rather than widgets because that is how Flutter presents
/// them, and wrapping them keeps `showModalBottomSheet` and
/// `showCupertinoModalPopup` out of every screen file.
abstract final class Adaptive {
  /// A bottom sheet. Sheets use `cardStrong`, and under glass they blur over
  /// the scrim rather than over other glass.
  ///
  /// Note for #90: `showCupertinoModalPopup` has no drag-to-dismiss, so
  /// FR-T3-03 ("dismissing the sheet by dragging down behaves as *Done for
  /// now*") needs a drag handle on iOS.
  static Future<T?> showSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    final tokens = context.tokens;
    final chrome = context.chrome;

    // The sheet is a route of its own, above wherever the opener's chrome
    // scope sits: it carries the chrome with it, or an iOS sheet would draw
    // Material controls.
    //
    // On the root navigator nothing above the sheet shrinks for the keyboard,
    // so the sheet rises by the inset itself: M1's name field stays in view.
    Widget wrap(BuildContext sheetContext) => AdaptiveChromeScope(
      chrome: chrome,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: DpSurface(
          kind: DpSurfaceKind.cardStrong,
          radius: tokens.shape.sheet,
          child: SafeArea(top: false, child: builder(sheetContext)),
        ),
      ),
    );

    if (chrome == AdaptiveChrome.cupertino) {
      // A Cupertino popup has no Material under it, and a sheet's buttons,
      // fields and text styles need one: without it every line came out with
      // the yellow "no Material" underline and a DpButton threw (#122).
      return cupertino.showCupertinoModalPopup<T>(
        context: context,
        builder: (sheetContext) => Material(
          type: MaterialType.transparency,
          child: wrap(sheetContext),
        ),
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      // Over the tab bar, as the Cupertino popup already is and the
      // artboards draw it: a sheet on a tab's own navigator left the bar
      // uncovered and live under the scrim.
      useRootNavigator: true,
      isScrollControlled: true,
      // The sheet's own surface is the DpSurface inside; Material must not
      // paint one behind it, or the glass panel sits on a solid slab.
      // Fully transparent is the absence of a colour, not a token.
      backgroundColor: const Color(0x00000000), // ponytail: allow-raw-colour
      elevation: 0,
      builder: wrap,
    );
  }

  /// A full-height pane along the trailing edge, over a scrim: a tablet's
  /// sheet (W1's "tablets: right pane", `word-detail.md`). The page under it
  /// stays as it was; a tap on the scrim or back closes it.
  ///
  /// ponytail: an overlay pane, not a true split view that narrows the opener
  /// — the openers are every list in the app, and none has a two-pane layout
  /// to give up half of. Revisit if a tablet artboard ever draws one.
  static Future<T?> showPane<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double width = 420,
  }) {
    final tokens = context.tokens;
    final chrome = context.chrome;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: tokens.surface.scrim,
      transitionDuration: tokens.motion.standard,
      pageBuilder: (paneContext, _, _) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          width: width,
          height: double.infinity,
          // A dialog route has no Material under it: text needs this one's
          // DefaultTextStyle, as a popup sheet does.
          // Its route sits above the opener's chrome scope, as a sheet's
          // does, so it carries the chrome with it (#122).
          child: AdaptiveChromeScope(
            chrome: chrome,
            child: Material(
              type: MaterialType.transparency,
              child: DpSurface(
                kind: DpSurfaceKind.cardStrong,
                radius: 0,
                child: SafeArea(
                  left: false,
                  child: AdaptiveToastScope(child: builder(paneContext)),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  /// A confirmation dialog. [destructive] colours the confirm action Coral —
  /// the leave-exam and reset dialogs use it.
  static Future<bool?> showConfirm({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) {
    final tokens = context.tokens;

    if (context.isCupertino) {
      return cupertino.showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => cupertino.CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            cupertino.CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            cupertino.CupertinoDialogAction(
              isDestructiveAction: destructive,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: tokens.surface.card,
        title: DpText(title, role: DpTextRole.title),
        content: DpText(message, role: DpTextRole.body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: destructive
                  ? tokens.color.again
                  : tokens.color.primary,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// The reminder time. Material shows a dialog; iOS shows the wheel in a sheet,
  /// which is what `onboarding.md` and `reminder-days.md` describe.
  static Future<TimeOfDay?> showTimePickerFor({
    required BuildContext context,
    required TimeOfDay initial,
  }) async {
    if (!context.isCupertino) {
      return showTimePicker(context: context, initialTime: initial);
    }

    final today = DateTime.now();
    var picked = DateTime(
      today.year,
      today.month,
      today.day,
      initial.hour,
      initial.minute,
    );

    final confirmed = await cupertino.showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: 280,
        child: DpSurface(
          kind: DpSurfaceKind.cardStrong,
          radius: sheetContext.tokens.shape.sheet,
          child: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: cupertino.CupertinoDatePicker(
                    mode: cupertino.CupertinoDatePickerMode.time,
                    initialDateTime: picked,
                    use24hFormat: true,
                    onDateTimeChanged: (value) => picked = value,
                  ),
                ),
                cupertino.CupertinoButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(AppLocalizations.of(sheetContext).done),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return null;
    return TimeOfDay(hour: picked.hour, minute: picked.minute);
  }
}

/// One destination of [AdaptiveNavBar].
@immutable
class AdaptiveNavDestination {
  const AdaptiveNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.colour,
    this.onColour,
  });

  final IconData icon;

  /// Filled when the tab is the current one; the artboards draw both.
  final IconData selectedIcon;

  final String label;

  /// The pill under the tab when it is the current one: each tab has its
  /// own on the artboards — Today Lagoon, Learn Sun, Search Raspberry, Me
  /// Cobalt. Lagoon when null.
  final Color? colour;

  /// The selected icon on [colour].
  final Color? onColour;
}

/// The four-tab bar at the foot of the shell.
///
/// Android draws a Material `NavigationBar`, iOS the flat bar with a hairline
/// top border that `CupertinoTabBar` gives — the same difference every other
/// `Adaptive*` wrapper exists for. Built here rather than in the router so the
/// platform branch stays in one place and the shell is only routing.
class AdaptiveNavBar extends StatelessWidget {
  const AdaptiveNavBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<AdaptiveNavDestination> destinations;
  final int currentIndex;

  /// Called on every tap, including a tap on the tab already showing — the
  /// shell needs those to scroll to top and then pop to root.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (context.isCupertino) {
      return cupertino.CupertinoTabBar(
        currentIndex: currentIndex,
        onTap: onSelected,
        backgroundColor: tokens.surface.card,
        activeColor: tokens.color.ink,
        inactiveColor: tokens.color.textSecondary,
        items: <cupertino.BottomNavigationBarItem>[
          for (final destination in destinations)
            cupertino.BottomNavigationBarItem(
              icon: Icon(destination.icon),
              activeIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      );
    }

    // The artboards' bar: a hairline on top, the tab's own pill under the
    // current tab, and 12 pt labels — ink when chosen, Slate otherwise.
    final label = Theme.of(context).textTheme.labelSmall!;
    final current = destinations[currentIndex];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.surface.outline)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: tokens.surface.card,
        indicatorColor: current.colour ?? tokens.color.primary,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? label.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.color.ink,
                )
              : label.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: tokens.color.textSecondary,
                ),
        ),
        // Material swallows a tap on the current destination; the shell's
        // re-tap behaviour depends on hearing it, so this is wired directly.
        onDestinationSelected: onSelected,
        destinations: <Widget>[
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon, color: tokens.color.ink),
              // On the bright pill, the ink made for its colour.
              selectedIcon: Icon(
                destination.selectedIcon,
                color: destination.onColour ?? tokens.color.onPrimary,
              ),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

/// Pull-to-refresh round a scrollable.
///
/// The scrollable has to be able to scroll with nothing to scroll —
/// [AlwaysScrollableScrollPhysics] — or a short screen cannot be pulled.
// ponytail: Material's indicator on both chromes. iOS's own is a sliver
// control, which needs the screen built from slivers; do it with iOS's pass.
class AdaptiveRefresh extends StatelessWidget {
  const AdaptiveRefresh({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: tokens.color.ink,
      backgroundColor: tokens.surface.card,
      child: child,
    );
  }
}

/// The platform the app would pick with no override, for diagnostics.
AdaptiveChrome get defaultChrome =>
    AdaptiveChrome.forPlatform(defaultTargetPlatform);
