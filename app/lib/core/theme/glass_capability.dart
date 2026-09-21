import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Why a glass panel is rendering opaque instead of frosted.
enum GlassFallbackReason {
  /// The platform will not blur: Android below API 31, or cross-window blur
  /// switched off system-wide (battery saver, developer options, low-end
  /// device). On those, a `BackdropFilter` costs the same and shows nothing.
  platformBlurUnavailable,

  /// The OS accessibility setting is on. Flutter surfaces no such flag —
  /// `MediaQueryData` has highContrast, invertColors, disableAnimations and
  /// boldText, but nothing for transparency — so it comes over a channel from
  /// `UIAccessibility.isReduceTransparencyEnabled` on iOS.
  reduceTransparency,

  /// The device missed the frame budget for two seconds straight.
  frameBudget,
}

/// Decides whether glass may actually blur.
///
/// `docs/01-architecture/theming.md`: "`GlassPanel` degrades to a 92 %-opaque
/// tinted surface when: Android API < 31, the device missed the frame budget
/// for 2 s, or the OS 'reduce transparency' setting is on."
///
/// All three are independent and individually settable, so a test can trigger
/// exactly one without faking a device.
class GlassCapability extends ChangeNotifier {
  // The fields are private and mutable, so an initializing formal would have to
  // be a private named parameter, which Dart does not allow.
  GlassCapability({
    bool platformSupportsBlur = true,
    bool reduceTransparency = false,
    // ignore: prefer_initializing_formals
  }) : _platformSupportsBlur = platformSupportsBlur,
       // ignore: prefer_initializing_formals
       _reduceTransparency = reduceTransparency;

  /// Everything blurs. For tests and for the glass goldens.
  factory GlassCapability.always() => GlassCapability();

  /// Nothing blurs, as on an Android 11 phone.
  factory GlassCapability.never() =>
      GlassCapability(platformSupportsBlur: false);

  static const MethodChannel _channel = MethodChannel('deutschplan/glass');

  /// The frame budget: one frame at 60 Hz. A frame slower than this is a
  /// dropped frame as far as the glass budget is concerned.
  static const Duration frameBudget = Duration(milliseconds: 16);

  /// How long the device must keep missing frames before glass gives up.
  static const Duration sustainedMissWindow = Duration(seconds: 2);

  bool _platformSupportsBlur;
  bool _reduceTransparency;
  bool _frameBudgetMissed = false;

  Duration? _missingSince;
  bool _watching = false;

  /// True when a glass panel may use a `BackdropFilter`.
  bool get blurAllowed => reasons.isEmpty;

  /// Every reason blur is currently off. Empty when glass renders fully.
  Set<GlassFallbackReason> get reasons => <GlassFallbackReason>{
    if (!_platformSupportsBlur) GlassFallbackReason.platformBlurUnavailable,
    if (_reduceTransparency) GlassFallbackReason.reduceTransparency,
    if (_frameBudgetMissed) GlassFallbackReason.frameBudget,
  };

  /// Starts listening for platform pushes and reads the current values.
  ///
  /// Both flags change while the app runs — battery saver flips Android's
  /// cross-window blur, and the learner can turn Reduce Transparency on from
  /// Settings without leaving the app — so a one-shot read at launch would make
  /// DeutschPlan look like it ignores an accessibility setting.
  Future<void> queryPlatform() async {
    _channel.setMethodCallHandler(_onPlatformPush);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      if (result == null) return;
      _platformSupportsBlur = result['supportsBlur'] as bool? ?? true;
      _reduceTransparency = result['reduceTransparency'] as bool? ?? false;
      notifyListeners();
    } on MissingPluginException {
      // No native side (tests, an unsupported platform): keep the defaults.
    } on PlatformException catch (_) {
      // Treat a failure to answer as "blur is fine"; a wrongly-opaque app is a
      // worse outcome than a blur that costs a little on an odd device.
    }
  }

  Future<dynamic> _onPlatformPush(MethodCall call) async {
    if (call.method != 'capabilitiesChanged') return null;
    final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
    if (arguments == null) return null;

    var changed = false;
    if (arguments['supportsBlur'] case final bool value
        when value != _platformSupportsBlur) {
      _platformSupportsBlur = value;
      changed = true;
    }
    if (arguments['reduceTransparency'] case final bool value
        when value != _reduceTransparency) {
      _reduceTransparency = value;
      changed = true;
    }
    if (changed) notifyListeners();
    return null;
  }

  /// Watches real frame timings and gives up on blur after
  /// [sustainedMissWindow] of continuous misses.
  ///
  /// Once tripped it stays tripped for the session: flickering between frosted
  /// and opaque as the device recovers would be worse than either state.
  void startFrameWatchdog() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrames);
  }

  void stopFrameWatchdog() {
    if (!_watching) return;
    _watching = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrames);
  }

  @visibleForTesting
  void reportFrames(List<FrameTiming> timings) => _onFrames(timings);

  void _onFrames(List<FrameTiming> timings) {
    if (_frameBudgetMissed) return;

    for (final timing in timings) {
      final total = timing.totalSpan;
      if (total <= frameBudget) {
        // One good frame ends the streak.
        _missingSince = null;
        continue;
      }

      final stamp = timing.timestampInMicroseconds(FramePhase.rasterFinish);
      final now = Duration(microseconds: stamp);
      _missingSince ??= now;

      if (now - _missingSince! >= sustainedMissWindow) {
        _frameBudgetMissed = true;
        _missingSince = null;
        stopFrameWatchdog();
        notifyListeners();
        return;
      }
    }
  }

  @visibleForTesting
  void setReduceTransparency({required bool value}) {
    if (_reduceTransparency == value) return;
    _reduceTransparency = value;
    notifyListeners();
  }

  @visibleForTesting
  void setPlatformSupportsBlur({required bool value}) {
    if (_platformSupportsBlur == value) return;
    _platformSupportsBlur = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stopFrameWatchdog();
    super.dispose();
  }
}

/// Makes a [GlassCapability] available to every [DpSurface] below it.
///
/// Absent, glass blurs — so a screen rendered in a test or a golden is frosted
/// unless it deliberately says otherwise.
class GlassCapabilityScope extends InheritedNotifier<GlassCapability> {
  const GlassCapabilityScope({
    required GlassCapability super.notifier,
    required super.child,
    super.key,
  });

  static GlassCapability? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassCapabilityScope>()
      ?.notifier;

  /// Whether a glass panel in this subtree may blur.
  static bool blurAllowed(BuildContext context) =>
      maybeOf(context)?.blurAllowed ?? true;
}
