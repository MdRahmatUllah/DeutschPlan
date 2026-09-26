import 'package:flutter/services.dart';

/// A tablet, by its shortest side: where W1 opens as a pane, and turning the
/// tablet keeps it one. Android 16 ignores an app's orientation lock from
/// 600 dp up, so the line is the platform's too.
const double tabletShortestSide = 600;

/// The owner's call on #577: a phone stays portrait, a tablet turns. Turned
/// sideways, a phone left 16 screens cut at 150 / 200 % text, and about
/// 150 dp above a keyboard. Empty is every orientation, the system's own.
List<DeviceOrientation> orientationsFor(Size screen) =>
    screen.shortestSide < tabletShortestSide
    ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
    : const <DeviceOrientation>[];

/// Asks for [orientationsFor] the screen once it has a size, and again each
/// time it crosses [tabletShortestSide]: a foldable opened or closed, a
/// tablet into or out of split screen.
class OrientationLock {
  bool? _tablet;

  /// [screen] in logical pixels. An empty one (the window before its first
  /// size, at start) is skipped: read as a phone, it locked tablets too.
  Future<void> update(Size screen) async {
    if (screen.isEmpty) return;
    final tablet = screen.shortestSide >= tabletShortestSide;
    if (tablet == _tablet) return;
    _tablet = tablet;
    await SystemChrome.setPreferredOrientations(orientationsFor(screen));
  }
}
