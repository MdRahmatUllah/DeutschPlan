import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// #462: tells Android the app has drawn what it opened on (Today with its
/// plan, or the first page of setup), so the cold start is timed to it, not
/// to the splash's first frame. The system logs it as "Fully drawn".
abstract final class StartReport {
  static const MethodChannel _channel = MethodChannel('deutschplan/start');

  static bool _reported = false;

  /// Once per run, after the frame that shows it. Nothing on iOS, which has
  /// no such report, and nothing when the channel isn't there.
  static void fullyDrawn() {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _channel.invokeMethod<void>('fullyDrawn');
      } on Object {
        // No report: the start is timed to the first frame, as before.
      }
    });
  }

  /// A test's fresh run.
  @visibleForTesting
  static void reset() => _reported = false;
}
