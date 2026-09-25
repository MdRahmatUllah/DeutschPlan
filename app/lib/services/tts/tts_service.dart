import 'dart:async';

import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/foundation.dart' show immutable;

/// What the one player is doing, and for which text: the speaker that says
/// [text] shows [state], and every other speaker is idle.
@immutable
class TtsPlayback {
  const TtsPlayback(this.text, this.state);

  static const TtsPlayback idle = TtsPlayback('', TtsState.idle);

  final String text;
  final TtsState state;
}

/// What a [TtsService.speak] came to.
enum TtsOutcome {
  /// Said — by the chosen voice, or by the phone's once the learner has been
  /// told — or replaced by a newer request: nothing to report.
  spoke,

  /// Said by the phone's voice in place of Supertonic, the first time this
  /// session: the caller shows the one-time toast with its Settings link
  /// (accessibility-performance.md, "Supertonic missing/fails").
  fellBack,

  /// Nothing was said: no voice could speak German.
  silent,
}

/// Every speaker's voice (`tts.md`, #153).
///
/// It picks the engine from `tts_engine`, and falls back to the phone's voice
/// for the request when Supertonic is missing — no engine yet (#152), or its
/// model not installed — or fails in any way, false or thrown. It owns one
/// player: a request stops the one before it, then speaks. [playback] says
/// what is sounding, so a speaker knows whether it is the one playing.
class TtsService {
  TtsService(this._system, this._settings, {this._supertonic});

  final TtsEngine _system;
  final TtsEngine? _supertonic;
  final SettingsRepository _settings;

  /// `tts.md`: the loading indicator shows only once synthesis has taken
  /// longer than this; a quicker voice goes straight from idle to playing.
  static const Duration loadingAfter = Duration(milliseconds: 150);

  /// Sync, so a speaker's look changes with the request that changed it.
  final StreamController<TtsPlayback> _playback =
      StreamController<TtsPlayback>.broadcast(sync: true);
  TtsPlayback _now = TtsPlayback.idle;

  /// The engine the latest request went to, which the next one stops.
  TtsEngine? _engine;
  StreamSubscription<TtsState>? _events;
  Timer? _loading;

  /// Bumped by every request, so a request a newer one replaced lets go.
  int _request = 0;

  /// The fallback toast is once per app session: this service is kept alive.
  bool _told = false;

  /// Each change of what is sounding.
  Stream<TtsPlayback> get playback => _playback.stream;

  bool get _wantsSupertonic =>
      _settings.read(SettingKeys.ttsEngine) == TtsEngineSetting.supertonic;

  /// Whether any voice can speak German now: the chosen one or, behind it,
  /// the phone's. False slashes the speakers (accessibility-performance.md).
  Future<bool> isAvailable() async {
    final supertonic = _supertonic;
    if (_wantsSupertonic &&
        supertonic != null &&
        await _answer(supertonic.isAvailable)) {
      return true;
    }
    return _answer(_system.isAvailable);
  }

  /// Says [text] at `tts_speed` × [pace] — 0.75 on a speaker's long-press
  /// (FR-T2-09) — after stopping whatever was sounding.
  Future<TtsOutcome> speak(String text, {double pace = 1}) async {
    final request = ++_request;
    await _halt();
    if (request != _request) return TtsOutcome.spoke;

    final speed = _settings.read(SettingKeys.ttsSpeed) * pace;
    _loading = Timer(
      loadingAfter,
      () => _show(TtsPlayback(text, TtsState.loading)),
    );

    var fellBack = false;
    if (_wantsSupertonic) {
      final supertonic = _supertonic;
      if (supertonic != null) {
        if (await _try(supertonic, text, speed, request)) {
          return TtsOutcome.spoke;
        }
        // A newer request owns the player now, Supertonic included.
        if (request != _request) return TtsOutcome.spoke;
        // Whatever it may have started, it does not finish over the phone.
        await _quietly(supertonic.stop);
      }
      if (request != _request) return TtsOutcome.spoke;
      fellBack = true;
    }

    if (await _try(_system, text, speed, request)) {
      if (!fellBack || _told) return TtsOutcome.spoke;
      _told = true;
      return TtsOutcome.fellBack;
    }
    if (request != _request) return TtsOutcome.spoke;
    _loading?.cancel();
    _show(TtsPlayback.idle);
    return TtsOutcome.silent;
  }

  /// [engine] says [text]; false when it cannot, whichever way it fails.
  Future<bool> _try(
    TtsEngine engine,
    String text,
    double speed,
    int request,
  ) async {
    _unlisten();
    _engine = engine;
    _events = engine.state.listen((state) {
      if (request != _request) return;
      // An engine's own `loading` is the timer's to show, after 150 ms.
      if (state == TtsState.loading) return;
      _loading?.cancel();
      _show(
        state == TtsState.playing ? TtsPlayback(text, state) : TtsPlayback.idle,
      );
    });
    final bool spoke;
    try {
      spoke = await engine.speak(text, speed: speed);
    } on Object {
      return false;
    }
    // A voice that has said it is speaking has stopped synthesising, whether
    // or not it reports its states: the spinner never outlives the request.
    if (spoke && request == _request) {
      _loading?.cancel();
      if (_now.state == TtsState.loading) _show(TtsPlayback.idle);
    }
    return spoke;
  }

  /// One player: the sound before a request stops before it speaks.
  Future<void> _halt() async {
    _loading?.cancel();
    _unlisten();
    final engine = _engine;
    if (engine != null) await _quietly(engine.stop);
    _show(TtsPlayback.idle);
  }

  void _show(TtsPlayback playback) {
    if (identical(playback, _now) || _playback.isClosed) return;
    _now = playback;
    _playback.add(playback);
  }

  /// Not awaited: a subscription hears nothing more from the moment it is
  /// cancelled, and a broadcast one's cancel future belongs to the root zone,
  /// which a test's fake clock never runs.
  void _unlisten() {
    final events = _events;
    _events = null;
    if (events != null) unawaited(events.cancel());
  }

  void dispose() {
    _loading?.cancel();
    _unlisten();
    unawaited(_playback.close());
  }
}

/// An engine's yes or no, where a throw is a no.
Future<bool> _answer(Future<bool> Function() ask) async {
  try {
    return await ask();
  } on Object {
    return false;
  }
}

/// A stop that fails leaves nothing to stop: the next sound goes ahead.
Future<void> _quietly(Future<void> Function() stop) async {
  try {
    await stop();
  } on Object {
    // Nothing to do: see above.
  }
}
