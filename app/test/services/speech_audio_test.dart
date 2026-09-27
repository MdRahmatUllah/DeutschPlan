import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/services/speech_audio.dart';

/// #623: a word ducks the learner's music and gives it back.
void main() {
  test('#623 the session is speech that ducks, as the phone voice asks', () {
    expect(
      SpeechAudio.configuration.androidAudioFocusGainType,
      AndroidAudioFocusGainType.gainTransientMayDuck,
    );
    expect(
      SpeechAudio.configuration.androidAudioAttributes?.contentType,
      AndroidAudioContentType.speech,
    );
  });

  test('#623 both players play through it', () {
    // The plugin players themselves run on a device only (the device check);
    // this pins that they go through the session.
    for (final path in <String>[
      'lib/services/tts/supertonic_tts.dart',
      'lib/services/exam_recorder.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('SpeechAudio.play('),
        reason: path,
      );
    }
  });

  test("#623 Speaking's replay stops the finished take before it loads the "
      'next, or play returns before asking for the focus', () {
    final recorder = File('lib/services/exam_recorder.dart').readAsStringSync();
    expect(
      RegExp(r'await _player\.stop\(\);\s*await _player\.setFilePath')
          .hasMatch(recorder),
      isTrue,
    );
  });

  test('#623 a session that fails to configure: the word plays all the '
      'same, and the next play asks again', () async {
    final original = SpeechAudio.open;
    addTearDown(() => SpeechAudio.open = original);
    var opens = 0;
    SpeechAudio.open = () async {
      opens++;
      throw StateError('setCategory refused');
    };

    var played = 0;
    await SpeechAudio.play(() async => played++);
    await SpeechAudio.play(() async => played++);
    await pumpEventQueue();

    expect(played, 2);
    expect(opens, greaterThanOrEqualTo(2), reason: 'no failure kept');
  });

  test('#623 on iOS it ducks others and lets them back', () {
    expect(
      SpeechAudio.configuration.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.duckOthers,
    );
  });

  test("#623 a give-back that fails is no error of the play's", () async {
    final focus = FocusRelease(() async => throw StateError('no session'));
    final play = Completer<void>();
    focus.playing(play.future);
    play.complete();
    await pumpEventQueue();
  });

  group('#623 FocusRelease', () {
    late int released;
    late FocusRelease focus;

    setUp(() {
      released = 0;
      focus = FocusRelease(() async => released++);
    });

    test('gives the focus back when a play ends', () async {
      final play = Completer<void>();
      focus.playing(play.future);
      await pumpEventQueue();
      expect(released, 0, reason: 'not while it plays');

      play.complete();
      await pumpEventQueue();
      expect(released, 1);
    });

    test('not when an older play ends under a newer one', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      focus
        ..playing(first.future)
        ..playing(second.future);

      first.complete();
      await pumpEventQueue();
      expect(released, 0, reason: "the next card's word still plays");

      second.complete();
      await pumpEventQueue();
      expect(released, 1);
    });

    test('a play that fails gives it back too', () async {
      final play = Completer<void>();
      focus.playing(play.future);
      play.completeError(StateError('no such file'));
      await pumpEventQueue();
      expect(released, 1);
    });
  });
}
