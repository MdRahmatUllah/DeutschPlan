# L2 · Step detail (Words · Grammar · Quiz · Exams)

**Purpose.** Everything in one step, on four inner tabs.

**Prototype.** `StepDetail` (Words), `StepGrammar` (Grammar), `QuizSetup` (Quiz tab + custom sheet), `ExamHub` / `ExamHubLocked` (Exams tab — documented in `exam-hub.md`).

**Reached from.** L1 tile, T1 step chip, T1 exam card (`?tab=exams`), M1 exam badge, M2 step row. **Leads to.** W1, L4, L15, L7/L8, L10/L11, T2, R1 (search icon, pre-filtered).

**Header.** "A2.1 · Grundstufe · 540 words · 10 grammar topics", segmented bar, "Started 19 Aug · about 51 days left at 7 words/day" (or "Completed 18 Aug · Mock 1 passed · revision continues"). Inner tab bar (Material `TabBar` / Cupertino segmented): Words · Grammar · Quiz · Exams. Top-right search icon → R1 with a removable step filter chip.

## Words tab
Filter chips All · To do · Learning · Done · {category}, kept across a trip to another inner tab and back (#702); rows: article + headword, meaning, status chip. If the step is not active: banner "You're in A1.2 — start A2.1 now?" with *Start* (FR-L2-03).

## Grammar tab
Button *Practise all due · 2* (→ L15 with all due topics). Numbered list: title, one-line rule preview ("konnte, musste, wollte — no umlaut, no ge-"), and "next practice in 4 d" / "due today" once learned. Tap → L4.

## Quiz tab
Tiles *Quick* (10) · *Standard* (20) · *Long* (30), in the learner's meaning direction as L7 starts (#667), · *Forms* ("Perfekt, 3rd person, plurals from this step") · *Custom* ("Direction, length, source, timer") → custom sheet. Last quiz card: "16 / 20 · Standard · DE → EN · Sun 20 Sep"; the score as L9 shows it, halves kept ("8.5 / 10"), coloured by the unrounded share, and dated by the local day it finished (#335). The badge's score shrinks to fit at large text sizes, and is in the UI language's digits, as the line beside it (#690 LQ-6). The kind is the length asked for, stored in `quiz_attempts.length`, not the questions a step could fill: a Standard quiz over 14 learned words still reads Standard (#690 LQ-7). Disabled with an explanation until ≥ 10 words of the step are learned.

**Custom quiz sheet** (bottom sheet): Direction DE → EN · DE → বাংলা · EN → DE · Articles · Listening · Mixed; Length 10 · 20 · 30; Source this step's learned words · all learned · {category}, the step's category with most of *this step's* words learned (on a tie, the step's biggest). The chip stays closed, dimmed and announced as disabled, until the chosen direction can ask 10 of the category's learned words, counted from any step as the quiz draws them (Articles counts only nouns). A caption says why: "{category} opens once 10 of its words are learned · 3 so far". A direction that closes it takes the source back to the step's words (#337); Timer switch ("Off · 15 s per question when on"); *Start quiz · 20 questions*.

**Functional requirements**
- FR-L2-01 The header's "days left" = remaining To-do words ÷ daily_new × (7 ÷ study days). A step whose enrollment ended reads "Completed {date}" once every word has been met (none To do), words still Learning included: the plan finished it; or "Completed {date} · Mock {n} passed" once its exam passed. One left with words still To do reads "Left on {date}", as *Start* on another step leaves it (FR-L2-03) (the owner, 2026-09-27 and 2026-09-28, #950, #1012).
- FR-L2-02 Filters combine (status AND category); list is virtualised. A note or a comparison has no status, so it is under *All* only (BR-CONTENT-04). Under Aurora Glass the word list is one frosted panel, as the glass artboards draw it: blur, sheen and top highlight, with the rows unfilled on it. That is one `BackdropFilter` for the list, never one per row. The panel ends at the last row, so a short list leaves the aurora clear below (#282). The *Start* banner and the chips scroll away before the words (a `NestedScrollView`): fixed over the list, at 200 % on a 731 dp phone they left it no room, none at all in Bangla (#815). Past 130 % the rows have no prototype, so only a list of 20 rows or fewer shrink-wraps; a longer one fills the screen either way (#690 LQ-12).
- FR-L2-03 *Start* enrols the step (BR-COURSE-04): completes the current enrollment's `completed_on = today`, inserts the new one; today's plan is unchanged (BR-PLAN-08).
- FR-L2-04 Quiz tiles build `QuizArgs(source: stepLearned, …)` and push L8; *Forms* uses direction `forms`. A second tap while the quiz is on its way pushes no second L8 and writes no second attempt (#690 LQ-15).
- FR-L2-05 Grammar rows show FSRS due from `grammar_state`.

**Tests.** FR-L2-01 maths; FR-L2-03 enrollment switch; goldens for each tab.
