import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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
            child: SafeArea(top: false, bottom: bottomBar == null, child: body),
          ),
          if (bottomBar != null) SafeArea(top: false, child: bottomBar!),
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
        : DpText(title!, role: DpTextRole.title);

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
    // button's width.
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(child: titleWidget),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: back ?? const SizedBox.shrink(),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ],
      ),
    );
  }
}

/// The back affordance, in whichever treatment the platform draws.
///
/// Android is a chevron alone; iOS is a chevron with the 17 pt label the
/// artboards show. Both are 44 pt wide, which clears the minimum tap target.
class AdaptiveBackButton extends StatelessWidget {
  const AdaptiveBackButton({required this.onPressed, super.key, this.label});

  final VoidCallback onPressed;

  /// The iOS label. Android ignores it — Material back buttons carry no text.
  final String? label;

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
            foregroundColor: tokens.color.link,
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
                color: tokens.color.link,
              ),
              if (cupertinoChrome && label != null) ...<Widget>[
                const SizedBox(width: 2),
                DpText(
                  label!,
                  role: DpTextRole.bodyLarge,
                  color: tokens.color.link,
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

    Widget wrap(BuildContext sheetContext) => DpSurface(
      kind: DpSurfaceKind.cardStrong,
      radius: tokens.shape.sheet,
      child: SafeArea(top: false, child: builder(sheetContext)),
    );

    if (chrome == AdaptiveChrome.cupertino) {
      return cupertino.showCupertinoModalPopup<T>(
        context: context,
        builder: wrap,
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      // The sheet's own surface is the DpSurface inside; Material must not
      // paint one behind it, or the glass panel sits on a solid slab.
      // Fully transparent is the absence of a colour, not a token.
      backgroundColor: const Color(0x00000000), // ponytail: allow-raw-colour
      elevation: 0,
      builder: wrap,
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

/// The platform the app would pick with no override, for diagnostics.
AdaptiveChrome get defaultChrome =>
    AdaptiveChrome.forPlatform(defaultTargetPlatform);
