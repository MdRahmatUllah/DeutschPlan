import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// #462: tells Android the app has drawn what it opened on (Today with its
/// plan, or the first page of setup), so the cold start is timed to it, not
/// to the splash's first frame. The system logs it as "Fully drawn".
///
/// A cold start into another page (a reminder's or the widget's link)
/// reports once Today or setup is shown, if ever: `tools/perf.py` starts the
/// launcher's intent, which opens on one of them.
abstract final class StartReport {
  static const MethodChannel _channel = MethodChannel('deutschplan/start');

  static bool _reported = false;

  /// Once per run, after the frame that shows it. Android only: iOS has no
  /// such report.
  static void fullyDrawn() {
    if (_reported || defaultTargetPlatform != TargetPlatform.android) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _channel.invokeMethod<void>('fullyDrawn');
      } on MissingPluginException {
        // A test's binding, with no activity behind it.
      }
    });
  }

  /// A test's fresh run.
  @visibleForTesting
  static void reset() => _reported = false;
}
