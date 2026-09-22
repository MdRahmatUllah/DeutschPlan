import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_tts/flutter_tts.dart';

/// The phone's own German voice.
///
/// What S2 plays before any model exists — FR-S2 page 5's "Hear it" works on
/// a fresh install with nothing downloaded.
class SystemTts implements TtsEngine {
  SystemTts([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// `tts.md`: German is spoken as de-DE.
  static const String language = 'de-DE';

  @override
  Future<bool> speak(String text) async {
    try {
      // `isLanguageAvailable` answers `true`, `false` or — on some engines —
      // an int. Only a plain yes is a yes: "maybe" is how a learner ends up
      // tapping a speaker that says nothing.
      if (await _tts.isLanguageAvailable(language) != true) return false;
      await _tts.setLanguage(language);
      await _tts.speak(text);
      return true;
    } on PlatformException {
      // An engine that failed to bind throws rather than answering. The
      // contract is false for "cannot speak German", so the caller can say so.
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() => _tts.stop();
}
