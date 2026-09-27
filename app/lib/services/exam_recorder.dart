import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:sogda/services/speech_audio.dart';

/// L12's Speaking recorder (`exam-writing-speaking.md`): the microphone, and
/// playing the answer back to tick the rubric.
///
/// An interface so the Speaking screen's states can be tested without a
/// microphone, as `NotificationPermission` is for S2.
abstract interface class ExamRecorder {
  /// FR-L12S-01: asks for the microphone if the phone hasn't been answered
  /// yet, and says whether it may record.
  Future<bool> permission();

  /// The phone's settings for the app, where a refused microphone is
  /// allowed again.
  Future<void> openSettings();

  /// FR-L12S-02: records to [path], AAC mono at 32 kbps, replacing what is
  /// there.
  Future<void> start(String path);

  /// Stops; the file at the path given to [start] is complete.
  Future<void> stop();

  /// The input level while recording, 0 (silence) to 1, a few times a second.
  Stream<double> get levels;

  /// True while a call, an alarm or a voice assistant has the microphone and
  /// the recording waits for it, false once it records again (#624).
  Stream<bool> get interrupted;

  /// Plays [path] once; completes when it ends or [stopPlaying] is called.
  Future<void> play(String path);

  Future<void> stopPlaying();

  /// How long the recording at [path] is; null when it can't be read.
  Future<Duration?> length(String path);

  Future<void> dispose();
}

/// [ExamRecorder] on the `record` and `just_audio` plugins.
class PlatformExamRecorder implements ExamRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  /// FR-L12S-02's encoding. A call, an alarm or a voice assistant that
  /// takes the microphone pauses the recording, and it goes on once they
  /// give it back (#624): `pause`, the default, never went on.
  static const RecordConfig config = RecordConfig(
    bitRate: 32000,
    numChannels: 1,
    audioInterruption: AudioInterruptionMode.pauseResume,
  );

  @override
  Future<bool> permission() => _recorder.hasPermission();

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  @override
  Future<void> start(String path) => _recorder.start(config, path: path);

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  /// dBFS runs from about −60 (silence) to 0 (the loudest the microphone
  /// takes); the bars want a fraction.
  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 250))
      .map((level) => ((level.current + 60) / 60).clamp(0.0, 1.0));

  @override
  Stream<bool> get interrupted =>
      _recorder.onStateChanged().map((state) => state == RecordState.pause);

  @override
  Future<void> play(String path) async {
    // A finished take leaves `playing` true, and `play` would return at once,
    // before asking for the focus: the replay under the learner's music, at
    // full volume (#623).
    await _player.stop();
    await _player.setFilePath(path);
    // Ducks the learner's music, and gives it back after (#623).
    await SpeechAudio.play(_player.play);
  }

  @override
  Future<void> stopPlaying() => _player.stop();

  @override
  Future<Duration?> length(String path) async {
    try {
      return await _player.setFilePath(path);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
