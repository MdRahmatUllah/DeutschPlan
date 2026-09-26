# agent-0: work history

## Summary

agent-0 was the lead of the three-agent team. It took lane A, the critical
path: the quiz builder, the quiz runner, the mock-exam runner and, at the end,
the release. It also assigned work, reviewed the other agents' PRs, triaged
SQA's bugs, closed the epics and milestones, and relayed the owner's
decisions. It was active from 2026-09-24 11:27 (local time), when it rebalanced
the lanes for three agents, to the v1.0.1 tag on 2026-09-26 19:34. In that
period it merged **66 PRs**: 63 are attributed with certainty, and 3 tooling
PRs (#288, #303, #311) most probably. Through them it closed 57 issues. It
also closed 9 epics (#6, #10 to #17) and milestones M4 to M7. It reviewed
about 57 PRs by agent-1 and agent-2, and it tagged v1.0.0 and v1.0.1.

## Before the team: M0 to M3

M0 to M3 were built before the board existed, by one Claude Code session
working alone and in sequence.

- **The backlog.** The owner's own commits come first ("first commit",
  "init", "delete windows, web and linux", "update design", all on
  2026-09-21). Then issues #1 to #175 were filed in about ten minutes
  (19:07 to 19:17 UTC on 2026-09-21): the milestones M0 to M7, their 17
  epics, and every feature issue.
- **The PRs.** 101 PRs, #176 to #279, merged between 2026-09-21 19:32 UTC
  and 2026-09-24 08:18 UTC. Each one closed one issue, on its own
  `feat/<N>-<slug>` branch.
  - Their commits are co-authored by Claude Opus 5 up to #241, and by Claude
    Opus 5.5 from #242 (2026-09-23) on.
  - The PRs sampled (#198, #230, #261, #279) each carry a review pass,
    written as a findings table or as inline comments, and the findings were
    fixed before the merge.
- **What each milestone built.**
  - **M0** (60 issues, closed 2026-09-23):
    - the repository layout, the SDK pin, the dependencies and codegen, the lint rules, the l10n scaffolding and the architecture test (#176 to #184);
    - the design tokens for Light, Dark and Glass, `DpSurface`, `DpText`, the Adaptive wrappers, the shared components and the golden harness (#185 to #197);
    - drift and the user.db schema, and the content pipeline PIPE-01 to PIPE-08 (#198 to #211);
    - `ContentDao`, the content update flow and every repository (#212 to #220);
    - bootstrap (#221), a GitHub CI workflow (#222; turned off later by #302), and the router (#223 to #228);
    - the domain engines: FSRS, answer checking, the plan engine, ratings and the streak (#229 to #234).
  - **M1** (19 issues, closed 2026-09-23):
    - the splash, onboarding pages 1 to 5 and placement (#235, #240 to #249);
    - the iOS launch screen, written blind (#250);
    - two startup fixes (#236, #237). #237's title owns the miss: "a ProviderScope at the root, which CI caught and I did not".
  - **M2** (19 issues, closed 2026-09-24):
    - Today, the study session, the rating bar with undo, swipe to rate, the session summary, the backlog, practice sentences and day complete (#251 to #268).
  - **M3** (12 issues, closed 2026-09-24):
    - the course map, step detail and its tabs, the grammar library, topic and practice, the grammar generator, and word categories (#269 to #279).
- **Setting up the team.** The same session then wrote the team's onboarding
  guide, `CLAUDE.md`, `ONBOARDING.md` and `tools/team.py` (#285). It opened the
  board at 10:45 on 2026-09-24. Those first board entries are signed
  `agent-1`: the plan at the time was four agents, with agent-1 on lane A.
- **The switch to three agents.** At 11:27 the owner settled on three agents
  with a lead. The session signing as agent-0 rewrote the plan and made
  `team.py` accept `agent-0` (#286). It then posted the first assignments.

Who carried over is not written down. The owner's local notes from the M2 and
M3 work were made in the same Claude Code session that later led the team as
agent-0. That points to the pre-team builder becoming agent-0, but nothing on
the board says so directly. Whether M0 and M1 (the Opus 5 commits) came from
that same session cannot be told from the history.

## What it built (the team era, M4 to M7)

### M4: quiz and mock exams (the critical path)

| Issue | PR | What it delivered |
|---|---|---|
| #81 | #289 | `quiz_builder.dart`, `DriftQuizStore` and `quizBuilderProvider`: the shared quiz infrastructure used by #83, #122, #142 and #143 |
| #291 | #292 | Distractors are ranked before the synonym check. A 30-item quiz over the whole course went from 5.4 s to 178 ms (found by agent-2's review of #289) |
| #122 | #295 | L7, the custom quiz sheet. It also fixed `Adaptive.showSheet` on iOS for everyone (H-26) |
| #123 | #297 | L8, the quiz runner shell: the timer and per-item persistence |
| #124 | #301 | L8's item layouts and feedback, reusable by the exam runner without verdicts. Tiles are graded by exact match (H-47) |
| #125 | #304 | Wrong items are asked once more at the end |
| #126 | #306 | L9, the quiz result |
| #130 | #313 | L12, the exam runner: timer and resume |
| #131 | #329 | L12's question navigator |
| #132 | #338 | L12's leave dialog |
| #135 | #373 | L13, the exam results, with Speaking's self-assessed ticks re-grading |
| #136 | #376 | L14, the exam review |

It closed epics #6, #10 and #11 and milestone M4, reporting it done on
2026-09-25 (H-274). GitHub shows #10 closed the evening before.

### M5: search, words, Me

| Issue | PR | What it delivered |
|---|---|---|
| #142 | #414 | W2: compare a near-synonym set side by side, and quiz it. This was a lane B issue that agent-0 took |
| #377 | #381 | A change of study days keeps the streaks already earned |

It also took over the review fixes on agent-2's #402 (#149, reset) so that
M5 could close (H-344). It closed epics #12 and #13 and milestone M5 on
2026-09-25 (H-381).

### M6: voice, translation, widget

| Issue | PR | What it delivered |
|---|---|---|
| #245 | #423 | Supertonic 3 is the seven files that exist, each pinned, with the F1 voice (after the owner's decision) |
| #153 | #429 | `TtsService`: one player, with the chosen engine or the phone's voice behind it, and a one-time fallback toast |

It closed epics #14 and #15, and then M6, on 2026-09-26.

### M7: polish and release

| Issue | PR | What it delivered |
|---|---|---|
| #169 | #399 | Integration smoke tests (first day, exam start, exam resumed across a kill) and `tools/smoke.py` |
| #287 | #408 | An article typed into the German cell moves into `article` (it found the 54 nouns while building #81) |
| #164 | #417 | Reduce motion reaches pages, panes, sheets, tabs and swipes |
| #163 | #433 | WCAG AA text contrast in every mode, with Glass measured over its worst blob |
| #174 | #458 | The error matrix: a failed save offers Retry and Export, removed words stay hidden |
| #294 | #466, #468 | The pipeline no longer writes skill prompts scraped from W01, and the docs say why the table is empty |
| #167 | #464, #491 | `tools/perf.py`: size, cold start, frames and search, against baselines |
| #173 | #495 | ADR 9: v1.0 ships with Hy-MT off in every build (the owner's decision) |
| #171 | #546 | Docs: v1.0 ships on Android, and iOS waits for a Mac. #171 itself moved to Later |
| #175 | #558 | Release 1.0.0. Tagged v1.0.0 on 2b424e33 |
| #593 | #594 | Release 1.0.1 (large text in English and Bangla). Tagged v1.0.1 on 0d23968e |

It closed epic #16, then epic #17 and milestone M7 with the v1.0.0 release
on 2026-09-26.

### SQA fixes (milestone SQA)

agent-0 fixed 22 of agent-3's 42 SQA issues, including three of the four
P1s. It also fixed the developer-filed follow-ups kept in the SQA milestone.

| Issues → PRs | What they fixed |
|---|---|
| #319 → #323, #322 → #326 | The Undo snackbar dismisses after 4 s; `team.py` reads gh output as UTF-8 |
| #325 → #340, #324 → #380 | `clozeGap` finds reflexives, phrases and split verbs; T5's word tap finds conjugated verbs |
| #327 → #344 (P1) | FSRS counts local calendar days between reviews |
| #342 → #348 (P1), #346 → #392 | The plan engine follows the settings it holds; a past day reopened never moves the plan back |
| #337 → #349, #339 → #385 | L7's category source opens at 10 learned words; Mixed keeps to the learner's meaning language |
| #321 → #383, #384 → #403 | A word-class tip reaches only its word class; two wrong gender tips gone, reflexive prefixes |
| #350 → #371, #389 → #397, #388 → #400 | The exam submit counts as the navigator does; L14 says "not answered"; one written word counts for one target |
| #335 → #395, #420 → #426 | L2's last quiz keeps its half points; a step reset leaves the course's first day alone |
| #428 → #439 | S2's voice download checks free space, waits for Wi-Fi, and never re-fetches an installed voice |
| #437 → #448, #449 → #461 | Progress tracks, rails, empty days and Sun-field bars reach 3:1 (non-text contrast) |
| #457 → #465, #456 → #471, #451 → #472 | Course-finished days pick Revise once; removed words leave the backlog; the Updated chip shows |
| #473 → #474 | T1 stops offering the voice once Supertonic is installed |
| #396 → #493 | Eight small pass-2 gaps (M1's badge, L12's rubric and chip, R1, M6, T1, T3) |
| #463 → #536 | llamadart ships llama.cpp's CPU backend only: 159.5 → 72.3 MB (the owner's decision) |
| #548 → #549 | A day is opened in one transaction, so overlapping openings plan it once |
| #550 → #552, #553 | Past 130 %, a word row stacks, on L2 and L6 |
| #554 → #555 | With the keyboard up at large text, L8's and the exam's prompt stays above it |

### Other issues and tooling

- #331 → #336: real-course tests attach their own copy of content.db (the tests had failed now and then with "database is locked").
- #347 → #391: the time-per-item medians group ratings by their local day.
- #239 → #543: `fsrs-scheduler.md`'s Good chain now matches what the scheduler computes (the owner's decision: fix the doc).
- #407 → #545: a duplicate C2 noun is dropped in the pipeline, and content.db is rebuilt.
- #286: three agents, with agent-0 as the lead (`team.py` accepts `agent-0`).
- The attribution of three tooling PRs is probable but not certain. agent-0 announced each one in a heads-up at the moment it merged:
  - #288: `team.py status` on a Windows console (H-9);
  - #303: GitHub CI turned off, #302 (H-57);
  - #311: emulator-5554 reserved for agent-3, developers on 5558, #310 (H-84).

## How it built things

- **The critical path first.** It built the lane A chain in order: #81 → #122
  → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #135 → #136. When a
  blocker of someone else's surfaced, it paused its own work:
  - it released #122 to fix #291 at once, because agent-2's #83 was waiting on it;
  - it released #164 when the owner said to close M5 first.
- **Parallel subagents in extra worktrees.** Besides its main worktree, it
  ran `dp-wt/agent-0-c`, `agent-0-d`, `agent-0-fix` and `agent-0-l13`. It
  handed issues to implementation subagents and kept leading meanwhile:
  - "a subagent is building #174" while it took #167 (H-509);
  - "my subagent has your measurements as test cases" for #554 (H-905).
- **Review subagents.** When no other agent was free, its PRs got a
  self-review pass from a subagent before the merge.
  - GitHub's search finds about 17 of its team-era PRs with a self-review or review-subagent comment, for example #383, #385, #403 and #423.
  - On #385, #414 and #429 it is marked as a subagent review.
  - These reviews were not rubber stamps. #414's run of `compare_set.dart` over all 60 real sets came back "changes needed", and so did #429's review.
- **Probing against the real course.** It routinely checked a change
  against all 5,594 words or every topic-day, not just the fixtures:
  - #291's benchmark;
  - #403's regex patterns probed over the whole course;
  - reviews that found a crash on 3 of 21,840 topic-days (#386) and made-up options in #416.
- **Device checks.** It set up the developers' emulator (emulator-5558) with
  an onboarded learner and `exam_unlock_percent=0`, so the exam screens
  (#131 to #136) could be checked there, and wrote the setup into MEMORY.md.
- **Running the team.**
  - **Assignments.** 52 assignments (24 to agent-1, 16 to agent-2, the rest to itself).
  - **SQA triage.** It triaged agent-3's bugs as they arrived (H-116) and took most P1 and P2 SQA bugs itself between lane A items.
  - **Splitting work.** It split large findings so both agents could work in parallel: #571 into #572, #573 and #574, and the 360 × 640 phone findings by screen (H-998, H-999).
  - **Lead's calls.** It made small calls instead of waiting for the owner:
    - the exam timer is a setting, `SettingKeys.examTimer`, not a column (H-52);
    - grammar gaps keep `checkGerman`;
    - a voice download the learner starts selects Supertonic (H-497);
    - the exam clock stays visible past 130 % (H-919);
    - the ✓ key replaces the labelled Check key while typing (H-992).
- **Relaying the owner's decisions.** When the owner decided, it reopened the
  issue, recorded the decision (`team.py remember`; seven owner-decisions
  entries in MEMORY.md) and told the agent concerned. Examples:
  - #150, #409 (H-356), #245, #152 (H-427), #425 (H-420), #167 (H-484), #437;
  - #463, #173, #239, #577, #175, and the Android-only v1.0 (H-798).
  - It asked the owner itself on #450, #463 and #175.
- **Releases.**
  - **v1.0.0.** It held release PR #558 until #556 and #557 had merged and agent-3 had re-checked #548, #550 and #554 (H-923). It had agent-1 run the full gate on the exact release commit, and tagged v1.0.0 on 2b424e33 once the gate was green (H-950, H-961).
  - **v1.0.1.** It tagged v1.0.1 on 0d23968e when the owner said "tag now".
- **Keeping the host alive.** Three agents ran tests on one machine, and
  Claude Code killed full test runs for low memory. agent-0 asked everyone to
  stagger full runs and to use `flutter test -j 2` (H-166, H-254). It relayed
  the owner's rule of a basic gate per PR and the full suite at milestone
  completion (H-304).

## Notable decisions and lessons

- **#291:** rank distractors first and check synonyms lazily. It is the model
  for keeping `quiz_builder` fast over a finished course.
- **H-47:** multiple-choice tiles are graded by exact match, because
  `checkMeaning` splits a cell with commas or brackets into synonyms.
- **H-26 (#122):** iOS sheets had no Material under them. The fix lives in
  `Adaptive.showSheet`, so every sheet benefits.
- **#548:** `PlanStore.atomically` wraps `openDay`, `startNextStep` and
  `switchStep`, and any new code that plans a day must go through it (H-882).
- **MEMORY.md lessons it added:**
  - `mirror_content_schema.py` leaves `content_schema.drift` showing as modified;
  - the state of the emulator-5558 learner;
  - `flutter test -j 2` when three agents share the host.
- **Mistakes it owned:**
  - It installed a feature build on emulator-5554 minutes before the owner reserved that emulator for agent-3, and told agent-3 exactly what changed (H-83).
  - It reassigned #551 to agent-1 while agent-2 had in fact already finished it (#556), and stopped agent-1's duplicate work (H-913).

## Reviews it did for others

About 57 distinct PRs: 29 by agent-1 and 28 by agent-2, in 69 review
handoffs. Most findings were posted inline on the PR, with a one-line
summary on the board. Notable catches:

- **#296 (#83, the exam generator):** changes requested, five findings.
  - Grammar items shared a sentence across papers.
  - Retakes needed the other seeds' stored references.
  - Connectors were ordered by `seq`, not `sublevels.ord`.
  - The writing targets leaked the answers.
  - The size sort was undone by a shuffle.
- **#298 (#140, W1):** the root navigator put M1's name sheet behind the
  keyboard, and the no-voice toast was hidden under the sheet.
- **#299 (#84, grading):**
  - The target matching missed conjugated verbs and umlaut plurals.
  - The first fix then credited *sehen* for *sehr* and *Küche* for *Kuchen*, and it asked for negative tests.
- **#378 (#160, the widget):** a blocker. `org.json`'s `optString` shows the
  word "null" for about half the course's words.
- **#386 (#330):** a `RangeError` crashed L4 and L15 on 3 of 21,840
  topic-days.
- **#394 (#369):** a merge import kept AUTOINCREMENT ids, so two used phones
  could not merge.
- **#402 (#149):** resetting the only enrollment sent the next cold start to
  onboarding.
- **#415 (#156):**
  - download progress was lost across a restart;
  - a failed activation left the model at "verifying";
  - an iOS literal would not compile.
- **#412 (#405):** the soft hyphen broke before a vowel, and Flutter 3.47
  draws no hyphen at U+00AD.
- **#454 and #467:** a prefetch was cancelled by the old screen's dispose; a
  Cancel while waiting for Wi-Fi was undone.
- **#490 (#478):** once grown to 48 dp, Me's step badges took each other's
  taps.
- **#579 (#577):** the orientation lock read `Size.zero` at startup, which
  would have locked tablets to portrait.
