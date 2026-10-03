# T2 · Study session (1/2 — structure and flow)

**Purpose.** The focused card-by-card loop: hear → think → reveal → rate.

**Prototype.** `StudyFront`, `StudyBack`, `StudyNew`, `StudyCloze` (states in `study-session-states.md`).

**Reached from.** T1 (button, ring, section cards), T4 (*Study all*, *Study this day*), L1 current-step *Study*, L2 *Start this step now*, T3 (the day's next block, #328). **Leads to.** T3 on the last card; T6 if the day is complete; W1 via overflow; X returns to the opener.

**Presentation.** Full-screen modal (root navigator), tab bar hidden. Android: container transform from the tapped card; iOS: modal slide-up.

**Layout.**
1. Top bar: close X · block label "Revise · 4 / 10" · overflow ⋯ (auto-play toggle, speech speed, open word details, report a problem).
2. Segmented progress strip: one segment per block (Revise Lagoon, New Sun, Grammar Slate), filling per card over `surface.track` (#437).
3. Word card (`StudyCard`): 6 px gender bar; step chip; front = article + headword (display), caption "Nomen · die Rechnung, -en · /রেশনুং/" (the pronunciation guide (`/…/`) is the first meaning language's, or the second's where the first has none (#1081); the Bangla one shows only while Bangla is a meaning language and *Show Bangla pronunciation* is on; with no Bangla chosen it never shows, however the language was set, and a change in M3 reaches the screen at once (#1077)), 56 dp speaker; hint "Hear it, think of the meaning, then reveal."; back = the pronunciation key's line, when the front's guide has a key (#1122, as W1: a sheet with the key; the ⓘ alone once a key has been opened), then meanings (the first meaning language's, the second's under it, #1081), with an *Updated* chip over them for a meaning a course update changed in the last 7 days (BR-CONTENT-02, #451; the chip W1's header wears), examples with mini play, then *Where you saw it* with the learner's newest own sentence for the word, from a document they read (`word_contexts`, #1232: play, and the document's title under it while that document is kept), collocations (⟶), register (≈), interference tip callout if any. The cloze card (FR-T2-10) has no *Updated* chip: once checked it shows the word in its gap and the rating bar, not the meanings.
4. Bottom action area (thumb zone): before reveal *Show meaning*; after reveal the rating bar Again 1 d · Hard 3 d · Good 8 d · Easy 21 d (intervals from FSRS preview); at large text, when a label is wider than a quarter of the row, two rows of two, Again · Hard over Good · Easy, rather than a label broken (#1155). The header's counter ("Revise · 4 / 10") is joined by no-break spaces, so it never wraps inside "4 / 10" (#1155). New words add *I know it* and *Skip → backlog* above the bar.

**Session queue.** Built once from the plan (`SessionArgs.blocks`): Revise items → New items → Grammar due. The grammar topics are not cards: once the words are done, L15 practises them on its own screen, in the session's place. Position and per-card results are persisted in `studySession` notifier state and mirrored to the DB after each card, so backgrounding or a crash resumes at the same card.

A word of the learner's own (`custom:<id>`, #363) comes as a revision like any word. Its chip says *My word* instead of a step, its back shows the meaning and its own example, and *open word details* opens R2 on it (`add-word.md`).

A word suspended mid-session (W1 opened from the overflow) stays in the queue it was built with. Rating it keeps it suspended (BR-STATUS-03). In a Revise block it completes no plan row, because the suspend dropped today's revision (#351). In a New block its row is still there, skipped, and in a backlog session its backlog row stays (#368), so the rating completes it.

**Functional requirements**
- FR-T2-01 Tapping the card or *Show meaning* MUST reveal; auto-play rules per `03-domain/tts.md`.
- FR-T2-02 Rating MUST write one transaction (plan engine `rate`) and advance; a 4 s snackbar *Undo* MUST revert it fully. It reverts that rating only: when the word has been rated again since, elsewhere (an L8 answer under a bar a screen reader keeps), nothing changes (#888). *I know it*'s *Undo* likewise.
  - The bar floats clear of the next card's thumb zone, a new word's *I know it* and *Skip → backlog* included (#742).
  - The card that completes the day keeps its *Undo* too: T6 comes once the bar has gone (4 s, or when a screen reader's user closes it). Taken, the session is back on that card (#689 TD-9).
  - A rating, *I know it* or *Skip* acts on the card it came from. A swipe on a card still leaving (its exit animation) writes nothing, rather than rating the card come in its place (#689 TD-10).
- FR-T2-03 *Skip → backlog* MUST leave the item open (BR-PLAN-06) and show "Moved {word} to the backlog · Undo".
- FR-T2-04 *I know it* MUST rate Easy (BR-STATUS-04).
- FR-T2-05 Interval previews MUST be computed with the card's current FSRS state on reveal.
- FR-T2-06 Between blocks a 1 s banner ("Neue Wörter · {category}") MUST play; block order is fixed. The banner is German in every UI language and a screen reader reads it in a German voice, as Today's greeting (#162); with a category, which the course names in English, it keeps the app's voice (#689 TD-12).
- FR-T2-07 Closing MUST NOT prompt; progress is per card. Reopening from Today shows "Continue · n left".
  - A session reopened (or continued) counts what the day already has behind each block: 4 of 15 new words done, it opens at "New today · 5 / 15", with the strip filled to there. The day's planned words of the block no longer open are its done ones, however the session was opened (#345).
- FR-T2-08 Optional swipe-to-rate (left Again, right Good) only when `swipe_to_rate = 1`. Not after a wrong cloze answer, when the bar offers only Again and Hard (#345): a right swipe would be Good (#661).
- FR-T2-09 Long-press the headword copies it; long-press the speaker plays at 0.75×. A keyboard's context-menu key or Shift+F10 does either, on the headword from the moment the card takes the focus (#1039). The overflow's speeds are in the UI language's digits: "০.৭৫×" in Bangla (#425, #689 TD-15).
- FR-T2-10 Cloze cards replace the front for words with `card_mode = cloze` (see states doc). **Typing at large text** (#564, as L8's #554 and L15's #557): past 130 % with the keyboard up, the field, its umlaut row and *Check* filled the room above it and the sentence went under the top bar. The top bar gives up its row (close, "Revise · 4 / 10", the menu) until the keyboard goes, and the field no longer scrolls to keep *Check* in view. *Check* is a scroll away, and the keyboard's Done checks the answer as well. The sentence, its translation, the field and the umlaut row then show above the keyboard. Past 130 % the sentence and its translation are also a role smaller (#572, the rule of #571: reduce first, then scroll), the gaps around the field close (14 → 6, 6 → 2 dp), the field's padding closes (dense, as L8's), and the margin under the umlaut keys is 12 dp, not 20; so on a 360 × 640 phone with a 280 dp keyboard a three-line sentence (about 37 letters) shows whole at 200 % (66 dp under the top before). A longer one scrolls, field first, as L8's and L12's do (#573): the field and its umlaut row stay in view, and a drag shows the sentence while the field keeps the keyboard. At 130 % and below nothing changes.

**Business rules.** BR-FSRS-01/02/06, BR-PLAN-06, BR-STATUS-04.

**Motion.** Reveal: `AnimatedSize` + fade/slide 4 px (quick). Rate: Again slides left, others lift up; next card rises from 16 px below; haptic light (Again medium). Speaker morphs to three bars while playing. Glass: card is gender-tinted `cardStrong`; aurora shifts toward the gender colour.

**Data.** `studySessionProvider(args)`, `PlanRepository.rate/skip/markKnown`, `TtsService`.

**Developer notes.** Keep the queue in the notifier, not in widget state. Precompute the next card's audio while the current card is shown. The rating bar's intervals are pure (`Fsrs.review` × 4) — memoise per card.

**Tests.** FR-T2-02 undo restores `word_state` and deletes the log row; FR-T2-03 skip → backlog next day; FR-T2-05 interval preview equals scheduler; widget: reveal, rate, block banner; goldens front/back/new/cloze × 3 themes.
