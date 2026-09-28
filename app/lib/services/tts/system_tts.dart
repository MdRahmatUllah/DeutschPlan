import 'dart:async';

import 'package:sogda/services/tts/tts_engine.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';

/// The phone's own German voice.
///
/// What S2 plays before any model exists — FR-S2 page 5's "Hear it" works on
/// a fresh install with nothing downloaded — and `TtsService`'s fallback
/// whenever Supertonic is missing or fails (#153).
class SystemTts implements TtsEngine {
  SystemTts([
    FlutterTts? tts,
    this._stuck = const Duration(seconds: 3),
    this._rebinding = const Duration(seconds: 10),
  ]) : _tts = tts ?? FlutterTts() {
    // The plugin calls back whichever FlutterTts registered last, so there is
    // one per app: `systemTtsProvider` keeps this alive.
    _tts
      ..setStartHandler(() => _emit(TtsState.playing))
      ..setCompletionHandler(() => _emit(TtsState.idle))
      ..setCancelHandler(() => _emit(TtsState.idle))
      ..setErrorHandler((_) => _emit(TtsState.idle));
  }

  final FlutterTts _tts;

  /// How long a speak may go unanswered before the engine counts as dead:
  /// a live one answers at once, the audio following on its own (#755).
  final Duration _stuck;

  /// How long a new binding may take: the engine's cold start was 2.9 s on
  /// the emulator (#755).
  final Duration _rebinding;

  final StreamController<TtsState> _state =
      StreamController<TtsState>.broadcast();

  /// `tts.md`: German is spoken as de-DE.
  static const String language = 'de-DE';

  @override
  String get name => 'system';

  @override
  Stream<TtsState> get state => _state.stream;

  /// German was there this session: a no after it is an engine that died
  /// (#755), not a phone without German.
  bool _hadGerman = false;

  @override
  Future<bool> isAvailable() async {
    if (await _german()) return _hadGerman = true;
    // #755: the phone's TTS engine died under the app (a memory kill, a Play
    // update), and every question reads "not bound": a new binding, once,
    // then the question again. Never on a phone that had no German.
    // Still no after it: the phone lost German, and the next question costs
    // no binding.
    if (!_hadGerman || !await _rebind()) return false;
    return _hadGerman = await _german();
  }

  Future<bool> _german() async {
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

  /// A new engine bound, the phone's default: the plugin creates it, and
  /// replays what it parked meanwhile, in the new engine's own language
  /// (#755). False when none comes up in [_rebinding].
  // ponytail: a dead engine costs a word up to 2 × [_rebinding] + 2 × _stuck
  // (26 s) before the no-voice state; a shorter bound once devices show
  // binding takes well under 10 s.
  Future<bool> _rebind() async {
    Future<bool> bind() async {
      final engine = await _tts.getDefaultEngine;
      if (engine is! String) return false;
      await _tts.setEngine(engine);
      return true;
    }

    try {
      // The engine asked for and bound, both under the one bound.
      return await bind().timeout(_rebinding);
    } on TimeoutException {
      return false;
    } on PlatformException {
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
      if (await _said(_tts.speak(text))) return true;
      // #755: the engine died after the question, or said yes unbound.
      // flutter_tts parks the speak until an engine starts, which none does,
      // so it never answers, or it says 0. A new binding replays it in the
      // new engine's default language: stopped, and German said again. No
      // engine back: the no-voice state (#452), not silence.
      if (!await _rebind()) return false;
      await _tts.stop();
      if (turn != _turn) return true;
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(speed / 2);
      return await _said(_tts.speak(text));
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether [speak] was taken: 1, and in time.
  Future<bool> _said(Future<dynamic> speak) async {
    try {
      return await speak.timeout(_stuck) == 1;
    } on TimeoutException {
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
