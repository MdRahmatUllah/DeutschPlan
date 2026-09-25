# Text-to-speech

`services/tts/`. Interface `TtsEngine { name; isAvailable(); speak(text, {speed}); stop(); Stream<TtsState> state }`.

- **SupertonicTts** — Supertonic 3 (ONNX, ~99 M params, CPU) through `flutter_onnxruntime`. Model files downloaded by the Model manager to `<appSupport>/models/supertonic3/`; voices Anna / Jonas / Lena map to speaker embeddings. Synthesises to 16-bit PCM WAV in a background isolate, played with `just_audio`. Cache: last 200 synthesised strings on disk keyed by (text, voice, speed).
- **SystemTts** — `flutter_tts` with `de-DE`; fallback and the onboarding preview.
- **TtsService** chooses the engine from `tts_engine`, falls back to SystemTts on any failure (one-time toast), owns one player so two sounds never overlap, exposes `state` (idle / loading / playing) for the speaker button's three-bar animation. Loading indicator only if synthesis > 150 ms.
- Speed: `tts_speed` default 1.0; long-press = 0.75×.
- Auto-play: headword on card appear (`autoplay_headword`), first example on reveal (`autoplay_example`).

Details #153 settles:
- `TtsService` (`services/tts/tts_service.dart`) is `ttsProvider`. Supertonic reaches it through `supertonicVoiceProvider`, null until #152. It picks Supertonic when `tts_engine` is `supertonic` and falls back to SystemTts for that request when Supertonic is missing (null, or its model not ready: `speak` answers false) or fails (it throws). The half-started Supertonic is stopped first. Nothing is remembered, so the next request tries Supertonic again.
- One-time toast: "Supertonic isn't ready, so the phone voice is speaking.", with a *Settings* action that opens M3 (`jumpToTab`). It shows once per app session (the service is kept alive), the first time the phone voice really speaks in Supertonic's place. When the phone has no German voice either, the no-voice toast shows instead and the once isn't used up. A toast with an action stays 4 s, like Undo.
- One player: each request stops the engine the previous one used, then speaks. There is no queue.
- `state` is keyed by the text: `ttsPlayback` gives (text, idle / loading / playing), and the speaker saying that text shows playing (the three bars) or loading (the spinner); every other speaker stays idle. Loading runs from the request to the engine's first `playing` or `idle`. The spinner shows only once that has taken more than 150 ms. A `speak` that answers true also ends loading, so a voice that reports no states leaves no spinner behind. The three bars are the Foundations artboard's static bars ("idle → playing (3 bars)"); they don't move.
- Speed: the service reads `tts_speed` and multiplies it by the caller's pace. The long-press pace is 0.75, so it plays at 0.75 × `tts_speed` (1.25 → 0.9375).
- The long-press sits where it already was: T2's headword speaker, W1's and T5's. The exam and placement speakers leave it out on purpose, because they are tests. The quiz speakers leave it out too.
- Auto-play is T2's (`StudyWordCard`): the headword after the card's first frame, and the first example when the card turns over, each through the service. W1's `?speak=1` plays the word on open, whatever the settings say: it is the widget's "hear it", not auto-play. S2's preview stays on SystemTts.

