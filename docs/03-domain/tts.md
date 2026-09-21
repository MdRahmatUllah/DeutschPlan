# Text-to-speech

`services/tts/`. Interface `TtsEngine { name; isAvailable(); speak(text, {speed}); stop(); Stream<TtsState> state }`.

- **SupertonicTts** — Supertonic 3 (ONNX, ~99 M params, CPU) through `flutter_onnxruntime`. Model files downloaded by the Model manager to `<appSupport>/models/supertonic3/`; voices Anna / Jonas / Lena map to speaker embeddings. Synthesises to 16-bit PCM WAV in a background isolate, played with `just_audio`. Cache: last 200 synthesised strings on disk keyed by (text, voice, speed).
- **SystemTts** — `flutter_tts` with `de-DE`; fallback and the onboarding preview.
- **TtsService** chooses the engine from `tts_engine`, falls back to SystemTts on any failure (one-time toast), owns one player so two sounds never overlap, exposes `state` (idle / loading / playing) for the speaker button's three-bar animation. Loading indicator only if synthesis > 150 ms.
- Speed: `tts_speed` default 1.0; long-press = 0.75×.
- Auto-play: headword on card appear (`autoplay_headword`), first example on reveal (`autoplay_example`).
