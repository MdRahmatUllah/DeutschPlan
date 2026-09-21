# L2 · Step detail (Words · Grammar · Quiz · Exams)

**Purpose.** Everything in one step, on four inner tabs.

**Prototype.** `StepDetail` (Words), `StepGrammar` (Grammar), `QuizSetup` (Quiz tab + custom sheet), `ExamHub` / `ExamHubLocked` (Exams tab — documented in `exam-hub.md`).

**Reached from.** L1 tile, T1 step chip, T1 exam card (`?tab=exams`), M1 exam badge, M2 step row. **Leads to.** W1, L4, L15, L7/L8, L10/L11, T2, R1 (search icon, pre-filtered).

**Header.** "A2.1 · Grundstufe · 540 words · 10 grammar topics", segmented bar, "Started 19 Aug · about 51 days left at 7 words/day" (or "Completed 18 Aug · Mock 1 passed · revision continues"). Inner tab bar (Material `TabBar` / Cupertino segmented): Words · Grammar · Quiz · Exams. Top-right search icon → R1 with a removable step filter chip.

## Words tab
Filter chips All · To do · Learning · Done · {category}; rows: article + headword, meaning, status chip. If the step is not active: banner "You're in A1.2 — start A2.1 now?" with *Start* (FR-L2-03).

## Grammar tab
Button *Practise all due · 2* (→ L15 with all due topics). Numbered list: title, one-line rule preview ("konnte, musste, wollte — no umlaut, no ge-"), and "next practice in 4 d" / "due today" once learned. Tap → L4.

## Quiz tab
Tiles *Quick* (10) · *Standard* (20) · *Long* (30) · *Forms* ("Perfekt, 3rd person, plurals from this step") · *Custom* ("Direction, length, source, timer") → custom sheet. Last quiz card: "16 / 20 · Standard · DE → EN · Sun 20 Sep". Disabled with an explanation until ≥ 10 words of the step are learned.

**Custom quiz sheet** (bottom sheet): Direction DE → EN · DE → বাংলা · EN → DE · Articles · Listening · Mixed; Length 10 · 20 · 30; Source this step's learned words · all learned · {category}; Timer switch ("Off · 15 s per question when on"); *Start quiz · 20 questions*.

**Functional requirements**
- FR-L2-01 The header's "days left" = remaining To-do words ÷ daily_new × (7 ÷ study days).
- FR-L2-02 Filters combine (status AND category); list is virtualised.
- FR-L2-03 *Start* enrols the step (BR-COURSE-04): completes the current enrollment's `completed_on = today`, inserts the new one; today's plan is unchanged (BR-PLAN-08).
- FR-L2-04 Quiz tiles build `QuizArgs(source: stepLearned, …)` and push L8; *Forms* uses direction `forms`.
- FR-L2-05 Grammar rows show FSRS due from `grammar_state`.

**Tests.** FR-L2-01 maths; FR-L2-03 enrollment switch; goldens for each tab.
