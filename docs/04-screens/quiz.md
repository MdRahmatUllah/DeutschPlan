# L7 · Quiz setup · L8 · Quiz runner · L9 · Quiz result

**Purpose.** Quick practice from learned words in any direction.

**Prototype.** `QuizSetup` (custom sheet), `QuizRunner` (EN→DE with *almost* feedback), `QuizResult`.

**Reached from.** L2 Quiz tab, L6 *Quiz*, W2 *Quiz these*, M1 quick-quiz tile. **Leads to.** L9 → L8 (*Retry mistakes*) or back to the opener.

## L7 Setup

The direction starts on the learner's meaning language: DE → বাংলা for `meaning_language = bn`, DE → EN otherwise (#387).

## L8 Runner
Full-screen modal; top bar close · "Standard · DE → EN" · "7 / 20" · progress strip · optional 15 s timer. Item layouts: type the meaning (German word + play, text field); type the German (EN/BN prompt, text field + umlaut row); articles (three big coloured buttons der/die/das); multiple choice (4 tiles); listening (play button, text field); forms (prompt "Perfekt of …"). Feedback: ✓ Correct · ≈ Almost — watch the spelling: *der Mietvertrag* · Article: *die*, not *der* · ✗ with the correct answer; *Next*.

**Typing at large text** (#554): past 130 % with the keyboard up, the room above it is a few lines, and the field alone filled it. The header gives up its row (close, the title and "7 / 20"; its colour stays behind the status bar) and the "YOUR ANSWER" caption goes, the field's hint saying as much. The prompt's gap to the field closes from 20 to 8 dp and the list's foot from 16 to 8, so a two-line prompt (one that wraps, or a meaning with its Bangla under it) shows whole on a 731 dp phone (#561). On a German answer *Check* is then a key at the end of the umlaut row (a tick on the primary, named *Check* for a screen reader, 48 dp so the four keys keep theirs), not a row of its own: in Bangla, whose copy is a role larger, its row left a Forms prompt 45 dp under the strip (#568). The prompt then shows above the field, with the umlaut row and *Check*. Both come back when the keyboard goes; back still asks (FR-L8-04). At 100 % nothing changes.

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
