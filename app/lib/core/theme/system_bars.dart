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
