# agent-1: work history

## Summary

agent-1 took lane B: the voice seam, word detail and search, the model
download manager and the model manager, translation, and polish. Late in the
project it also took a large share of the large-text and keyboard fixes. It
claimed its first issue (#151) on 2026-09-24 at 11:31 (local time) and was
still active at the v1.0.1 tag on 2026-09-26. In that period it merged **65
PRs** and closed 56 issues through them, 14 of them SQA bugs. It reviewed
about 49 PRs by the other two developers, and it ran the full gate on the
exact commits that were tagged.

One note on the name. Under the original four-agent plan, the session that
finished M3 opened the board as "agent-1" at 10:45 on 2026-09-24 (the board's
first lines, and MEMORY.md's "bootstrap" entry). That work belongs to the
pre-team era (see agent-0's history). The agent-1 described here is the lane
B developer that started work at 11:31.

## What it built

### M5: search, words, Me

| Issue | PR | What it delivered |
|---|---|---|
| #140 | #298 | W1, a word's detail: a sheet with detents on phones, a pane on tablets, a page for deep links. `WordRoute.open` and `?speak=1` |
| #137 | #307 | R1, search results over the four search tiers, joined to the word state, with sentence highlights, filter chips and a step pre-filter |
| #141 | #309 | W1's actions (add to today, mark known, reset, suspend, card mode, with undo) and the `Translator` seam with an "unavailable" implementation |
| #138 | #359 | R1 idle: recent searches and my words |
| #139 | #362 | R1 no results, the web hand-off, and "add as my word" |
| #143 | #364 | R2, add and edit my word |
| #316 | #366 | The card-mode choice in W1 survives the next review (`word_state.card_mode_manual`, user.db schema v3) |
| #363 | #375 | Words of one's own in revision and quizzes (split out of #143) |

### M6: voice, translation, widget

| Issue | PR | What it delivered |
|---|---|---|
| #151 | #290 | The `TtsEngine` interface, `SystemTts`, and a `tts` provider seam that every speaker codes against. 14 test fakes moved into one shared `fake_tts.dart` |
| #156 | #415 | The model download manager: resume, Wi-Fi only, verify then activate, and the space check. Built against fakes while the manifest URLs were wrong |
| #152 | #431 | `SupertonicTts`: Supertonic 3 on the CPU through ONNX Runtime, with the voices Anna, Jonas and Lena mapped to F1, M1 and F2 (the owner's decision) |
| #155 | #447 | M4, the model manager: storage, each model's seven states, voices, and the licence gate |

### M7: polish and release

| Issue | PR | What it delivered |
|---|---|---|
| #280 | #401 | Bar titles at the artboards' 22/600 (Android) and 17/600 (iOS), ending in "…" |
| #166 | #413 | Localisation tests: an untranslated key fails, the two languages switch apart, German keeps its digits |
| #281 | #422 | L6 tests: tie-break, loading, suspended words, ellipsis |
| #284 | #424 | The dev guide reconciled with how the app is really built (no make or fvm), ADR 26, and the owner's gate rule written down |
| #168 | #485 | Every screen doc has its golden matrix, and a test checks it |
| #469 | #519 | content.db rebuilt before the release: the manifest carries meanings, and `skill_prompts` is empty |
| #175 (part) | #547 | The Play listing in English and Bangla, the 1.0.0 changelog, and 24 Android screenshots |

### SQA fixes (milestone SQA)

| Issues → PRs | What they fixed |
|---|---|
| #312 → #334 (P1) | Screen readers can press every Semantics button (13 sites), and an architecture test guards the pattern |
| #315 → #341, #314 → #354 | The back button and T1's ring are named nodes; nothing is cut at 200 % text (chips, word rows, L2's tabs, the ring) |
| #317 → #355, #318 → #357 | Scrolled tab content no longer runs under the status bar; dialog and time-picker buttons read at 4.5:1 |
| #351 → #352 | A suspended word leaves today's plan, and no rating resumes it |
| #328 → #393 | T3's next step follows the day's block order |
| #405 → #412 | `GermanWord` soft-hyphenates long compounds through `DpHeadword` |
| #390 → #418 | The keyboard covers the tab bar; R2 keeps its band behind the status bar |
| #453 → #459 | Every Supertonic voice speaks, not only the first after launch |
| #455 → #467 | Losing Wi-Fi mid-download waits for Wi-Fi instead of showing Failed |
| #452 → #470, #479 | The small play buttons show the slashed no-voice state |
| #345 → #476, #480, #481 | SQA's pass-1 checklist: study-flow nits, rest-day copy, the app name, L10's days, M3's rows |
| #462 → #489 | Android's "Fully drawn" marks Today, so cold start is timed to Today |
| #477 → #488 | Dismissing "Course updated" clears every older update too |
| #501 → #542 | A download the learner starts asks to show its progress in a notification (the owner's decision) |
| #561 → #562 | Typing past 130 %, a two-line L8 prompt shows whole above the field (1.0.1) |

### Follow-ups found during development (no milestone, or Later)

- **Words and study:**
  - #368 → #379: W1's Suspend keeps the backlog rows.
  - #369 → #394: a backup merge gives my words this phone's ids.
  - #387 → #499: EN → DE asks in the learner's meaning language.
  - #421 → #500: W1's header keeps its colour behind the status bar.
  - #528 → #531: W2's drag hint goes once the last column is in view.
  - #515 → #521, #523, #524, #525: four of the five #396 leftovers. agent-2 did the fifth, #526.
- **Voice, performance and downloads:**
  - #430 → #454: T2 has Supertonic make its cards' clips ahead.
  - #436 → #482: stale clips are dropped when their steps change.
  - #460 → #484: Supertonic's sessions open at app start.
  - #486 → #487: the player is primed, so card 1 plays within 300 ms.
  - #438 → #503: the download notification says only what stays true.
  - #506 → #508: the app reports how downloads ended over a stuck notification.
  - #509 → #510: syncing the reminder cancels only its own notifications.
  - #511 → #512: `settingsSourceProvider` moved to the app's providers.
- **Large text and the keyboard:**
  - #404 → #410: the back button and back rows grow at 200 %.
  - #529 → #532: L12 Writing keeps its count line above the keyboard.
  - #565 → #570: a field's hint wraps whole instead of ending in "…".
  - #571 → #575: L12's typed question on a short phone gives way to the band and buttons.
  - #574 → #578: L8's prompt is one role smaller while typing past 130 %.
  - #572 → #582: T2's cloze sentence shows whole on a 360 × 640 phone.
  - #581 → #589: the 150/200 % golden audit also runs in Bangla.
  - #588 → #591: iOS in Bangla at 200 %: the back label and the speaking timer fit.
- **Research:** #494 → #534, which offline translator could bring
  translation back after v1.0. It recommended the Bergamot tiny models; the
  owner's decision is pending on #533.

## How it built things

- **Seams first, so others could build on them.** #151 added the `tts`
  provider before any new speaker existed, so W1, R1 and the quiz runner all
  coded against it. #141 created the `Translator` interface with an
  "unavailable" implementation for #154 to fill. #156 was built against fakes
  because the manifest URLs were known to be wrong (#245, #283).
- **Stacked branches.** When one issue continued another, it stacked the PR
  on the unmerged branch and rebased after the merge:
  - #309 on #307;
  - #364 on #362;
  - #454 on #447;
  - #591 on #589.
- **Locks for shared files.** It held the locks while touching shared
  resources:
  - `shared-look` for #314 and #280 (74 bar goldens regenerated);
  - `user-db-schema` for #316 (schema v3);
  - `adr-number` for #284 (the ADR 26 row).
- **Device-measured voice work.** The Supertonic work was checked on
  emulator-5558 with timings:
  - prepared cards played in 90 to 183 ms (#430);
  - the first card played within 300 ms after priming (#486).
- **Root causes from the device:**
  - #453: `Isolate.run` captured the model, whose futures could not be sent from the second voice on.
  - #462: `FlutterActivity` reported "fully drawn" at the splash, and Android keeps the first report, so `MainActivity` now overrides it.
  - #455: WorkManager returns a stop off Wi-Fi as "canceled".
- **Release support.**
  - It ran `smoke.py` (7/7) and `perf.py` for epic #17's release checks.
  - It ran the final full gate on main: 4,145 flutter and 339 pytest tests on 09f5de98.
  - It ran the gate again on the tag commit (4,166 and 339 on 2b424e33 minus the changelog).
  - It wrote the listing, changelog and screenshots (#547). Its counts are tested against content.db.
- **Splitting scope honestly.** It split #143 (the screen and Save) from #363
  (revision and quizzes), filed #316 for a card-mode gap its own review
  turned up, and filed #486, #506 and #588 when the device or an audit showed
  something new.

## Notable decisions and lessons

- **Questions it put to the owner:**
  - #152: which Supertonic styles Jonas and Lena should use;
  - the performance budget questions on #167 (H-479);
  - #496: the update card's counts;
  - #501: the notification permission for downloads;
  - #533: translation after v1.0.
- **MEMORY.md "gotchas" entry:**
  - `todayPlan` is a snapshot, not a stream, so a feature that writes today's plan items must invalidate it.
  - drift's `insertOnConflictUpdate` omits null columns, so rows are restored with `toCompanion(false)`.
- **Its own memory notes:**
  - Supertonic needs an R8 keep rule for `ai.onnxruntime` in release builds.
  - `DpScript.largeTypingInView` reads the keyboard inside a scaffold's body.
- **Two slips, both corrected:**
  - It ran #141's device check on emulator-5554 minutes before reading the owner's reservation of it for SQA, and told agent-3 exactly what it changed (H-86, H-87).
  - It merged #470 before reading its review's should-fixes, and followed up with #479. The owner later made "read the full review before merging" a rule.

## Reviews it did for others

About 49 distinct PRs: 23 by agent-0 and 26 by agent-2, in 54 review
handoffs. It also swapped reviews with agent-2 while agent-0 was away.
Notable catches:

- **#297 (#123):** the 15 s quiz timer kept running under the Stop dialog, so
  "Keep going" returned to an item already marked wrong.
- **#301 (#124):** the verdict line's speaker had a 32 dp hit area against
  the 48 dp rule.
- **#306 (#126):** "Add missed to revision" wrote `due` directly and bypassed
  FSRS (BR-FSRS-03).
- **#353 (#134):** a double tap on Record started two timers, one of which
  leaked and wrote every second.
- **#360 (#158):** after an update, the 00:05 background task and the app
  could both try to migrate user.db.
- **#361, #365 and #367:** providers kept alive with stale settings, and
  today's study day read from the live mask. Its follow-up question on
  streaks led agent-2 to file #377.
- **#439 (#428):** Retry skipped the new space check.
- **#475 (#165):** at 200 %, T2's Undo bar covered "Show meaning".
- **#490 (#478):** the exam navigator's grown ring was never hit.
- **#495 (#173):** with Hy-MT off, M3 still showed a Translation switch that
  could never turn on (fixed by #513).
- **#497 (#170):** the signing check trusted `key.properties` instead of the
  bundle's certificate.
- **The typography chain:**
  - #498: the hyphen was dropped when a plan broke only at spaces;
  - #507: pronunciation-only captions never got akshara breaks, and a `ৎ`-closed cluster was missed.
- **#552 and #556:** L6 had no test for #550 (added as #553); the audit's
  exemptions were too wide.
- **#563:** a near miss on ß closed the Writing keyboard.
- **#558:** the smoke run was a debug build, not a release build.
