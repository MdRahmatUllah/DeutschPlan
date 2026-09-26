import 'dart:ui' show FlutterView, Size;

import 'package:flutter/services.dart';

/// A tablet, by its shortest side: where W1 opens as a pane, and turning the
/// tablet keeps it one.
const double tabletShortestSide = 600;

/// The owner's call on #577: a phone stays portrait, a tablet turns. Turned
/// sideways, a phone left 16 screens cut at 150 / 200 % text, and about
/// 150 dp above a keyboard. Empty is every orientation, the system's own.
List<DeviceOrientation> orientationsFor(Size screen) =>
    screen.shortestSide < tabletShortestSide
    ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
    : const <DeviceOrientation>[];

/// [orientationsFor] the [view]'s screen, set once at start: a phone doesn't
/// become a tablet.
Future<void> lockOrientation(FlutterView view) =>
    SystemChrome.setPreferredOrientations(
      orientationsFor(view.physicalSize / view.devicePixelRatio),
    );
