# agent-3: work history

## Summary

agent-3 was the team's one and only SQA engineer. It claimed no feature
issues and wrote no PRs. Its job was to test every closed issue of M0 to M7
on its own emulator, oldest first, and to file what it found as GitHub issues
in the **SQA** milestone for the developers to fix. It also re-tested each
fix on the device once it merged. It joined on 2026-09-24 at 21:25 (local
time) and worked in four passes up to 2026-09-26 13:31, which included the
final device check before the v1.0.0 tag. In that time it filed **42 issues**
(4 P1, 21 P2, 17 P3), all labelled `sqa`, and verified **36** of them fixed on
the device. Of the remaining six, one was a false positive it withdrew and
one a duplicate; the other four are covered under Pass 4 below. It also
checked five open PRs on the device before they merged.

The details below come from the board (WORKLOG.md, the handoffs) and from its
own coverage ledger, which it kept in the owner's local Claude memory. The
ledger is summarised here with device serials, local paths and the names of
other apps on the emulator left out.

## What it did, pass by pass

### Pass 1: M0 to M6 (2026-09-24 21:25 to 2026-09-25 00:31)

This pass tested every closed issue of M0 to M6 on emulator-5556, with
release x64 builds of main up to bcb766f. It filed 22 issues (its own report
counts 23), verified four fixes the same night, and withdrew one false
positive.

| Issue | Pri | Finding | Fixed by |
|---|---|---|---|
| #312 | P1 | Chips, the rating bar, umlaut keys and T5's answers can't be activated by a screen reader | agent-1, #334 |
| #314 | P2 | At 200 % text, chip labels, word-row meanings and L2's tabs are clipped | agent-1, #354 |
| #315 | P2 | The back button (8 screens) and T1's ring are unlabelled clickable nodes | agent-1, #341 |
| #317 | P2 | Scrolled content on Today, Learn and Me runs under the status bar | agent-1, #355 |
| #318 | P2 | Material dialog buttons at 2.2:1 and 1.9:1 contrast | agent-1, #357 |
| #319 | P1 | The 4 s Undo snackbar never dismisses; raised to P1 when it covered the cloze's Check | agent-0, #323 |
| #320 | P2 | W1 as a page hides its meaning from screen readers | closed: a false positive (see the lessons) |
| #321 | P2 | About 160 of 775 interference tips are for the wrong word class | agent-0, #383 |
| #322 | P3 | `team.py add` crashes on an issue with Bangla text | agent-0, #326 |
| #324 | P2 | T5's word tap misses conjugated verbs: 25 % of tokens say "not from the course" | agent-0, #380 |
| #325 | P2 | `clozeGap` misses 99 % of reflexive verbs and 70 % of phrases | agent-0, #340 |
| #327 | P1 | FSRS counts 24-hour periods, so a card reviewed next morning never grows | agent-0, #344 |
| #328 | P2 | After a Revise-only session, T3 skips the day's open blocks | agent-1, #393 |
| #330 | P2 | Grammar "Pick the form" shows non-words in 71 % of distractors | agent-2, #386 |
| #335 | P3 | L2's last-quiz card rounds 8.5 / 10 to 9 / 10 | agent-0, #395 |
| #337 | P3 | L7 starts a quiz from a category with no learned words (an empty runner) | agent-0, #349 |
| #339 | P3 | Mixed asks Bangla-only questions to an English-only learner | agent-0, #385 |
| #342 | P1 | Turning the backlog pause off is ignored until restart, and missed days are lost | agent-0, #348 |
| #345 | P3 | A checklist of minor gaps from M1 to M6 (digits, study-flow nits, labels) | agent-1, #476, #480, #481 |
| #346 | P3 | Reopening a past date adds a Revise block to a finished day | agent-0, #392 |
| #350 | P3 | The submit dialog counts 40 unanswered where the navigator says 38 | agent-0, #371 |
| #351 | P2 | A suspended word stays in today's plan, and rating it un-suspends it | agent-1, #352 |

### Pass 2: newly closed issues and SQA fixes (2026-09-25 11:16 to 14:41)

This pass ran on main from a83a7e3 to 3bbd5e5.

- **Features tested:**
  - the rest of M4 (#133 to #136);
  - M5's search, words and Me screens (#138, #139, #143, #145, #147, #148, #316, #363, #377);
  - M6's reminder, background tasks and widget (#157 to #160);
  - #287 (articles moved out of the German cell) and #280's bar titles on Android.
- **Fixes verified:** 18 of its pass-1 bugs, each with a comment on the issue:
  #314, #315, #317, #318, #321, #324, #327, #328, #330, #335, #337, #339,
  #342, #346, #350, #351, #388 and #389.

| Issue | Pri | Finding | Fixed by |
|---|---|---|---|
| #388 | P3 | One written word counts for two Writing targets | agent-0, #400 |
| #389 | P3 | L14 says "the time ran out" for questions skipped in an early submit | agent-0, #397 |
| #390 | P3 | With the keyboard up, the tab bar covers R2's form | agent-1, #418 |
| #396 | P3 | A checklist of pass-2 minor gaps | agent-0, #493 |
| #405 | P3 | L12's headword breaks long compounds with no hyphen ("die Reiseversic / herung") | agent-1, #412; the hyphen itself came in agent-2's #498 |
| #406 | P2 | The grammar splitter cuts at an ordinal's dot ("Heute ist _____ 17.") | agent-2, #416 |

### Pass 3: M5 to M7 as they closed (2026-09-25 16:37 to 2026-09-26 about 04:00)

This pass followed the merges almost in real time.

- **Features verified:**
  - W2, Reset, About and Licences (#142, #149, #150);
  - the voice and model work: #152, #153, #155, #156 and #245;
  - contrast (#163, which led to #437), reduce motion (#164), localisation (#166, in part; the rest became #425), licences (#172), and #282, #442 and #445.
- **Fixes verified:** #390, #406, #420, #425, #428, #432, #437, #453 and #455.
  #455 was checked again on main after a late commit.

| Issue | Pri | Finding | Fixed by |
|---|---|---|---|
| #420 | P3 | Resetting one step moves the course's start ("Day 1 of your course") | agent-0, #426 |
| #425 | P2 | Screen readers read English in the Bangla UI, and Bangla strings mix ১২ with 12 | agent-2, #434 |
| #428 | P2 | S2's download ignores free space (fills the phone to 0 B), says "Downloading" while waiting for Wi-Fi, and re-downloads an installed voice | agent-0, #439 |
| #432 | P2 | Reset everything's typed confirm doesn't scroll at 200 % or in Bangla | agent-2, #435 |
| #437 | P3 | M1's subtitle is 4.49:1, and in Glass the heat map and tracks are 1.01:1 | agent-0, #448 |
| #440 | P2 | Supertonic's first audio takes 1.1 to 1.6 s, not under 300 ms | closed as a duplicate of #430 (agent-1, #454) |
| #453 | P2 | Only the first Supertonic voice after launch speaks | agent-1, #459 |
| #455 | P2 | Losing Wi-Fi mid-download shows Failed and can lose progress | agent-1, #467 |
| #473 | P3 | T1 offers "A better voice" with Supertonic installed and Ready | agent-0, #474 |
| #477 | P3 | Dismissing "Course updated" brings back older updates' cards | agent-1, #488 |

**PRs checked on the device before they merged:**

- **#467 (#455):** it found that switching Wi-Fi-only off after a drop left
  a file stuck, then re-checked the fix and wrote "good to merge".
- **#474 (#473):** T1 was not refreshed after a download finished.
- **#475 (#165):** on Android 14 and later, font scaling is nonlinear (a
  96-point box scales to about 97 at 200 %, where the audit assumed linear
  scaling). It also found that L8's prompt hides behind the keyboard at 200 %,
  which it filed later as #554.
- **#476 (#345):** the study-flow items.
- **#540 (#539):** W1's and T2's example rows still cut long compounds at
  200 %. This comment came in pass 4.

### Pass 4: before v1.0 (2026-09-26 10:57 to 13:31)

agent-0 asked for this pass (H-851). It used a fresh release build of main
(4061e0c) under the new app id, after uninstalling the old `com.example`
build.

- **Verified on the device, about 30 closed issues:**
  - the release work: #170, #173, #294, #407, #462, #463 and #469;
  - fixes and follow-ups: #387, #419, #421, #438, #473, #477, #486, #501, #502 and #504;
  - #506, #509, #513, #515 (with #521 to #526), #516, #517, #527, #528 and #529;
  - summaries for #162, #165 and #478.

| Issue | Pri | Finding | Fixed by |
|---|---|---|---|
| #548 | P2 | The first day after onboarding plans twice `daily_new` (a regression: `openDay`'s guard wasn't atomic) | agent-0, #549 |
| #550 | P2 | At 200 % a word row shows "die Gebu…" and cuts its meaning with no ellipsis | agent-0, #552, #553 |
| #554 | P2 | At 200 %, L8's typed answer hides its prompt behind the keyboard | agent-0, #555 |
| #561 | P3 | At 200 % with the keyboard up, a two-line L8 prompt loses its first line | agent-1, #562 (1.0.1) |

**The final gate for v1.0.0.** It re-checked #548, #550 and #554 on main
9869579 (H-934):

- #548 passed on four fresh installs;
- #550 passed;
- #554 mostly passed. The remainder became #561, which it judged not a
  release blocker.

No P1 or P2 from SQA was open. agent-0 tagged v1.0.0 after this report.

Its ledger does not show the four remaining issues re-checked on the device:

- #345 and #396 are checklists. Parts of #345 were checked before the merge
  (#476).
- #554's remainder became #561.
- #561 merged after its last session, for 1.0.1.

## How it tested

- **Its own device.** The owner told it directly to use emulator-5556. #310
  had reserved emulator-5554 for SQA, but that emulator was not running. It
  never touched the developers' emulator-5558, so it never needed the
  developers' device lock.
- **Release builds, keeping the learner.** It tested release x64 builds of
  main (a debug build did not fit on the emulator). It installed each over
  the last with `pm uninstall -k`, so the learner's data carried over and
  schema migrations ran on real data (v2 → v3 for #316). Storage was always
  tight, and it freed space before each install.
- **A coverage ledger.** It kept an oldest-first record of every issue: OK,
  filed, or not device-testable (with the reason). On each resume it listed
  the issues closed since the last pass and tested only the new ones.
- **Probe tests.** Uncommitted tests in its worktree's `app/test/sqa/`, never
  to be committed, measured a bug over the whole course before it was filed:
  - chip semantics;
  - FSRS elapsed days (#327);
  - grammar distractors (#330);
  - the cloze gap (#325, and the fix's rate of 24 % → 7.2 %);
  - grammar blanks (#406).
  This is why its issues carry numbers such as 71 %, 99 % and "about 160 of
  775".
- **Clock travel.** It turned automatic time off and moved the emulator's
  clock with `cmd alarm set-time`. That let it walk through rest days,
  backlogs, streaks, a reminder firing, and the weeks of study needed to
  unlock a step's mock exams. It restored automatic time afterwards.
- **Contrast measurement.** A small script computed WCAG ratios from
  screenshot pixels. It gave #437's 4.49:1 and 1.01:1, and later verified the
  fix at 5.13, 3.19 and 4.21:1.
- **Fake content updates.** A script changed a meaning or removed a word in
  a copy of content.db and its manifest and bumped `content_version`. It then
  built and installed that APK over the old one, so the in-app content update
  ran. This exercised #451 (the Updated chip), #456 (removed words) and found
  #477.
- **Network and storage faults.**
  - It dropped Wi-Fi mid-download at chosen percentages with `svc wifi` scripts (#455, #467).
  - It filled the disk to 0 B with a filler file for #428 and for #174's failed-save path, and deleted the filler afterwards.
- **Timing and motion.**
  - It put markers in logcat to time the first Supertonic audio (#440) and tap-to-audio (#486).
  - It used a screen recording deduplicated by frame to confirm reduce motion (#164).
- **Large text sweeps.** It ran 200 % font-scale passes over each new screen,
  in English and in Bangla, and restored the scale afterwards.
- **Artboard comparisons.** It rendered the glass artboards with a headless
  browser to compare them with the device. It avoided the repo's render tool
  because that tool rewrites `docs/design`.

## Notable findings and lessons

- **The four P1s:**
  - #312: screen readers could not press chips or the rating bar. When the
    same pattern appeared at six new sites, including the timed exam's Pause,
    Navigator and Flag, it warned everyone (H-157), and #334 added an
    architecture test for it.
  - #319: the Undo snackbar never dismissed.
  - #327: FSRS counted 24-hour periods, not days.
  - #342: a stale plan engine lost catch-up days. It also warned agent-2
    that #146's settings writes would hit the same bug (H-141).
- **A false positive, and the rule it led to (#320).** `uiautomator dump`
  wraps an attribute in single quotes when its value contains a double quote,
  and its parser missed those. Since then it confirms any "missing text"
  claim in the raw XML, in both quote styles.
- **A notification lesson (#467).** The download notification's Cancel
  action appears only when the notification is fully expanded. It had wrongly
  reported "no Cancel" from one early capture and corrected itself. Since
  then it never claims a control is missing from a single capture.
- **A time-zone lesson.** gh's `closed:>=` filter and `closedAt` are in UTC.
  A "since" built from local time plus "Z" lies in the future and silently
  misses closures.
- **A duplicate check.** Before filing, it searches all issues for the
  symptom. #440 duplicated agent-1's own #430 and was closed.
- **Reporting on the team.** The owner also asked it to report how the agents
  work. It flagged board inconsistencies in its reports: #347 shown as ready
  though closed, and a PR number mislabelled in a handoff (H-328).
- **Owner requests.** It also built arm64 release APKs for the owner's own
  phone, on request.

## Reviews

agent-3 did not review code. Its reviews were device checks: comments on
each closed issue it verified, and the pre-merge checks on #467, #474, #475,
#476 and #540 described above. Its end-of-pass reports went to everyone:

- H-168: pass 1;
- H-328 and H-347: pass 2;
- H-435 and H-483: pass 3;
- H-912 and H-934: pass 4 and the final gate.

agent-0 triaged its bugs into lanes as they arrived (H-116). At the v1.0.1
tag, agent-0's plan was to route agent-3's 1.0.1 device pass into 1.0.2. That
pass had not started when these notes were compiled.
