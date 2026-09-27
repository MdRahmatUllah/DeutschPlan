import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// #623: the app's own sounds, Supertonic's clips and Speaking's playback,
/// share the phone's audio as the phone's voice does. A word ducks the
/// learner's music while it plays and gives it back after. just_audio's
/// default session is music with `AUDIOFOCUS_GAIN`, taken on every play and
/// never given back, so a one-second word paused Spotify for good.
// ponytail: `speech()` is iOS's playback category; Speaking's recorder sets
// its own. iOS is Later (v1 scope): check the two together there.
abstract final class SpeechAudio {
  /// Speech, ducking what else plays: what `flutter_tts` asks for too.
  static final AudioSessionConfiguration configuration =
      const AudioSessionConfiguration.speech().copyWith(
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
      );

  static Future<AudioSession>? _session;

  static final FocusRelease _focus = FocusRelease(() async {
    await (await _ready()).setActive(false);
  });

  static Future<AudioSession> _ready() => _session ??= () async {
    final session = await AudioSession.instance;
    await session.configure(configuration);
    return session;
  }();

  /// Runs [play], a just_audio `play()`, in the configured session, and
  /// gives the focus back once it, and any play started after it, has ended.
  /// Completes as [play]'s future does.
  static Future<void> play(Future<void> Function() play) async {
    await _ready();
    final ended = play();
    _focus.playing(ended);
    return ended;
  }
}

/// Gives the audio focus back once the last play it was told of has ended,
/// never under a play that started after (#623): the next card's word must
/// not lose the focus to the end of the one before it.
class FocusRelease {
  FocusRelease(this._release);

  final Future<void> Function() _release;
  int _plays = 0;

  /// A play has started; [ended] completes when it stops, however it stops.
  void playing(Future<void> ended) {
    final mine = ++_plays;
    unawaited(
      ended.catchError((Object _) {}).whenComplete(() {
        if (mine == _plays) unawaited(_release());
      }),
    );
  }
}
