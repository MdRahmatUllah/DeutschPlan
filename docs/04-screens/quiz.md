# L7 · Quiz setup · L8 · Quiz runner · L9 · Quiz result

**Purpose.** Quick practice from learned words in any direction.

**Prototype.** `QuizSetup` (custom sheet), `QuizRunner` (EN→DE with *almost* feedback), `QuizResult`.

**Reached from.** L2 Quiz tab, L6 *Quiz*, W2 *Quiz these*, M1 quick-quiz tile. **Leads to.** L9 → L8 (*Retry mistakes*) or back to the opener.

## L8 Runner
Full-screen modal; top bar close · "Standard · DE → EN" · "7 / 20" · progress strip · optional 15 s timer. Item layouts: type the meaning (German word + play, text field); type the German (EN/BN prompt, text field + umlaut row); articles (three big coloured buttons der/die/das); multiple choice (4 tiles); listening (play button, text field); forms (prompt "Perfekt of …"). Feedback: ✓ Correct · ≈ Almost — watch the spelling: *der Mietvertrag* · Article: *die*, not *der* · ✗ with the correct answer; *Next*.

## L9 Result
Score "16 / 20", "80% · 4 min 12 s · Standard · DE → EN"; "Mistakes · 4 · re-asked once at the end" list ("die Kaution — you wrote: die Kausion", "der Vermieter — you wrote: die Vermieter · article"); buttons *Retry mistakes · 4*, *Add mistakes to revision*, *Done*. Result block colour: Lime ≥ 80 %, Sun 50–79 %, Coral < 50 %.

**Functional requirements**
- FR-L8-01 Quiz built by `QuizBuilder` with a seed stored in `quiz_attempts`.
- FR-L8-02 Every answer graded by `answer_check` and rated into FSRS (BR-FSRS-03, source `quiz`); answers persisted per item.
- FR-L8-03 Wrong items re-asked once at the end (BR-QUIZ-01); the re-ask result does not change the score.
- FR-L8-04 Close asks "Stop quiz? Your answers so far are saved to revision".
- FR-L8-05 Timer (when on) auto-submits an empty answer as wrong at 0.
- FR-L9-01 *Retry mistakes* builds a new quiz from the mistake uids; *Add mistakes to revision* sets their `due = tomorrow` explicitly.

**Tests.** FR-L8-02 rating mapping; FR-L8-03 re-ask queue; golden runner per item type.
