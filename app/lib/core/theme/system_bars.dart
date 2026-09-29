import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The system bars, out of the way.
///
/// `SystemUiMode.edgeToEdge` lets the app draw into the status and navigation
/// bars, but Android still enforces a contrast scrim over them by default —
/// which puts a band two shades darker across the top of every coloured
/// header. Turning that off is the whole of this file.
///
/// It lives in `core/theme/` because it names colours, and that is the one
/// place allowed to.
const SystemUiOverlayStyle transparentSystemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

/// #1070: the status bar's icons over [fill]: dark on a light fill, light on
/// a dark one. Left to the last app bar's style, they stayed white on
/// Learn's yellow, T6's lime and S1's cyan in dark mode.
SystemUiOverlayStyle barsOver(Color fill) {
  final light = ThemeData.estimateBrightnessForColor(fill) == Brightness.light;
  return transparentSystemBars.copyWith(
    statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
    // iOS names the bar's background instead.
    statusBarBrightness: light ? Brightness.light : Brightness.dark,
  );
}

/// A coloured header drawn under the status bar: its fill, with the status
/// bar's icons set for it (#1070).
class SgHeaderFill extends StatelessWidget {
  const SgHeaderFill({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: barsOver(color),
    child: ColoredBox(color: color, child: child),
  );
}
