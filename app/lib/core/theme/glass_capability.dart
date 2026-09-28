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

  static const MethodChannel _channel = MethodChannel('sogda/glass');

  /// The frame budget: one frame at 60 Hz. A frame slower than this is a
  /// dropped frame as far as the glass budget is concerned.
  static const Duration frameBudget = Duration(milliseconds: 16);

  /// How long the device must keep missing frames before glass gives up.
  static const Duration sustainedMissWindow = Duration(seconds: 2);

  /// A pause between two slow frames longer than this is the app sitting
  /// idle, not a device falling behind: about two vsyncs (#650).
  static const Duration idleGap = Duration(milliseconds: 32);

  bool _platformSupportsBlur;
  bool _reduceTransparency;
  bool _frameBudgetMissed = false;

  /// When the current run of slow frames began, and when its last one ended.
  Duration? _missingSince;
  Duration? _lastMissEnd;

  /// [startFrameWatchdog] was called and [stopFrameWatchdog] was not.
  bool _armed = false;

  /// Glass is the theme on screen ([glassOnScreen]).
  bool _onScreen = false;

  /// The timings callback is registered.
  bool _watching = false;

  /// True when a glass panel may use a `BackdropFilter`.
  ///
  /// Read by every [SgSurface] build, so it allocates nothing, unlike
  /// [reasons] (#698).
  bool get blurAllowed =>
      _platformSupportsBlur && !_reduceTransparency && !_frameBudgetMissed;

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
  /// Sogda look like it ignores an accessibility setting.
  Future<void> queryPlatform() async {
    _channel.setMethodCallHandler(_onPlatformPush);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      if (result == null) return;
      // A reply that is not a bool keeps the default rather than throwing: a
      // cast error here failed bootstrap at step "settings" (#698).
      if (result['supportsBlur'] case final bool value) {
        _platformSupportsBlur = value;
      }
      if (result['reduceTransparency'] case final bool value) {
        _reduceTransparency = value;
      }
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
  ///
  /// It watches only while [glassOnScreen] too (#650): frames drawn in light
  /// or dark say nothing about what the blur costs, and a few slow ones there
  /// used to leave a later switch to glass opaque until a restart.
  void startFrameWatchdog() {
    _armed = true;
    _syncWatching();
  }

  /// Stops it for good, whatever [glassOnScreen] says: `perf_test.dart` holds
  /// blur on for its glass runs.
  void stopFrameWatchdog() {
    _armed = false;
    _syncWatching();
  }

  /// Whether glass is the theme on screen, which the app sets from the theme
  /// (`watchGlassTheme` in `main.dart`, #650).
  set glassOnScreen(bool value) {
    _onScreen = value;
    _syncWatching();
  }

  /// Whether the timings callback is registered.
  @visibleForTesting
  bool get watchingFrames => _watching;

  void _syncWatching() {
    final watch = _armed && _onScreen && !_frameBudgetMissed;
    if (watch == _watching) return;
    _watching = watch;
    // A run of slow frames never spans a time the watchdog was not looking.
    _missingSince = null;
    _lastMissEnd = null;
    if (watch) {
      SchedulerBinding.instance.addTimingsCallback(_onFrames);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(_onFrames);
    }
  }

  @visibleForTesting
  void reportFrames(List<FrameTiming> timings) => _onFrames(timings);

  /// A frame misses when its build or its raster alone takes longer than
  /// [frameBudget]. Not its whole span, vsync to raster end: a pipelined
  /// frame at 60 fps builds one frame while the last one rasterises, so its
  /// span can pass 16 ms with every phase on time (#650).
  static bool _missed(FrameTiming timing) =>
      timing.buildDuration > frameBudget || timing.rasterDuration > frameBudget;

  void _onFrames(List<FrameTiming> timings) {
    if (_frameBudgetMissed) return;

    for (final timing in timings) {
      if (!_missed(timing)) {
        // One good frame ends the streak.
        _missingSince = null;
        continue;
      }

      final start = Duration(
        microseconds: timing.timestampInMicroseconds(FramePhase.vsyncStart),
      );
      final end = Duration(
        microseconds: timing.timestampInMicroseconds(FramePhase.rasterFinish),
      );
      // Two slow frames with the app idle between them are not a streak: the
      // time between them was not a frame missed (#650).
      if (_lastMissEnd case final last? when start - last > idleGap) {
        _missingSince = null;
      }
      _missingSince ??= start;
      _lastMissEnd = end;

      if (end - _missingSince! >= sustainedMissWindow) {
        _frameBudgetMissed = true;
        _syncWatching();
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

/// Makes a [GlassCapability] available to every [SgSurface] below it.
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
