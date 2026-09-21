# T2 · Study session (1/2 — structure and flow)

**Purpose.** The focused card-by-card loop: hear → think → reveal → rate.

**Prototype.** `StudyFront`, `StudyBack`, `StudyNew`, `StudyCloze` (states in `study-session-states.md`).

**Reached from.** T1 (button, ring, section cards), T4 (*Study all*, *Study this day*), L1 current-step *Study*, L2 *Start this step now*. **Leads to.** T3 on the last card; T6 if the day is complete; W1 via overflow; X returns to the opener.

**Presentation.** Full-screen modal (root navigator), tab bar hidden. Android: container transform from the tapped card; iOS: modal slide-up.

**Layout.**
1. Top bar: close X · block label "Revise · 4 / 10" · overflow ⋯ (auto-play toggle, speech speed, open word details, report a problem).
2. Segmented progress strip: one segment per block (Revise Lagoon, New Sun, Grammar Oat-tinted), filling per card.
3. Word card (`StudyCard`): 6 px gender bar; step chip; front = article + headword (display), caption "Nomen · die Rechnung, -en · /রেশনুং/", 56 dp speaker; hint "Hear it, think of the meaning, then reveal."; back = meanings (per `meaning_language`), examples with mini play, collocations (⟶), register (≈), interference tip callout if any.
4. Bottom action area (thumb zone): before reveal *Show meaning*; after reveal the rating bar Again 1 d · Hard 3 d · Good 8 d · Easy 21 d (intervals from FSRS preview). New words add *I know it* and *Skip → backlog* above the bar.

**Session queue.** Built once from the plan (`SessionArgs.blocks`): Revise items → New items → Grammar due (each grammar topic inserted as an `L15` practice set inline) . Position and per-card results are persisted in `studySession` notifier state and mirrored to the DB after each card, so backgrounding or a crash resumes at the same card.

**Functional requirements**
- FR-T2-01 Tapping the card or *Show meaning* MUST reveal; auto-play rules per `03-domain/tts.md`.
- FR-T2-02 Rating MUST write one transaction (plan engine `rate`) and advance; a 4 s snackbar *Undo* MUST revert it fully.
- FR-T2-03 *Skip → backlog* MUST leave the item open (BR-PLAN-06) and show "Moved {word} to the backlog · Undo".
- FR-T2-04 *I know it* MUST rate Easy (BR-STATUS-04).
- FR-T2-05 Interval previews MUST be computed with the card's current FSRS state on reveal.
- FR-T2-06 Between blocks a 1 s banner ("Neue Wörter · {category}") MUST play; block order is fixed.
- FR-T2-07 Closing MUST NOT prompt; progress is per card. Reopening from Today shows "Continue · n left".
- FR-T2-08 Optional swipe-to-rate (left Again, right Good) only when `swipe_to_rate = 1`.
- FR-T2-09 Long-press the headword copies it; long-press the speaker plays at 0.75×.
- FR-T2-10 Cloze cards replace the front for words with `card_mode = cloze` (see states doc).

**Business rules.** BR-FSRS-01/02/06, BR-PLAN-06, BR-STATUS-04.

**Motion.** Reveal: `AnimatedSize` + fade/slide 4 px (quick). Rate: Again slides left, others lift up; next card rises from 16 px below; haptic light (Again medium). Speaker morphs to three bars while playing. Glass: card is gender-tinted `cardStrong`; aurora shifts toward the gender colour.

**Data.** `studySessionProvider(args)`, `PlanRepository.rate/skip/markKnown`, `TtsService`.

**Developer notes.** Keep the queue in the notifier, not in widget state. Precompute the next card's audio while the current card is shown. The rating bar's intervals are pure (`Fsrs.review` × 4) — memoise per card.

**Tests.** FR-T2-02 undo restores `word_state` and deletes the log row; FR-T2-03 skip → backlog next day; FR-T2-05 interval preview equals scheduler; widget: reveal, rate, block banner; goldens front/back/new/cloze × 3 themes.
