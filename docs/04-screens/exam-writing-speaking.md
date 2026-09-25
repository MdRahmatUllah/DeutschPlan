# L12 · Exam runner (2/2 — Writing and Speaking sections)

**Prototype.** `ExamWriting`, `ExamSpeaking`.

## Writing · 1 of 1
Prompt: "Write to your landlord about a broken heating. Use at least 6 of these words:" + 10 target-word chips (Heizung, Vermieter, kaputt, reparieren, kalt, seit, dringend, Wohnung, bitte, Termin); progress line "7 of 10 used · minimum 30 words at A1"; text area; live line "43 words · min 30 · Connectors found: seit, bitte"; *Submit text*; umlaut row pinned above the keyboard.

- FR-L12W-01 Target-word detection uses `searchKey` prefix matching on tokens (so "Heizung" matches "Heizungen"); chips turn Lime when used. A word of the text counts for one target at most, the most targets it can use once each (#388): "Beweise" is *Beweis* or *beweisen*, not both, and the same word twice is one word.
- FR-L12W-02 Minimum words per level: A1 30 · A2 60 · B1 100 · B2 150 · C1 200 · C2 250.
- FR-L12W-03 App points (2): ≥ 6 target words → 1; ≥ minimum length → 1. Rubric (2): task covered · structure — 0.5 each, ticked by the learner on the results review.
- FR-L12W-04 The text is stored in `exam_answers.given`; never leaves the device.

Details Writing settles (#133):
- The task is exam-generator.md's per level with the paper's category ("Write a short message to a friend about Wohnen."), then "Use at least 6 of these words:". The artboard's landlord letter is a sample of one. A step with no category writes about "your week".
- A chip is an outline until the text uses the word (FR-L12W-01's matching, as #84 grades it), then Lime with a tick; a screen reader hears "Heizung, used". Under them, "7 of 10 used · minimum 30 words at A1".
- Under the text, live: "43 words · min 30", and "Connectors found: seit, bitte" once there are any. A connector is found as a whole word, case aside; a two-word one ("ohne dass") only as the two together. Shown, not scored.
- The text is the runner's typed answer: written when the learner moves on, and with the clock every 10 s, so a crash loses at most 10 s of typing (FR-L12W-04). Only Writing is saved with the clock; any other typed answer still waits for a move, or a half-typed one would count as answered on resume.
- The keyboard's autocorrect and suggestions are off, as for the runner's other typed answers: in an exam the keyboard must not spell the German. The empty field's hint, "Write your text here, in German", is also what a screen reader hears on it.
- *Submit text* stands where *Next* is (on the last item, *Submit exam*). The runner's *Previous* and flag stay: the artboard's single button would leave no way back until the navigator (#131).

## Speaking · 1 of 1
Prompt "Describe your morning routine — 1 minute." + hint "Say what you do, when, and in what order. Use Perfekt or Präsens."; recorder with "00:52 / 01:00" ring; state line "Recorded · stays on this phone"; *Retake · 1 left* · *Delete recording*; "Listen back and tick what you managed": four rubric checkboxes (Task covered — the whole morning, in order · Fluency — few long pauses · Pronunciation — understandable throughout · Vocabulary — 6+ words from this step); "Self-assessed · counts 4 points"; *Submit exam*.

- FR-L12S-01 Mic permission requested on first use with rationale; denial shows a message and the section can be skipped (0 points) without blocking the exam.
- FR-L12S-02 Recording via `record` (AAC, mono, 32 kbps) to `<appSupport>/recordings/<attemptId>.m4a`; max length per level (60/90/120 s); one retake.
- FR-L12S-03 Rubric ticks → `self_rubric_json`; 1 point each.
- FR-L12S-04 *Delete recording* from here or from L13 removes the file and zeros the section.

Details Speaking settles (#134):
- The task is exam-generator.md's per level with the paper's category, then its length ("— 1 minute", "— 90 seconds"), and the hint "Speak in whole sentences. Then listen back and tick what you managed." The artboard's morning routine is a sample of one.
- Before recording, the round Coral button records, and the line under the time says why the phone will ask: "The first time, your phone asks for the microphone. The recording never leaves this phone." The permission is asked on the first tap (FR-L12S-01). Refused, the line says so, *Open settings* opens the phone's settings for the app, and *Next* moves on: nothing recorded scores 0.
- Recording: the button stops, the time counts up to the level's length, and at the length it stops by itself. Leaving the exam mid-recording stops it and keeps what was said.
- Recorded: the Lagoon button plays it back (and stops), "00:52 / 01:00", "Recorded · stays on this phone", the bars of the levels heard (even bars for a recording made before this visit), *Retake · 1 left* and *Delete recording*. A retake records over the same file. The retake left is counted in memory, so a resumed attempt offers it again.
- The recording is the row's `given` (the path); deleting it removes the file and clears `given`, which zeros the section as #84 grades it (FR-L12S-04). Each tick is written to `self_rubric_json` as it is ticked, and the ticks come back on resume (FR-L12S-03).
- The recorder is `ExamRecorder` (`services/exam_recorder.dart`): `record` for AAC mono at 32 kbps, `just_audio` to play back. `RECORD_AUDIO` and `NSMicrophoneUsageDescription` are declared for it.

**Tests.** FR-L12W-01 stem matching; FR-L12W-03 scoring; recorder state machine (fake recorder).
