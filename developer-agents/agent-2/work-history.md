# agent-2: work history

## Summary

agent-2 took lane C: the exam engine, Me, settings and data, the platform
work (reminders, background tasks and the home-screen widget), and
accessibility. From there it grew into the project's typography and
golden-audit owner, and it built the Android release pipeline. It claimed its
first issue (#144) on 2026-09-24 at 11:32 (local time) and ended its last
session at the v1.0.1 tag on 2026-09-26. In that period it merged **57 PRs**
and closed 54 issues through them. It reviewed about 54 PRs by the other two
developers, and ran full-suite gates at milestone ends and for v1.0.1.

## What it built

### M4: quiz and mock exams (the exam engine and hub)

| Issue | PR | What it delivered |
|---|---|---|
| #83 | #296 | `exam_generator.dart`: three seeded papers per step, drawn jointly (scarce sections first, least-recently-used reuse flagged). Every step of the real course gives three disjoint papers of 42 items and 48 points |
| #84 | #299 | Mock-exam grading, with Writing and Speaking scored by rubric |
| #127 | #300 | L10, the mock-exam hub (unlocked) |
| #129 | #305 | L11, the exam intro, which starts the attempt the runner resumes (handed to agent-0 for #130) |
| #128 | #308 | L10, the locked hub |
| #133 | #343 | L12, the Writing task |
| #134 | #353 | L12, the Speaking task and the recorder, with microphone permissions |

### M5: search, words, Me

| Issue | PR | What it delivered |
|---|---|---|
| #144 | #293 | M1, the learner's overview: name, words, a 12-week heat map, schedule, exam badges |
| #146 | #332 | M3, the settings screen. It also wired the glass theme at the root, which the device check found unwired |
| #145 | #358 | M2, the progress detail |
| #148 | #361 | M6, export and import |
| #147 | #367 | M5, study days and reminder, with the day's mask recorded when the day is planned |
| #149 | #402 | M7, reset one step or everything (agent-0 finished the review fixes to close M5) |
| #150 | #411 | M9, About and privacy, and M8, Licences |

### M6: voice, translation, widget

| Issue | PR | What it delivered |
|---|---|---|
| #157 | #356 | The daily reminder, scheduled on the study days |
| #158 | #360 | Background tasks: plan pre-generation, reminder composition, widget refresh |
| #159 | #365, #370 | The widget's snapshot and the word of the day. #370 carries agent-1's two review findings, which #365 had merged without |
| #160 | #378 | X1, the Android home-screen widget |

### M7: polish and release

| Issue | PR | What it delivered |
|---|---|---|
| #172 | #441 | Licence collection is a release step, and M8 lists the Supertonic SDK |
| #282 | #444 | The glass word list on L2 and L6 is one frosted panel |
| #165 | #475 | Text scales to 200 % on every screen, audited by every golden |
| #162 | #483 | Screen readers: German voices for course text, the headword's gender, tooltips, focus after rating |
| #170 | #497 | The Android app id, upload-key signing, and a bundle checked for 16 KB pages |
| #537 | #541 | Docs: the Bangla pronunciation follows the meaning language in setup only |
| #551 | #556 | The 200 % golden audit also fails on text cut at `maxLines` |

### SQA fixes (milestone SQA)

| Issues → PRs | What they fixed |
|---|---|
| #330 → #386 | Grammar "Pick the form" offers real forms, in another sentence. Non-word distractors fell from 71 % to 2 % |
| #406 → #416 | Grammar sentences end at sentences, and a wrong form is the answer's own word's (0 made-up options in 12,060) |
| #425 → #434 | The Bangla UI speaks Bangla to screen readers and writes Bangla digits |
| #432 → #435 | Reset everything's typed confirm scrolls above the keyboard, at 200 % and in Bangla |

### Follow-ups found during development (no milestone)

- **Exam, widget and settings:**
  - #372 → #374: Submit while Speaking records saves the recording first.
  - #409 → #427: Hy-MT is the Q4_K_M build that exists, pinned (the owner's decision).
  - #442 → #443: the widget's Pronounce speaks on the word already open.
  - #445 → #446: a My words row is one node.
  - #513 → #514: M3 hides its Translation group while Hy-MT isn't offered.
  - #517 → #518: every `DpButton` is its own semantics node.
  - #527 → #530: the Bangla pronunciation starts off for an English-only learner.
  - #577 → #579: phones stay portrait, tablets turn (the owner's decision).
- **Accessibility:** #478 → #490, small controls' touch targets grow to 48 dp
  (44 on iOS) around their drawn size, with no layout change.
- **Typography:**
  - #419 → #498: a line that ends at a syllable shows its hyphen.
  - #502 → #505: the hyphen also works in German set among Bangla.
  - #504 → #507: a Bangla word too wide for its line breaks between aksharas.
  - #522 → #544: a Bangla word too wide first shrinks to fit, then breaks between aksharas with no hyphen (the owner's decision).
  - #516 → #520, #535 → #538, #539 → #540: long compounds break at a syllable at 200 % in R1's Open button, R1's sentence hits, T5, grammar practice, placement and T2's cloze.
- **The keyboard at large text (the #554 family, for 1.0.1):**
  - #515 → #526: a German field with the umlaut row under it scrolls above the keyboard.
  - #557 → #559: L15's gap keeps its sentence in view.
  - #560 → #563, #567: the timed exam keeps its clock in view.
  - #564 → #566: T2's cloze keeps its sentence in view.
  - #568 → #569: L8's Forms prompt shows whole in Bangla at 200 %.
  - #573 → #576: L12's typed prompt is one role smaller, and scrolls if it still doesn't fit.
  - #580 → #583: in Bangla at 200 %, the rating label, Backlog's day line and the navigator's numbers show whole.
  - #586 → #587: the Reset dialog's field comes above the keyboard.
  - #590 → #592: Writing's field and R2's German field stay clear of the status bar in Bangla.
- **The audit:** #584 → #585, the 200 % golden audit also puts the keyboard
  up on every screen with a field.

## How it built things

- **Building ahead on stacked branches.** It rarely waited for a merge. The
  typography chain shows the recipe, which is in its memory:
  - #84 was built on #83's branch while #83 was in review.
  - #129 was built on #127's.
  - The typography chain was three stacked PRs, #498 (#419) → #505 (#502) → #507 (#504), merged in order. Each later branch was moved with `git rebase --onto origin/main` and retargeted to main before the next merge.
  - #569 was stacked on #567.
- **A second worktree.** `dp-wt/agent-2-b` let it build the next issue while
  one was in review. #133 was built there while #146 waited, and the second
  half of the typography chain lived there too.
- **Probing the real course.** It measured on real data, not fixtures:
  - #83: three full papers for every step;
  - #330: non-word distractors 71 % → 2 %, and no reused sentences;
  - #406: 0 made-up options in 12,060.
- **Device checks that changed the code.** It found and fixed real bugs on
  the emulator before asking for review:
  - #144: a double keyboard inset, a semantics merge, and future-dated days;
  - #128: a double-read count;
  - #146: glass not wired at the root;
  - #160: the widget's resize cap and ring bitmap.
- **The golden audit as a safety net.** It turned the goldens into an
  accessibility audit and then kept tightening it. agent-1 extended it to
  Bangla (#581).
  - #165: every golden checks 200 % text.
  - #551: the audit fails on text cut at `maxLines`.
  - #584: a keyboard pass at 200 % checks each field against SQA's phone: status bar 24, keyboard top 396.
  - It added `DpTextRole.oneStepSmaller` for the rule "what is asked is one role smaller while typing past 130 %".
- **Typography in the text layer.** Its fixes went into `DpText` and the line
  planner, not into each screen:
  - `_Hyphenated` on runs, `banglaBreaks`, `DpText(breakTooWide:)`;
  - UAX #14's LB13 rule in the planner;
  - akshara-aware breaks for Bangla.
- **Locks.** It held `shared-look` for #146 (the iOS stepper, the slider, the
  switch thumb) and `pubspec` for #157's timezone dependency.
- **Gates and merges.** It ran the full suite in three chunks at `-j 2`:
  - 4,081 flutter and 329 pytest tests on 689929de;
  - 4,598 and 339 on 4dfd9d52 for v1.0.1.
  - While agent-0 was idle, it merged agent-0's approved #495 and #493 so the queue kept moving.

## Notable decisions and lessons

- **Questions it put to the owner:**
  - #150: About's contact, which is the GitHub new-issue page;
  - #425: Bangla digits in every Bangla string, and category names stay English;
  - #478 and #492: whether iOS's segmented control should grow to 44 pt;
  - #522: no hyphen inside a Bangla word;
  - #577: phones portrait, tablets rotate.
- **The Bangla digits rule (#425):** integer ARB placeholders use the
  `decimalPattern` format, numbers the code writes go through `l10n.digits`,
  and `l10n_test` guards both.
- **Lessons in its memory and MEMORY.md:**
  - Emulator installs failing for space: `pm uninstall -k`, then install.
  - `plant.py` counts any output without "All tests passed!" as caught.
  - A slow plant can hang past its timeout.
  - A board issue's "Dependencies" text blocks claims.
  - A reveal test depends on the caret's position and on the order of keyboard and focus.
  - Resizing the window with a dialog open isn't faithful.
  - Stash your own edits, don't `checkout` them.
- **An interruption.** On #551 it was blocked for a while by a permission
  prompt on a file read. It still finished the PR (#556) before the lead's
  reassignment to agent-1 landed.
- **A slip it corrected.** #365 merged without agent-1's review findings,
  because a script skipped the fix commit when main moved. It shipped them
  as #370 and noted the correction on #365.

## Reviews it did for others

About 54 distinct PRs: 39 by agent-1 and 15 by agent-0, in 55 review
handoffs. Notable catches:

- **#289 (#81):** agent-2's first review. A 30-item quiz over a finished
  course took 5.4 s to build, because the synonym regex ran over the whole
  pool before ranking. Filed as #291 and fixed by agent-0 in #292 (178 ms).
- **#313 (#130):** the timer and answers lived in widget state against the
  docs ("docs win"), and a submit that threw stranded the learner.
- **#357 (#318):** under glass the time picker's card is 55 % translucent, so
  its 5.2:1 contrast no longer held.
- **#362 (#139):** "Not in the course" flashed for a word the course has
  while the next query loaded.
- **#381 (#377):** the setup path that records study days had no test, and
  a plant deleting it survived.
- **#413 (#166):** an ICU plural reduced to "" and so passed the
  untranslated-key test.
- **#487 and #489:**
  - a speak that interrupted the priming load ended the day's prefetch;
  - a perf test fixture still used the old package name after #497.
- **#503 (#438):** the platform shows the running download note as one
  ellipsised line, so the Wi-Fi rule never showed.
- **#532 (#529):** on iOS nothing closed the multiline Writing keyboard.
- **#519 (#469):** it verified every table of the rebuilt content.db against
  main's.
- **#562:** a doc conflict with #559's change to the same sentence.
