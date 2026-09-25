import 'dart:async';

import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';

/// The phone's own German voice.
///
/// What S2 plays before any model exists — FR-S2 page 5's "Hear it" works on
/// a fresh install with nothing downloaded — and `TtsService`'s fallback
/// whenever Supertonic is missing or fails (#153).
class SystemTts implements TtsEngine {
  SystemTts([FlutterTts? tts]) : _tts = tts ?? FlutterTts() {
    // The plugin calls back whichever FlutterTts registered last, so there is
    // one per app: `systemTtsProvider` keeps this alive.
    _tts
      ..setStartHandler(() => _emit(TtsState.playing))
      ..setCompletionHandler(() => _emit(TtsState.idle))
      ..setCancelHandler(() => _emit(TtsState.idle))
      ..setErrorHandler((_) => _emit(TtsState.idle));
  }

  final FlutterTts _tts;
  final StreamController<TtsState> _state =
      StreamController<TtsState>.broadcast();

  /// `tts.md`: German is spoken as de-DE.
  static const String language = 'de-DE';

  @override
  String get name => 'system';

  @override
  Stream<TtsState> get state => _state.stream;

  @override
  Future<bool> isAvailable() async {
    try {
      // `isLanguageAvailable` answers `true`, `false` or — on some engines —
      // an int. Only `true` is a yes.
      return await _tts.isLanguageAvailable(language) == true;
    } on PlatformException {
      // An engine that failed to bind throws rather than answering. The
      // contract is false for "cannot speak German", so the caller can say so.
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Bumped by [stop]: a speak that a stop overtook while it was setting up
  /// the voice says nothing, or it would queue behind the next (iOS).
  int _turn = 0;

  @override
  Future<bool> speak(String text, {double speed = 1}) async {
    final turn = _turn;
    if (!await isAvailable()) return false;
    try {
      await _tts.setLanguage(language);
      // flutter_tts reads 0.5 as the normal rate on both platforms — its
      // Android side doubles what it is given — so 1 here is 0.5 there.
      await _tts.setSpeechRate(speed / 2);
      // Stopped, not failed: true, so nothing falls back or says "no voice".
      if (turn != _turn) return true;
      await _tts.speak(text);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _turn++;
    await _tts.stop();
    _emit(TtsState.idle);
  }

  /// The platform can call back after [dispose] — an utterance finishing as
  /// its container goes — and a closed stream would throw.
  void _emit(TtsState state) {
    if (!_state.isClosed) _state.add(state);
  }

  Future<void> dispose() => _state.close();
}
