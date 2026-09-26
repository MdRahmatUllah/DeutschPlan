import 'dart:async';

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:deutschplan/services/tts/tts_service.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A widget test's voice: the real `TtsService` with [tts] as the learner's
/// chosen engine — Supertonic, `tts_engine`'s default — so a speaker speaks
/// without the fallback and its one-time toast, which `tts_service_test.dart`
/// and `speak_test.dart` cover. The phone's voice behind it has none, so with
/// [FakeTts.voice] false nothing can speak; a test has no plugin to ask.
Override fakeVoice(FakeTts tts) => ttsProvider.overrideWith((ref) {
  final service = TtsService(
    FakeTts(voice: false),
    ref.watch(settingsProvider),
    supertonic: tts,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// A [FakeTts] that makes its clips ahead (#430): Supertonic's
/// [SpeechPrefetch], recording each list it is given.
class FakePrefetchTts extends FakeTts implements SpeechPrefetch {
  final List<List<String>> prepared = <List<String>>[];

  /// The speed each list was asked at.
  final List<double> speeds = <double>[];

  /// Every list a screen stopped, in order.
  final List<List<String>> stopped = <List<String>>[];

  /// The list being made: the last one prepared, until it is stopped.
  List<String>? current;

  @override
  Future<void> prepare(List<String> texts, {double speed = 1}) async {
    prepared.add(texts);
    speeds.add(speed);
    current = texts;
  }

  /// How many times the sessions were asked to open ahead.
  int warms = 0;

  @override
  Future<void> warm() async => warms++;

  @override
  Future<void> stopPreparing(List<String> texts) async {
    stopped.add(texts);
    if (identical(texts, current)) current = null;
  }
}

/// A [TtsEngine] for tests: a phone with a German voice, or — [voice] false —
/// without one, that records what it was asked to say.
///
/// It reports no states unless it [holds]: then a speak reports `playing` and
/// stays there until [finish] or a stop, as a real voice does while it talks.
class FakeTts implements TtsEngine {
  FakeTts({this.voice = true, List<String>? spoken, this.holds = false})
    : spoken = spoken ?? <String>[];

  /// Whether the phone has a German voice; a test may take it away.
  bool voice;

  /// Whether a speak plays until [finish] (and reports it) or ends at once.
  final bool holds;

  /// Thrown by [speak] in place of an answer: an engine that breaks.
  Object? error;

  /// A speak answers only once this completes: a voice still synthesising.
  Completer<void>? synthesis;

  /// Every text it was asked to say, in order.
  final List<String> spoken;

  /// The same, with the speed each was asked at.
  final List<(String, double)> said = <(String, double)>[];

  /// Every speak and stop, in order: `speak Hallo`, `stop`.
  final List<String> log = <String>[];

  final StreamController<TtsState> _state =
      StreamController<TtsState>.broadcast(sync: true);

  @override
  String get name => 'fake';

  /// How often it was asked whether it can speak.
  int availabilityChecks = 0;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return voice;
  }

  @override
  Future<bool> speak(String text, {double speed = 1}) async {
    spoken.add(text);
    said.add((text, speed));
    log.add('speak $text');
    await synthesis?.future;
    final error = this.error;
    if (error != null) throw error;
    if (voice && holds) _state.add(TtsState.playing);
    return voice;
  }

  /// The utterance ends.
  void finish() => _state.add(TtsState.idle);

  @override
  Future<void> stop() async {
    log.add('stop');
    if (holds) _state.add(TtsState.idle);
  }

  @override
  Stream<TtsState> get state => _state.stream;
}
