/// Speech, behind the small interface `project-structure.md` asks for so a
/// test can fake it.
///
/// #151 owns this seam and grows it — rate, availability on the speaker,
/// the slashed icon. It starts as what S2 page 5 needs: say one German phrase
/// with the system voice, and say whether that was possible.
abstract interface class TtsEngine {
  /// Speaks [text] in German at [rate] — 1 is normal, 0.75 is T2's slow
  /// long-press (FR-T2-09). False when there is no German voice to speak it
  /// with, so the caller can say so instead of staying silent.
  Future<bool> speak(String text, {double rate = 1});

  Future<void> stop();
}
