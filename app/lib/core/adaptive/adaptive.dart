import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, MatrixUtils, RenderProxyBox;
import 'package:flutter/semantics.dart' show SemanticsConfiguration;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/system_bars.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';

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
    this.statusBarColour,
  });

  final Widget body;
  final String? title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottomBar;
  final Color? backgroundColor;

  /// A tab's header colour, for the strip behind the status bar once its
  /// content scrolls (#317). The app is edge to edge: at rest the header
  /// bleeds to the top as the artboards draw it, and scrolled, cards would
  /// run under the clock and icons without it. Frosted under glass.
  final Color? statusBarColour;

  /// Android 56 dp, iOS 44 pt — the artboards draw exactly these.
  static const double materialBarHeight = 56;
  static const double cupertinoBarHeight = 44;

  /// The bar title's size, as the artboards draw it (#280): Android 22,
  /// between the scale's title and headline, and iOS 17, its bodyLarge.
  /// Both at 600.
  static const double materialTitleSize = 22;

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
    // #1070: the status bar's icons for what is behind it: the tab's strip
    // once scrolled (#317), else the page. Flutter sends a style only where
    // it finds one, so without the page's a header's outlived it, scrolled
    // away or on the next screen. A header over it sets its own. Under glass
    // the page is see-through, and its paper decides.
    final behindBar =
        statusBarColour ??
        (background.a == 1 ? background : tokens.surface.paper);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: barsOver(behindBar),
      child: Scaffold(
        backgroundColor: background,
        body: Column(
          children: <Widget>[
            if (title != null || leading != null || actions.isNotEmpty)
              SafeArea(bottom: false, child: _bar(context)),
            Expanded(
              child: bottomBar == null
                  ? SafeArea(
                      top: false,
                      child: statusBarColour == null
                          ? body
                          : _StatusStrip(colour: statusBarColour!, child: body),
                    )
                  // The bar below takes the system inset, so the body — and a
                  // tab's own scaffold inside it — must not take it again. The
                  // same for the keyboard: this scaffold already rises above
                  // it, and a tab's scaffold that rose again left R1's results
                  // a sliver between the field and the keyboard.
                  : MediaQuery(
                      data: MediaQuery.of(context)
                          .removePadding(removeBottom: true)
                          .removeViewInsets(removeBottom: true),
                      child: body,
                    ),
            ),
            // The keyboard covers the tab bar rather than lifting it (#390):
            // a screen being typed in needs the room, and the tabs are no use
            // until the keyboard goes.
            if (bottomBar != null &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
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
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final cupertinoChrome = context.isCupertino;
    final role = cupertinoChrome ? SgTextRole.bodyLarge : SgTextRole.title;
    final size = cupertinoChrome ? null : materialTitleSize;
    final back = leading ?? _defaultBack(context);
    // The artboard's height is a minimum (#314): at 200 % text the title's
    // line outgrows 56 dp, and the bar grows with it rather than cut it.
    final line = _titleLine(
      context,
      role,
      size: size,
      bangla: title != null && SgScript.hasBengali(title!),
    );
    final height = math.max(
      cupertinoChrome ? cupertinoBarHeight : materialBarHeight,
      line + 8,
    );

    final titleWidget = title == null
        ? const SizedBox.shrink()
        // One line, and a title that doesn't fit is cut after its last whole
        // word with "…" (#280). A category's name can run to thirty letters,
        // and a bar is one line tall.
        : SgOneLine(title!, role: role, weight: 600, size: size);

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

/// The height of one line of a bar title at [role] and [size], the ones its
/// SgOneLine gets, at the learner's text size, with a Bangla run a role up,
/// as SgOneLine sets it.
double _titleLine(
  BuildContext context,
  SgTextRole role, {
  required double? size,
  required bool bangla,
}) {
  final tokens = context.tokens;
  final scaler = MediaQuery.textScalerOf(context);
  double lineOf(SgTextRole at, {double? size}) {
    final token = at.token(tokens.typography);
    return scaler.scale(size ?? token.size) * token.heightFactor;
  }

  final latin = lineOf(role, size: size);
  return bangla ? math.max(latin, lineOf(role.oneStepLarger)) : latin;
}

/// [child], with a strip of [colour] over the status bar while its own
/// vertical scroll is away from the top.
class _StatusStrip extends StatefulWidget {
  const _StatusStrip({required this.colour, required this.child});

  final Color colour;
  final Widget child;

  @override
  State<_StatusStrip> createState() => _StatusStripState();
}

class _StatusStripState extends State<_StatusStrip> {
  bool _scrolled = false;

  bool _moved(ScrollNotification notification) {
    final metrics = notification.metrics;
    // The tab's own list, not a chip row or a list inside it.
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    final scrolled = metrics.pixels > metrics.minScrollExtent;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _moved,
          child: widget.child,
        ),
        if (_scrolled && top > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top,
            // Under glass a blur of its own, not the screen's shared read
            // (#709): it lies over the list scrolled under it, and the shared
            // read is taken at the list's first panel, before the rest.
            child: tokens.isGlass
                ? SgSurface(
                    kind: SgSurfaceKind.tint(widget.colour),
                    radius: 0,
                    child: const SizedBox.expand(),
                  )
                : ColoredBox(color: widget.colour),
          ),
      ],
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

  /// The button's height: 44, the tap target, or the iOS [label]'s line when
  /// larger text makes that taller (#404). A row that holds the button grows
  /// with it.
  static double heightOf(BuildContext context, {String? label}) =>
      context.isCupertino && label != null
      ? math.max(
          44,
          // A Bangla label draws one role larger, as a bar title does.
          _titleLine(
            context,
            SgTextRole.bodyLarge,
            size: null,
            bangla: SgScript.hasBengali(label),
          ),
        )
      : 44;

  /// The link colour unless given: L2's arrow is ink on its Sun header.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cupertinoChrome = context.isCupertino;

    // One node, named (#315). The TextButton gives the tap and this the
    // name; apart, a screen reader found a nameless button beside a name it
    // could not press. Android says "Back", as a Material back button does;
    // iOS reads the title its chevron shows.
    return AdaptiveTapTarget(
      merge: true,
      child: Semantics(
        button: true,
        attributedLabel: SgScript.attributedLabel(
          cupertinoChrome && label != null
              ? label
              : MaterialLocalizations.of(context).backButtonTooltip,
        ),
        // 44, the tap target; taller when the iOS label's line is (#404): at
        // 200 % it is 48 dp, and a fixed 44 cut it.
        child: SizedBox(
          height: heightOf(context, label: label),
          child: AdaptiveTooltip(
            message: MaterialLocalizations.of(context).backButtonTooltip,
            child: TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: colour ?? tokens.color.link,
                padding: EdgeInsets.symmetric(
                  horizontal: cupertinoChrome ? 8 : 12,
                ),
                minimumSize: const Size(44, 44),
              ),
              child: ExcludeSemantics(
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
                      // One line, cut after a whole word as iOS cuts a long
                      // back title: in Bangla at 200 % it ran 16 dp past the
                      // bar's leading slot (#588).
                      Flexible(
                        child: SgOneLine(
                          label!,
                          role: SgTextRole.bodyLarge,
                          color: colour ?? tokens.color.link,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small control's target, grown to the platform's minimum — 48 dp under
/// Material chrome, 44 pt under iOS chrome (`accessibility-performance.md`)
/// — without growing its layout, so the artboard stays as drawn (#478). A
/// tap around the control lands on it, and a screen reader's node is the
/// grown area. It is the control's own semantics node, as
/// `Semantics(container: true)` would be: the control's label and actions
/// gather on it, so the control's own `Semantics` mustn't be a container.
/// ponytail: a tap outside its parent's box never reaches it (a chip in a
/// one-row `Wrap` takes none from above the row); the node is grown anyway.
class AdaptiveTapTarget extends SingleChildRenderObjectWidget {
  const AdaptiveTapTarget({
    required Widget super.child,
    super.key,
    this.merge = false,
  });

  /// Everything under it read as one node, as `MergeSemantics` does: for a
  /// control built of pieces that would each be a node (the back button's
  /// `TextButton` and its label).
  final bool merge;

  static Size minimumOf(BuildContext context) =>
      context.isCupertino ? const Size.square(44) : const Size.square(48);

  /// The run spacing of a `Wrap` of controls at least [height] tall, drawn
  /// under the target (#952): 48 less [height], and 8 at the least. Closer,
  /// two runs' grown targets overlap: a tap between the runs is either's,
  /// and a screen reader takes the runs for one row and reads it column by
  /// column (Flutter groups nodes whose extents overlap, then sorts by x).
  /// 48 under iOS chrome too, one layout for both: 44 pt needs less.
  static double runSpacing(double height) => math.max(8, 48 - height);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderAdaptiveTapTarget(minimumOf(context), merge);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAdaptiveTapTarget renderObject,
  ) => renderObject
    ..minimum = minimumOf(context)
    ..merge = merge;
}

/// [AdaptiveTapTarget]'s box: its layout the child's, its hit test and
/// semantic bounds grown to the minimum.
class RenderAdaptiveTapTarget extends RenderProxyBox {
  RenderAdaptiveTapTarget(this._minimum, [this._merge = false]);

  bool _merge;
  set merge(bool value) {
    if (value == _merge) return;
    _merge = value;
    markNeedsSemanticsUpdate();
  }

  Size _minimum;
  set minimum(Size value) {
    if (value == _minimum) return;
    _minimum = value;
    markNeedsSemanticsUpdate();
  }

  /// The box grown, about its centre, to the minimum on each side short of it.
  Rect get _area {
    final dx = math.max(0, _minimum.width - size.width) / 2;
    final dy = math.max(0, _minimum.height - size.height) / 2;
    return Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
  }

  @override
  Rect get semanticBounds => _area;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = _merge;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    if (child == null || !_area.contains(position)) return false;
    // Around the control: a tap on its centre, as Material's padded target
    // gives it.
    final centre = child!.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(centre),
      position: centre,
      hitTest: (result, position) => child!.hitTest(result, position: centre),
    );
  }
}

/// An icon-only control's name, shown on a long press (or a hover) under
/// Material chrome, as a Material icon button's tooltip is (#162). Not under
/// iOS chrome, which has no tooltips, and never read: the control carries
/// the same words as its label.
class AdaptiveTooltip extends StatelessWidget {
  const AdaptiveTooltip({
    required this.message,
    required this.child,
    super.key,
    this.longPress = true,
  });

  /// None: no name to show, so no tooltip.
  final String? message;
  final Widget child;

  /// False where a long press has its own job (a speaker's slow replay):
  /// then only a hover shows it.
  final bool longPress;

  @override
  Widget build(BuildContext context) => context.isCupertino || message == null
      ? child
      : Tooltip(
          message: message,
          excludeFromSemantics: true,
          triggerMode: longPress ? null : TooltipTriggerMode.manual,
          child: child,
        );
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
            // #1049: the app's ring shows the focus, not a second halo.
            focusColor: tokens.color.primary.withValues(alpha: 0),
          )
        // The artboards' Paper & Ink switch: on, an ink thumb with a Lagoon
        // tick on Lagoon; off, a Slate thumb on Oat; each inside a 2 px border
        // of its thumb's colour.
        : Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: tokens.color.ink,
            inactiveThumbColor: tokens.color.textSecondary,
            activeTrackColor: tokens.color.primary,
            inactiveTrackColor: tokens.surface.muted,
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? tokens.color.ink
                  : tokens.color.textSecondary,
            ),
            trackOutlineWidth: const WidgetStatePropertyAll<double>(2),
            thumbIcon: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Icon(Icons.check, color: tokens.color.primary)
                  : null,
            ),
            // #1049: Material's focus halo measured 1.09:1; the app's ring
            // shows the focus instead, and one indicator is enough.
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? tokens.color.primary.withValues(alpha: 0)
                  : null,
            ),
          );
    final track = context.isCupertino ? cupertinoTrack : materialTrack;

    return Semantics(
      attributedLabel: SgScript.attributedLabel(semanticLabel),
      // #1049: the 2 dp ring every control shows under the keys, around the
      // track, while the switch has the focus.
      child: SgFocusable.around(
        radius: BorderRadius.circular(track.height / 2),
        size: track,
        child: control,
      ),
    );
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
      // Its segments are drawn 28 pt, short of iOS's 44, and the control
      // owns their nodes, so no target can grow them: marked dense for the
      // golden check (#478); whether to grow the control is #492.
      return Semantics(
        container: true,
        identifier: 'dense:segmented',
        child: cupertino.CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: tokens.surface.muted,
          thumbColor: tokens.surface.card,
          onValueChanged: (next) {
            if (next != null) onChanged(next);
          },
          children: <T, Widget>{
            for (final entry in segments.entries)
              // One line, shrunk to its segment only when it would not fit, as
              // UIKit's control does: at 150 % "Grammar" wrapped in a quarter
              // of the width and the control's height cut it (#165).
              entry.key: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SgText(
                    entry.value,
                    role: SgTextRole.label,
                    maxLines: 1,
                  ),
                ),
              ),
          },
        ),
      );
    }

    return SegmentedButton<T>(
      segments: <ButtonSegment<T>>[
        for (final entry in segments.entries)
          ButtonSegment<T>(
            value: entry.key,
            // Material's style is `labelLarge`, the label role (#698).
            label: SgChromeLabel(entry.value, role: SgTextRole.label),
          ),
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
    with TickerProviderStateMixin {
  late TabController _controller = _newController();

  /// A controller's length is fixed, so a bar whose tabs change count gets a
  /// new one (#698).
  TabController _newController() => _StillTabController(
    length: widget.tabs.length,
    initialIndex: math.max(_index, 0),
    vsync: this,
    still: () => mounted && MediaQuery.disableAnimationsOf(context),
  );

  /// -1 for a value not among the tabs, which moves nothing (#698).
  int get _index => widget.tabs.keys.toList().indexOf(widget.value);

  @override
  void didUpdateWidget(AdaptiveTabBar<T> old) {
    super.didUpdateWidget(old);
    if (_controller.length != widget.tabs.length) {
      // TabBar lets go of a disposed controller itself.
      _controller.dispose();
      _controller = _newController();
    } else if (_index >= 0 && _controller.index != _index) {
      _controller.animateTo(_index);
    }
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
    // 14 on the artboard, between the label and body roles.
    final labelStyle = SgText.styleFor(
      tokens,
      SgTextRole.label,
    ).copyWith(fontSize: 14);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Past 130 % text, four labels no longer fit a phone's width and the
        // fixed tabs faded them to "Word", "Gram" (#314): they scroll
        // instead. So does a bar whose labels don't fit an equal share of it
        // at any size (#1078): Polish's "Gramatyka" on a 384 dp phone.
        final scroll =
            SgScript.large(context) ||
            !_fit(context, labelStyle, constraints.maxWidth);
        return _bar(context, keys, labelStyle, scroll: scroll);
      },
    );
  }

  /// Whether every label fits an equal share of [width], with the tab's own
  /// 16 dp a side (`kTabLabelPadding`), measured as `SgChromeLabel` draws
  /// it: Bangla a role up.
  bool _fit(BuildContext context, TextStyle style, double width) {
    if (!width.isFinite) return true;
    final share = width / widget.tabs.length - 32;
    final larger = SgTextRole.label.oneStepLarger.token(
      context.tokens.typography,
    );
    for (final label in widget.tabs.values) {
      final painter = TextPainter(
        text: TextSpan(
          style: style,
          children: SgScript.spans(
            label,
            latin: const TextStyle(),
            bengali: TextStyle(
              fontSize: larger.size,
              height: larger.heightFactor,
            ),
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final wide = painter.width > share;
      painter.dispose();
      if (wide) return false;
    }
    return true;
  }

  Widget _bar(
    BuildContext context,
    List<T> keys,
    TextStyle labelStyle, {
    required bool scroll,
  }) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.surface.outline)),
      ),
      child: TabBar(
        controller: _controller,
        onTap: (index) => widget.onChanged(keys[index]),
        isScrollable: scroll,
        tabAlignment: scroll ? TabAlignment.start : null,
        labelColor: tokens.color.ink,
        unselectedLabelColor: tokens.color.textSecondary,
        labelStyle: labelStyle,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: tokens.color.ink, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          insets: const EdgeInsets.symmetric(horizontal: 12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        tabs: <Widget>[
          for (final label in widget.tabs.values)
            // As `Tab(text:)` draws it, with its Bangla a role up (#698).
            Tab(
              height: 48,
              child: SgChromeLabel(
                label,
                role: SgTextRole.label,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
            ),
        ],
      ),
    );
  }
}

/// Somewhere in a sheet or pane for its toasts to show.
///
/// An `SgToast` goes to the nearest `ScaffoldMessenger`, which draws it in the
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
        child: SgSurface(
          kind: SgSurfaceKind.cardStrong,
          // Its foot is the screen's: the page showed through two rounded
          // corners there (#686 ST-8).
          borderRadius: tokens.shape.sheetRadius,
          child: SafeArea(top: false, child: builder(sheetContext)),
        ),
      ),
    );

    if (chrome == AdaptiveChrome.cupertino) {
      // A Cupertino popup has no Material under it, and a sheet's buttons,
      // fields and text styles need one: without it every line came out with
      // the yellow "no Material" underline and an SgButton threw (#122).
      // ponytail: the Cupertino popup slides in even under reduce motion (it
      // takes no animation style, #164); a PopupRoute of our own if a
      // learner or the review asks for it.
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
      // #164: reduce motion shows the sheet without sliding it up.
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      // Over the tab bar, as the Cupertino popup already is and the
      // artboards draw it: a sheet on a tab's own navigator left the bar
      // uncovered and live under the scrim.
      useRootNavigator: true,
      isScrollControlled: true,
      // The sheet's own surface is the SgSurface inside; Material must not
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
              child: SgSurface(
                kind: SgSurfaceKind.cardStrong,
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
      // #164: reduce motion fades the pane in rather than sliding it.
      transitionBuilder: (paneContext, animation, _, child) =>
          MediaQuery.disableAnimationsOf(paneContext)
          ? FadeTransition(opacity: animation, child: child)
          : SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
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
      // The app's font, as the typed confirm sets it: the system's has no
      // Bangla, and "বাতিল" was tofu (#432, #698).
      final font = _appFont(tokens);
      return cupertino.showCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => cupertino.CupertinoAlertDialog(
          title: SgText(
            title,
            role: SgTextRole.body,
            weight: 600,
            textAlign: TextAlign.center,
          ),
          content: SgText(
            message,
            role: SgTextRole.caption,
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            cupertino.CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              textStyle: font,
              child: Text(cancelLabel),
            ),
            cupertino.CupertinoDialogAction(
              isDestructiveAction: destructive,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              textStyle: font,
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      // On the theme's dialog colour: the card, made opaque under glass.
      builder: (dialogContext) => AlertDialog(
        title: SgText(title, role: SgTextRole.title),
        content: SgText(message, role: SgTextRole.body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            // Material's style is `labelLarge`, the label role (#698).
            child: SgChromeLabel(cancelLabel, role: SgTextRole.label),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            // Text colours, not the fills (#318): Coral is 3.0:1 on the card
            // and Lagoon 2.2; their text variants clear 4.5.
            style: TextButton.styleFrom(
              foregroundColor: destructive
                  ? tokens.color.wrongText
                  : tokens.color.link,
            ),
            child: SgChromeLabel(confirmLabel, role: SgTextRole.label),
          ),
        ],
      ),
    );
  }

  /// A confirmation typed out (M7, #149): the confirm action, Coral, stays off
  /// until the field holds [word] exactly — "RESET", not "reset".
  static Future<bool?> showTypedConfirm({
    required BuildContext context,
    required String title,
    required String message,
    required String word,
    required String confirmLabel,
    required String cancelLabel,
  }) {
    // The platform is the caller's: a dialog is pushed above the screen's
    // chrome scope, as showConfirm decides before it pushes too.
    final ios = context.isCupertino;
    Widget dialog(BuildContext _) => _TypedConfirm(
      ios: ios,
      title: title,
      message: message,
      word: word,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
    return ios
        ? cupertino.showCupertinoDialog<bool>(context: context, builder: dialog)
        : showDialog<bool>(context: context, builder: dialog);
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

    // The wheel shows an hour and a minute; the day under them is one no
    // clock changes on, not today: on a spring-forward day 02:30 became 03:30
    // (#686 ST-14).
    var picked = DateTime(2000, 1, 15, initial.hour, initial.minute);

    final confirmed = await cupertino.showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: 280,
        child: SgSurface(
          kind: SgSurfaceKind.cardStrong,
          borderRadius: sheetContext.tokens.shape.sheetRadius,
          child: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: cupertino.CupertinoDatePicker(
                    mode: cupertino.CupertinoDatePickerMode.time,
                    initialDateTime: picked,
                    // The phone's own 12- or 24-hour setting, as Android's
                    // dialog follows it (#686 ST-14).
                    use24hFormat: MediaQuery.alwaysUse24HourFormatOf(
                      sheetContext,
                    ),
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

/// A tab controller that moves without sliding under reduce motion (#164):
/// `TabBar` animates a tapped tab itself, before telling anyone, so the
/// controller is where to stop it.
class _StillTabController extends TabController {
  _StillTabController({
    required super.length,
    required super.vsync,
    required this.still,
    super.initialIndex,
  });

  final bool Function() still;

  @override
  void animateTo(int value, {Duration? duration, Curve curve = Curves.ease}) =>
      super.animateTo(
        value,
        duration: still() ? Duration.zero : duration,
        curve: curve,
      );
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
        // #164: the bar blurs a see-through colour itself; where glass
        // falls back (reduce transparency among the reasons) it gets the
        // card over the paper, fully opaque, or it would blur again.
        backgroundColor:
            tokens.isGlass && !GlassCapabilityScope.blurAllowed(context)
            ? Color.alphaBlend(tokens.surface.card, tokens.surface.paper)
            : tokens.surface.card,
        activeColor: tokens.color.ink,
        inactiveColor: tokens.color.textSecondary,
        // ponytail: iOS's items take a plain label, so its Bangla isn't
        // tagged bn-BD as Android's tabs are (#877); iOS is Later (v1 is
        // Android-only). Wrap the icon and label ourselves on iOS's pass.
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
    // Bangla a role up (#698): 12 is the caption's size, so the label's.
    // Material draws each from a plain string, so the whole bar's style.
    final bangla = destinations.any(
      (destination) => SgScript.hasBengali(destination.label),
    );
    final larger = tokens.typography.label;
    final label = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: bangla ? larger.size : 12,
      height: bangla ? larger.heightFactor : null,
    );
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
                  fontWeight: FontWeight.w600,
                  color: tokens.color.ink,
                )
              : label.copyWith(
                  fontWeight: FontWeight.w500,
                  color: tokens.color.textSecondary,
                ),
        ),
        // Material swallows a tap on the current destination; the shell's
        // re-tap behaviour depends on hearing it, so this is wired directly.
        onDestinationSelected: onSelected,
        destinations: <Widget>[
          for (final (i, destination) in destinations.indexed)
            // #877: the tab read as Material reads it ("আজ", "Tab 1 of 4"),
            // but with its Bangla tagged bn-BD, as #743 tags every other
            // control's: Material builds the node from a plain string, so
            // TalkBack on an English phone read the Bangla with its English
            // voice. Its own node, so the destination's is left out, with
            // the selection and the tap it carried.
            Semantics(
              container: true,
              selected: i == currentIndex,
              attributedLabel: SgScript.attributedLabel(
                '${destination.label}\n'
                '${MaterialLocalizations.of(context).tabLabel(tabIndex: i + 1, tabCount: destinations.length)}',
              ),
              onTap: () => onSelected(i),
              excludeSemantics: true,
              child: NavigationDestination(
                icon: Icon(destination.icon, color: tokens.color.ink),
                // On the bright pill, the ink made for its colour.
                selectedIcon: Icon(
                  destination.selectedIcon,
                  color: destination.onColour ?? tokens.color.onPrimary,
                ),
                label: destination.label,
              ),
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

/// The app's font for an iOS alert's actions, not the system's: the
/// artboards draw the alert in it, as every SgText is, with its Bangla behind
/// it — "বাতিল" was tofu (#432). An action keeps its own colour and size.
TextStyle _appFont(SgTokens tokens) {
  final app = SgText.styleFor(tokens, SgTextRole.body);
  return TextStyle(
    fontFamily: app.fontFamily,
    fontFamilyFallback: app.fontFamilyFallback,
  );
}

/// [Adaptive.showTypedConfirm]'s dialog: the platform's alert with a field.
class _TypedConfirm extends StatefulWidget {
  const _TypedConfirm({
    required this.ios,
    required this.title,
    required this.message,
    required this.word,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final bool ios;
  final String title;
  final String message;
  final String word;
  final String confirmLabel;
  final String cancelLabel;

  @override
  State<_TypedConfirm> createState() => _TypedConfirmState();
}

class _TypedConfirmState extends State<_TypedConfirm> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final font = _appFont(tokens);
    final typed = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _typed,
      builder: (context, value, _) {
        final onConfirm = value.text == widget.word
            ? () => Navigator.of(context).pop(true)
            : null;
        return widget.ios
            ? cupertino.CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: onConfirm,
                textStyle: font,
                child: Text(widget.confirmLabel),
              )
            : TextButton(
                onPressed: onConfirm,
                // Coral text while it waits too, as the artboard draws it,
                // but faded: an action that does nothing yet shouldn't look
                // ready.
                style: TextButton.styleFrom(
                  foregroundColor: tokens.color.wrongText,
                  disabledForegroundColor: tokens.color.wrongText.withValues(
                    alpha: 0.5,
                  ),
                ),
                child: SgChromeLabel(
                  widget.confirmLabel,
                  role: SgTextRole.label,
                ),
              );
      },
    );
    void cancel() => Navigator.of(context).pop(false);

    // The keyboard's room as plain padding, in the same frame, and none for
    // the dialog's own: Material and Cupertino animate their inset over
    // 100 ms, and the field's reveal, run on the keyboard's first frame, saw
    // the dialog where it was, so at 200 % on a 360 × 640 phone the field
    // stayed under the keyboard until typing (#586).
    Widget keyboardAware(Widget dialog) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: dialog,
      ),
    );

    if (widget.ios) {
      return keyboardAware(
        cupertino.CupertinoAlertDialog(
          title: SgText(
            widget.title,
            role: SgTextRole.body,
            weight: 600,
            textAlign: TextAlign.center,
          ),
          content: Column(
            children: <Widget>[
              SgText(
                widget.message,
                role: SgTextRole.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              cupertino.CupertinoTextField(
                controller: _typed,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                style: SgText.styleFor(tokens, SgTextRole.body),
                // Ink-edged, as the artboard draws it on both platforms.
                // 44 pt tall, Apple's minimum target: the default padding made
                // it 38 (#478).
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.surface.cardStrong,
                  border: Border.all(color: tokens.color.ink),
                  borderRadius: BorderRadius.circular(tokens.shape.button),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            cupertino.CupertinoDialogAction(
              onPressed: cancel,
              textStyle: font,
              child: Text(widget.cancelLabel),
            ),
            typed,
          ],
        ),
      );
    }

    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.shape.button),
      borderSide: BorderSide(color: tokens.color.ink),
    );
    final dialog = AlertDialog(
      // The title, the message and the field scroll above the keyboard, the
      // actions under them: at 200 % or in Bangla they are taller than the
      // room the keyboard leaves (#432). Cupertino's alert scrolls already.
      scrollable: true,
      title: SgText(widget.title, role: SgTextRole.title),
      // A field has no width of its own: without a bound the dialog would
      // cross a tablet. Material's dialogs keep to 560 dp.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The artboard's size and grey: the title says what, this how.
            SgText(
              widget.message,
              role: SgTextRole.label,
              weight: 400,
              color: tokens.color.textSecondary,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _typed,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: SgText.styleFor(tokens, SgTextRole.bodyLarge),
              decoration: InputDecoration(
                border: edge,
                enabledBorder: edge,
                focusedBorder: edge,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: cancel,
          style: TextButton.styleFrom(foregroundColor: tokens.color.link),
          child: SgChromeLabel(widget.cancelLabel, role: SgTextRole.label),
        ),
        typed,
      ],
    );
    return keyboardAware(dialog);
  }
}
