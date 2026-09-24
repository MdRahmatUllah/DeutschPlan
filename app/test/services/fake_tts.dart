import 'package:deutschplan/services/tts/tts_engine.dart';

/// A [TtsEngine] for tests: a phone with a German voice, or — [voice] false —
/// without one, that records what it was asked to say.
class FakeTts implements TtsEngine {
  FakeTts({this.voice = true, List<String>? spoken})
    : spoken = spoken ?? <String>[];

  /// Whether the phone has a German voice; a test may take it away.
  bool voice;

  /// Every text it was asked to say, in order.
  final List<String> spoken;

  /// The same, with the speed each was asked at.
  final List<(String, double)> said = <(String, double)>[];

  @override
  String get name => 'fake';

  @override
  Future<bool> isAvailable() async => voice;

  @override
  Future<bool> speak(String text, {double speed = 1}) async {
    spoken.add(text);
    said.add((text, speed));
    return voice;
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<TtsState> get state => const Stream<TtsState>.empty();
}
