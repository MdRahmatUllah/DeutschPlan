/// What an engine is doing, for the speaker's three bars (`tts.md`): loading
/// only while a model synthesises, playing while sound is out.
enum TtsState { idle, loading, playing }

/// Speech, behind the small interface `project-structure.md` asks for so a
/// test can fake it: `tts.md`'s name, isAvailable, speak, stop and state.
///
/// Every speaker but S2's preview reaches one through `ttsProvider`'s
/// `TtsService`, which chooses between engines and falls back (#153).
abstract interface class TtsEngine {
  /// The engine's `tts_engine` setting value: `system` or `supertonic`.
  String get name;

  /// Whether this engine can speak German on this phone now. Only a plain yes
  /// is a yes: "maybe" is how a learner ends up tapping a speaker that says
  /// nothing.
  Future<bool> isAvailable();

  /// Speaks [text] in German at [speed] — 1 is normal, 0.75 is the slow
  /// long-press (FR-T2-09). False when there is no German voice to speak it
  /// with, so the caller can say so instead of staying silent.
  Future<bool> speak(String text, {double speed = 1});

  Future<void> stop();

  /// Each change of [TtsState]: `playing` as sound starts, `idle` as it ends
  /// or stops. Nothing is emitted until the engine is used. `TtsService`
  /// drives the speakers from it; a [speak] that resolves true ends a loading
  /// the engine never reported the end of.
  Stream<TtsState> get state;
}
