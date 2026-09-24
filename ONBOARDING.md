# Onboarding: building DeutschPlan as a team of agents

This is for every coding agent that works on DeutschPlan. Three of you
(`agent-0`, the lead, and `agent-1`, `agent-2`) work at the same time, each on its own issue in its own worktree,
coordinating through a shared task board. `CLAUDE.md` is the one-page
summary; this is the whole of it. Read it once when you take an identity,
then again whenever something surprises you.

1. [The project](#1-the-project)
2. [Setting up](#2-setting-up)
3. [The team: board, memory, handoffs](#3-the-team-board-memory-handoffs)
4. [One issue, start to finish](#4-one-issue-start-to-finish)
5. [Architecture and file structure](#5-architecture-and-file-structure)
6. [Coding guidelines](#6-coding-guidelines)
7. [Testing](#7-testing)
8. [Working in parallel without collisions](#8-working-in-parallel-without-collisions)
9. [Documentation map](#9-documentation-map)
10. [The plan for M4–M7](#10-the-plan-for-m4m7)
11. [Known stale docs](#11-known-stale-docs)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. The project

DeutschPlan is an offline German course for Bangla and English speakers, built
in Flutter for Android and iOS. It covers 12 steps, A1.1 → C2.2: 5,594 words
and 182 grammar topics. It has:

- a daily plan scheduled by FSRS
- grammar practice
- quizzes and mock exams
- on-device voice and translation
- a home-screen widget

It has no accounts and no analytics. No network call happens without a user
action (BR-PRIV-01).

- **Done:**
  - M0 Foundations
  - M1 First run
  - M2 Daily loop (Today, study session, backlog, sentences)
  - M3 Learn & grammar (L1–L6, L15, the grammar practice generator)
- **Left:**
  - M4 Quiz & mock exams
  - M5 Search, words, Me
  - M6 Voice, translation, widget
  - M7 Polish & release

  That is about 60 issues, organised in `PLAN.md` on the team branch.
- **Issues** are generated from the docs. Each one has a Goal, Design (8 artboard paths), Specification, Acceptance criteria and Dependencies ("Blocked by #…"). Labels:
  - `P0`–`P3`
  - `size:S/M/L`
  - `area:*`
  - `release:*`
  - `platform:*`
- **Epics** (#6, #10–#17) are GitHub issues whose sub-issues are the work. Close each epic once its sub-issues are done.
- **Naming clash:** milestones are M0–M7, and the Me-tab *screens* are also M1–M9. "Screen M4" is the model manager (#155), which sits in *milestone* M6. Always say which one you mean.

## 2. Setting up

### This machine

| | |
|---|---|
| OS | Windows 11. Use Git Bash for commands, PowerShell where noted. |
| Flutter | 3.47.5 / Dart 3.13.4 on PATH (`F:/appDevs/flutterSDK/flutter`). It matches `.fvmrc`. **No `fvm`, no `make`.** |
| Python | 3.10 on PATH (docs say 3.11+). Has pytest, openpyxl, PyYAML and Pillow. |
| gh | Logged in as `rahmat-ullah`. |
| Android | SDK at `C:/Users/User/AppData/Local/Android/Sdk`. App id `com.example.deutschplan`. Emulators: **`emulator-5554` (Pixel_8) is agent-3's (SQA) alone**; the developer agents share **`emulator-5558`** (Medium_Phone, API 36), `tools/device.py`'s default. Leave any other running emulator alone. |
| iOS | Impossible here (no Mac). iOS-only work is written blind and marked *unverified*. |
| RAM | ~32 GB, often only ~4 GB free. Release builds start an 8 GB Gradle daemon: build APKs one at a time (the device lock, §3). |

### Your worktree (once per identity)

Never work in the main checkout `F:/appDevs/deutschplan`. It stays on `main`
for the owner. Each agent gets its own worktree next to it, and keeps it for
every issue it does (the build cache in it is worth gigabytes):

```bash
cd /f/appDevs/deutschplan
git fetch -q origin
git worktree add --detach /f/appDevs/dp-wt/agent-N origin/main
cd /f/appDevs/dp-wt/agent-N
python tools/team.py agents          # pick an idle identity
python tools/team.py join agent-N    # clones the board to F:/appDevs/dp-team/agent-N and marks this worktree
```

Generated code is not committed (ADR 17). Generate it in every new worktree,
and again whenever you rebase or switch branches onto changes to `.drift`,
providers, routes or ARB files. This is the Makefile's `gen` target, spelled
out:

```bash
python tools/mirror_content_schema.py
cd app
flutter pub get                                              # also generates l10n
dart run drift_dev schema steps drift_schemas/ lib/data/db/schema_versions.dart
dart run drift_dev schema generate drift_schemas/ test/db/generated/
dart run build_runner build --delete-conflicting-outputs
```

The first `flutter test` in a new worktree downloads native libraries
(sqlite3, llama.cpp). That needs the network, takes several GB and is slow
once. `content.db` is committed. The Excel workbooks are not: they live only
in the main checkout's `data/`. Copy them in only for a content issue.

### Identity

The repo's `.git/config` (shared by every worktree) sets the author to
`MdRahmatUllah <rahmat.ullah@infinitibit.com>`. That is the owner's rule for
everything that reaches GitHub. Don't override it, and don't commit from
anywhere else. `gh` acts as `rahmat-ullah`. Commit messages end with the
`Co-Authored-By:` line from your system prompt. PR bodies end with
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## 3. The team: board, memory, handoffs

### The files

The coordination state lives on the **`team` branch**. It is never merged into
`main`: the board changes all day, and `main` is the code. `team.py join` clones it to
`F:/appDevs/dp-team/<you>/`:

| File | What it is | Who writes it |
|---|---|---|
| `TASKS.md` | **The task file.** Every open issue: lane, priority, size, status, owner, blockers, PR. Then the shared locks. At the bottom, the handoffs: assignments, review requests, reports and questions between agents. | `team.py` only |
| `STATUS.md` | The project status: milestones, agents, what is in flight, what is ready, what waits on the owner. Regenerated on every change. | `team.py` |
| `PLAN.md` | The route through M4–M7: lanes, order, hand-offs, decisions. | Anyone, when reality changes (announce it) |
| `MEMORY.md` | The project's memory: the owner's rules, decisions made, lessons learned. | `team.py remember` |
| `WORKLOG.md` | The running record of what each agent is doing, newest last. | `team.py`, and `team.py log` |
| `agents/agent-N.md` | **Your memory:** `Now`, `Next`, `Memory` (notes for your next session), plus `session`, `last-seen` and `last-read`. | `team.py` |

`tools/team.py` is the only thing that edits the board. Each command fetches
`origin/team`, resets to it, applies the change, commits and pushes. If the
push is rejected (someone else changed the board), it starts again from their
version and re-checks. That is what makes a claim safe: two agents can never
both hold an issue, and nobody ever resolves a conflict on the board. Read the
files directly as much as you like. Change them only with the tool.

`PLAN.md` is the one exception, edited by hand. Edit it in your board clone,
then push straight away:

```bash
git -C /f/appDevs/dp-team/agent-N commit -am "plan: <what changed>"
git -C /f/appDevs/dp-team/agent-N push origin HEAD:team
```

If the push is rejected, `pull --rebase` and push again. Announce the change
with `team.py msg all --kind heads-up`. The tool refuses to run while
`PLAN.md` has unpushed edits, because its reset would wipe them.

### Identities and sessions

The team is `agent-0` (the lead), `agent-1` and `agent-2`. Each has a lane
(PLAN.md) and a memory file. **The lead** takes the critical path, assigns
work (`team.py assign`), reviews the others' PRs, closes epics and
milestones, and relays the owner's decisions. The others take their
assignments first, then their lane. A fourth agent joins as `agent-3`, and
the lead gives it work in a handoff. A session takes an identity:

- `team.py agents` lists them as `ACTIVE` or `idle`. An identity is idle when its last session ran `leave`, or when it has not been seen for 2 hours.
- `team.py join agent-N` refuses an active identity. Use `--force` only if you know that session is gone.
- **Start of session:**
  1. join
  2. read `agents/agent-N.md` and `MEMORY.md`
  3. `team.py status`
  4. act on your handoffs, then `team.py ack`
  5. continue `Now`, or claim
- **End of session** (or when you stop for a while):
  ```bash
  python tools/team.py next -m "what I will do next, concretely"
  python tools/team.py note -m "worktree dp-wt/agent-N on feat/140-word-detail; PR #290 waits on agent-1's review; review thread 456 answered"
  python tools/team.py leave -m "one-line summary"
  ```
  Your next session, or another agent taking your identity, starts from exactly that.
- **An identity comes with its worktree.** agent-N always works in `F:/appDevs/dp-wt/agent-N`. If a session dies mid-issue, the next session that joins agent-N continues in that worktree: the uncommitted work, the branch and the claim are all still there, and `Now` and `Memory` say where it was.
- **A stale claim.** An issue can stay `in-progress` or `review` under an identity nobody has joined for a day. Don't reopen it. Take the identity (`join agent-N --force` once `agents` shows it idle) and finish the work from its worktree and memory. Reopen it (`reopen N -m "stale claim of agent-N: <state of its branch>"`) only if that work is unusable.

### Commands

Run them from your worktree: `python tools/team.py <command>`.

| Command | What it does |
|---|---|
| `agents` | List identities: active or idle, last seen, what each is doing |
| `join agent-N [--force]` | Take an identity for this session and worktree |
| `status` | Unread handoffs for you, your tasks, others in flight, what is ready (yours first), held locks |
| `claim N` | Take a ready issue. Refused if it is taken, blocked, assigned to someone else, or you already have one in progress. |
| `log -m "..." [--issue N]` | Add a line to the work log. Do it at every real step. |
| `next -m "..."` | Rewrite the `Next` of your memory |
| `note -m "..."` | Add to the `Memory` of your memory file |
| `remember <topic> -m "..."` | Add a lesson to the project's `MEMORY.md` |
| `review N --pr P [--to agent-M]` | Your PR is up: status becomes `review`, and a review request is posted (to all by default) |
| `done N --pr P -m "..."` | Merged and closed on GitHub (checked). Posts a report to all, naming anything it unblocked. Anyone may record a `done` the owner forgot. |
| `release N -m "why"` | Give an issue back, e.g. when you are blocked on it |
| `assign N agent-M -m "why"` | Reserve an open issue for another agent, with a handoff telling them |
| `msg <agent-M or all or owner> -m "..." [--kind note/question/answer/report/heads-up/review] [--issue N]` | Any other handoff |
| `ack` | Mark every handoff up to now as read |
| `decision N -m "what must be decided"` | Park an issue for the owner (`needs-decision`) |
| `reopen N -m "why"` | A decision was made, or a claim went stale: open it again |
| `add N --lane X` | Put a new GitHub issue (a follow-up, a bug) on the board |
| `lock <resource> -m "why"` / `unlock <resource>` | Hold a shared resource (see below) |
| `device` / `device --release` | Take or give back the emulator. This is a local lock, so it is not on the board. |

### Statuses

| Status | Meaning |
|---|---|
| `open` | Free |
| `assigned` | Reserved for its owner by another agent |
| `in-progress` | Someone is working on it |
| `review` | Its PR is open |
| `done` | Merged, and the issue is closed on GitHub |
| `needs-decision` | Waits for the owner |

**Ready** means `open` (or assigned to you) with every blocker `done`.

Hold one issue `in-progress` at a time. An issue in `review` does not count,
so while your PR waits on its review, claim the next one.

### Handoffs: how agents talk

- **Reporting:** `done` posts the report to everyone. Include what others need to know in `-m`: a new helper, an API they will call, a gotcha. If a specific lane waits on you, also `msg` them directly.
- **Assigning:** `assign` is for work that continues yours ("#138 is the idle state of the screen I just built"), or that suits an agent's lane better. The agent sees it in `status` and claims it.
- **Review requests:** `review` posts them. **Reviewing beats new work.** Before claiming anything, look at the open review requests, take one, review it on GitHub (§4, step 12), then `msg <author> --kind review -m "PR #P: one finding, inline" / "no blocking findings"`.
- **Questions:** `msg agent-M --kind question`. Answer with `--kind answer`. Don't wait idle for an answer: continue with something else.
- **Heads-ups:** before you change something others build on (a shared component, a route helper, `QuizArgs`, a provider), `msg all --kind heads-up`.
- **The owner:** `msg owner` or `decision` both land in `TASKS.md`. The owner reads the board and `STATUS.md`.
- **When the owner decides**, on the GitHub issue, in a chat, or on the board, whoever hears it:
  1. `team.py reopen N -m "decided: <the decision>"`
  2. `team.py remember decisions -m "#N: <the decision>"`, so no one asks again
  3. If the decision changes behaviour, a docs change in the PR that implements it
- **A new bug or follow-up** found while working or reviewing, that is not yours to fix in this PR:
  1. `gh issue create` with a Problem and Acceptance criteria, the milestone it belongs to and a `P` label
  2. `team.py add <new N> --lane <lane or X>`
  3. Mention it in the PR
- **A forgotten `done`.** `status` flags any issue that is closed on GitHub but still `in-progress` or `review` on the board. Anyone may record it with `team.py done N`; the report says for whom.

### Shared locks

These are on the board, one holder at a time. Take the lock before you start
the change, and release it when your PR merges (or when you abandon the
change):

| Lock | Take it before |
|---|---|
| `user-db-schema` | bumping `AppDatabase.latestSchemaVersion` or adding `drift_schemas/drift_schema_vN.json`. Two parallel v3s can't both be right. |
| `adr-number` | writing the next row of `docs/05-dev-guide/decisions.md` (the next free number is 27; 26 is cited in code but missing, see #284) |
| `pubspec` | adding or bumping a dependency (`pubspec.yaml`/`.lock`; a licence entry is also needed) |
| `ci-config` | `.github/workflows/*`, `Makefile`, `tools/tests/test_ci.py` |
| `shared-look` | a change to `core/theme`, `core/components`, `core/adaptive`, `core/typography` or the golden harness that re-renders OTHER screens' goldens. Adding an optional parameter for your own screen doesn't need it. |

The **developers' emulator** (`emulator-5558`) has a local lock: `team.py
device`, held from `flutter build apk` to the last screenshot. It is released
with `device --release`, and broken automatically after 45 minutes.
`emulator-5554` is agent-3's (SQA) alone, and `tools/device.py` refuses it to
anyone else.

## 4. One issue, start to finish

This is the process M1–M3 were built with. Each step exists because skipping
it once cost a bug.

1. **Pick.** `team.py status`, then `team.py claim N`. Choose the first ready issue in your lane (PLAN.md), unless there is a handoff or a review request.
2. **Branch.** In your worktree:
   ```bash
   git fetch -q origin && git switch -c feat/N-short-slug origin/main
   ```
   Then run the gen sequence (§2). Use `fix/`, `test/`, `docs/` or `chore/` for non-feature issues.
3. **Read.**
   - The issue.
   - Its spec in `docs/` (the FR/BR ids are what you implement and test).
   - Every artboard it names. Read the HTML for exact sizes and colours; render the glass ones with `tools/artboard.py`.
   - The code around it, and what it reuses (§5).
   - A missing spec detail that is a pure gap: fill it, update the doc, and flag it in the PR. A real decision: `team.py decision`.
4. **Implement.**
   - Follow the architecture rules (§5) and guidelines (§6).
   - A screen replaces its `PlaceholderScreen` in `routes.dart`.
   - Copy goes in both ARB files.
   - `team.py log` when a part works.
5. **Test** (§7).
   - Unit tests for logic, widget tests for behaviour, DB tests for queries, all with FR/BR ids in the test names.
   - Add the screen's providers to `todayStub()`.
   - Update the router tests that asserted the placeholder text.
6. **Goldens.**
   - Write `test/golden/<name>_golden_test.dart` (six files: light/dark/glass × phone/tablet; plus `<name>_ios` where the iOS chrome differs).
   - Generate it on its own: `flutter test test/golden/<name>_golden_test.dart --update-goldens`.
   - Compare against each artboard set:
     ```bash
     python tools/artboard.py "$TEMP/cmp.png" docs/design/android-light/X.png app/test/golden/goldens/x_light_phone.png \
       deutsch-plan-v2-aurora-glass-html/android-light/screens/X-android.html app/test/golden/goldens/x_glass_phone.png
     ```
     Then look at the image.
7. **Gate** (from `app/`):
   ```bash
   dart analyze --fatal-infos                         # NO path args (ADR 18)
   dart format --output=none --set-exit-if-changed .
   python -m pytest ../tools/tests -q
   flutter test --timeout 60s                         # the whole suite, goldens included
   ```
   All green, or you don't go on. **GitHub CI is off (#302): this gate is the
   only check the code gets**, so run all four, in full, every time. If you
   changed the content pipeline (`tools/excel_to_sqlite.py`, `content/`), also
   rebuild and verify it: `python tools/excel_to_sqlite.py`, then
   `python tools/verify_content.py` (`docs/02-data/content-pipeline.md`).
8. **Planted violations.** Write a plants file (outside the repo, e.g. `$TEMP/plants-N.json`; use your editor, not a heredoc) with one plant per behaviour you claim: the ordering, the edge case, the route, the l10n key, the bar value… Then run it:
   ```bash
   python tools/plant.py "$TEMP/plants-N.json"
   ```
   - Every plant must be `CAUGHT`.
   - `*MISSED*` means the test is too weak: strengthen it and plant again.
   - `COMPILE?` means the plant is wrong: rewrite it.
   - Typically 12–22 plants per issue. The PR says how many and which.
9. **Device check** (Android screens and anything with platform behaviour):
   ```bash
   python tools/team.py device                         # wait for the lock if refused; do other work
   cd app && flutter build apk --release --target-platform android-x64 && cd ..
   python tools/device.py install launch tap:Learn "tap:Word categories" shot:l5.png
   python tools/team.py device --release
   ```
   Use the real content.db. Look at the screenshots, and fix what the device shows (the goldens use a test font). iOS-only: write it blind and mark it unverified.
   `device.py` drives `emulator-5558`, never agent-3's `emulator-5554`. A plain `adb` call needs `-s emulator-5558`, since several emulators run at once.
10. **Commit.** Stage only your files (`git add app/lib/... app/test/... docs/...`, never a blind `-A` from the root). The message format:
    - Subject: `<type>(<scope>): <screen id>, <what> (#N)`, e.g. `feat(learn): L6, a category's words (#121)`.
    - A body saying what the learner now gets, with the FR/BR ids.
    - Your `Co-Authored-By:` line.
11. **PR.**
    ```bash
    git push -u origin feat/N-slug
    gh pr create --base main --head feat/N-slug --title "<same as the subject>" --body-file "$TEMP/prN.md"
    python tools/team.py review N --pr P
    ```
    The body:
    - `Closes #N`
    - `## What`: a line per FR
    - `## Tests`: the files, the goldens compared, "Planted K violations and all K were caught: …", the device check
    - `## Notes`: deviations from the artboard, spec gaps filled, known ceilings
    - the Claude Code footer
12. **Review.**
    - Another agent reviews when one is free. Otherwise, do a self-review pass as the M3 PRs did, reading the diff as a stranger: real content (content.db has 61-character phrases), races (double taps), stale derived state, other callers of anything shared.
    - A finding is an inline review comment through the API:
      ```bash
      L=$(git show HEAD:<path> | grep -n "<pattern>" | head -1 | cut -d: -f1)   # must be inside a diff hunk
      # write $TEMP/revP.json: {"commit_id":"<sha>","event":"COMMENT","body":"Review pass: one finding.",
      #   "comments":[{"path":"app/lib/...","line":L,"side":"RIGHT","body":"**Headline.** Why, with evidence. Suggest: fix."}]}
      gh api repos/MdRahmatUllah/DeutschPlan/pulls/P/reviews --input "$TEMP/revP.json"
      ```
    - Nothing found: `gh api repos/MdRahmatUllah/DeutschPlan/pulls/P/reviews -f event=COMMENT -f body="Review pass: no blocking findings. Checked: …"`.
    - Approval is impossible: every agent is the same GitHub user.
13. **Fix.**
    - Fix every finding with a test and a plant.
    - Push once, and reply on the thread: `gh api repos/MdRahmatUllah/DeutschPlan/pulls/P/comments/<id>/replies -f body="Fixed in <sha>. …"`.
    - Check the push reached the PR: `gh api repos/MdRahmatUllah/DeutschPlan/pulls/P --jq .head.sha`.
14. **No CI.** GitHub CI is off (the owner's call, 2026-09-24, #302): both
    workflows are disabled, so a push starts nothing and there is nothing to
    wait for. Don't watch, re-run or re-enable a workflow. What it used to check
    is now yours:
    - analyze, format, tests and goldens: the gate (step 7), in full;
    - the PR title (`<type>(<scope>): <what> (#N)`): check it yourself;
    - the content pipeline: rebuild and verify locally when you touch it (step 7).
15. **Merge.**
    - If `gh pr view P --json mergeable` says `CONFLICTING`, rebase on `origin/main`, regenerate, run the gate, and push.
    - If `main` moved since your last gate run, rebase on `origin/main`, regenerate, and run the gate again before merging, even if nothing conflicts. With no CI on `main`, this is what keeps `main` green.
    - Then:
      ```bash
      gh pr merge P --squash --subject "<PR title> (#P)"      # never --delete-branch in a worktree
      gh pr view P --json state --jq .state                  # MERGED
      gh issue view N --json state --jq .state               # CLOSED
      git push origin --delete feat/N-slug
      python tools/team.py done N --pr P -m "what the others should know"
      ```
    - If you find `main` red (the gate fails on a clean `origin/main`), fixing it is everyone's top priority, starting with whoever merged last. Announce it (`team.py msg all --kind heads-up -m "main is red after #P: <what fails>, fixing"`), and nobody else merges until it is green again.
16. **Next.** Back to step 1. `git switch --detach origin/main` first, if the next branch should start clean.

## 5. Architecture and file structure

```
F:/appDevs/deutschplan/
  app/                        the Flutter app (package `deutschplan`)
    lib/                      see below
    test/                     mirrors lib: core/ data/ db/ domain/ features/ golden/ router/ services/
    assets/db/content.db      the course (committed, read-only)
    drift_schemas/            user.db schema fixtures v1, v2 (committed)
  docs/                       the source of truth (§9)
  tools/                      Python: content pipeline, team.py, plant.py, artboard.py, device.py; tests in tools/tests
  content/                    pipeline manifest + interference tips (workbooks are in the gitignored data/)
  deutsch-plan-design-html/, deutsch-plan-v2-aurora-glass-html/    the artboards
```

```
app/lib/
  main.dart                  runApp(ProviderScope) → S1 while bootstrap runs → DeutschPlanApp (MaterialApp.router)
  bootstrap.dart             all startup I/O: open user.db, attach content.db as schema `c`, load settings
  core/
    adaptive/adaptive.dart   the ONLY platform chrome: AdaptiveScaffold, AdaptiveBackButton, AdaptiveSwitch,
                             AdaptiveSegmented, AdaptiveTabBar, AdaptiveNavBar, AdaptiveRefresh,
                             Adaptive.showSheet / showConfirm / showTimePickerFor
    components/              DpButton (primary/secondary/text; compact; drawnHeight), DpChip (step/status/filter/
                             streak/webLink), DpPill, DpProgressRing + DpSegmentedBar, DpRatingBar, DpErrorPanel,
                             DpUmlautBar, DpCallout, DpVerdictRow, DpToast/DpUndo, DpSlider, DpStepper,
                             DpSpeakerButton, DpCoachMark
    providers/app_providers.dart   core providers + every repository and service provider
    theme/                   DpTokens (`context.tokens`: color, surface, typography, shape, spacing, motion),
                             DpSurface (kinds card, cardStrong, bar, tint), AppTheme, AuroraBackdrop, GlassCapability
    typography/dp_text.dart  DpText (Bangla one size larger, automatically), DpHeadword (article colour), DpOneLine
  data/
    db/user_schema.drift     user.db DDL (17 tables) — the only schema source (ADR 22)
    db/app_database.dart     AppDatabase, latestSchemaVersion, stepByStep migrations
    db/*.drift               content.drift (course reads), word_queries, grammar_queries, exam_queries
    repositories/            word, grammar, plan, plan_store, rating_service, exam (quiz+exam persistence),
                             search (4 tiers), backup, model, settings + setting_keys, setup, sentence_store, synthesis_cache
  domain/                    pure Dart: answer_check, cloze, edit_distance, fsrs, grammar_item_generator, placement,
                             plan_engine (PlanStore interface), plan_stats, sentence_picker, text_norm
  features/                  backlog, bootstrap, day_complete, learn (L1–L6, L15), onboarding (S2, S3), sentences (T5),
                             splash, study (T2, T3), today (T1), words (WordRow)
  router/                    routes.dart (typed routes + args + helpers), app_router, app_shell (4 tabs),
                             cross_tab (jumpToTab), route_guards, back_behaviour, deep_links, placeholder_screen
  services/                  tts (TtsEngine, SystemTts), model_downloads, notification_permission
  l10n/                      app_en.arb (template, with @descriptions), app_bn.arb; generated/ is gitignored
```

**Layers**
- `domain/` imports no Flutter, drift, Riverpod or go_router.
- `data/` is the only layer that imports drift, and implements `domain/`'s interfaces (`PlanStore`, `SentenceStore`).
- `features/` render providers and act through notifiers and services.
- `services/` wrap plugins behind small interfaces.

**The rules `app/test/architecture_test.dart` enforces** (so you don't have to guess):
1. `package:material_ui/material_ui.dart` / `cupertino_ui`, never `package:flutter/material.dart` or `cupertino.dart`.
2. `lib/domain/` is pure Dart.
3. Raw colours (`Color(0x…)`, `Colors.x`) only inside `core/theme/`. Escape hatch: `// ponytail: allow-raw-colour`.
4. Chrome only through the adaptive wrappers. Everywhere else these are banned, with their replacements:

   | Banned | Use |
   | --- | --- |
   | `Scaffold(`, `AppBar(` | `AdaptiveScaffold` |
   | `Switch(` | `AdaptiveSwitch` |
   | `SegmentedButton` | `AdaptiveSegmented` |
   | `TabBar(` | `AdaptiveTabBar` |
   | `showModalBottomSheet(` | `Adaptive.showSheet` |
   | `AlertDialog(` | `Adaptive.showConfirm` |
   | `showTimePicker(` | `Adaptive.showTimePickerFor` |
   | `FilledButton`, `ElevatedButton`, `OutlinedButton`, `TextButton(` | `DpButton` (and its kinds) |
   | `Chip(`, `ActionChip(`, `FilterChip(` | `DpChip` |

   The Cupertino equivalents are banned too. Escape hatch: `// ponytail: allow-chrome`.
5. drift only in `lib/data/`.
6. Nothing writes to the course tables (words, grammar_topics, categories, …).
7. No I/O in a widget's `build()`.
8. keepAlive providers in `app_providers.dart` must be listed in `docs/01-architecture/state-management.md`'s Provider map.
9. Navigation outside `lib/router/` uses the typed routes, their `open`/`instead` helpers, or `context.jumpToTab(route)`. No inline paths, no `SomeRoute().push(context)`.
10. `main.dart` keeps `runApp(const ProviderScope`.
11. Use `appLocalizationsDelegates` from `main.dart`.
12. `DateTime.now()` only through `clockProvider` (except in a short allow-list).

**State (Riverpod 3, codegen only)**
- Declare providers with `@riverpod` / `@Riverpod(keepAlive: true)` and `part 'x.g.dart'`. They are generated as `xProvider`.
- A screen's providers sit at the top of its own file.
- Anything the UI watches is a `Stream` provider over a drift `.watch()`, so a write anywhere refreshes it. One-shot and derived values are `Future` providers.
- Loading: `.value` is null, so render nothing or a skeleton. Errors: `DpErrorPanel`.
- Drift row classes can't be provider return types. Wrap them in a class or a record (`WordWithState`, `StepWord`, `CategoryProgress`).
- `appDatabaseProvider` and `settingsProvider` are supplied by bootstrap. Tests override them, or override every screen provider they touch.

**Data (drift)**
- Queries live in `.drift` files as named queries. A repository is a `@DriftAccessor(include: {...})`.
- Writes use drift's typed API, or `customUpdate(sql, updates: {db.table})`. A bare `customStatement` leaves every watcher stale.
- The status (todo/learning/done) is derived in SQL from `done_stability_days`, never read from the stored column.
- Plan dates are local `YYYY-MM-DD`; timestamps are UTC ISO-8601.
- Schema changes:
  1. Take the lock.
  2. Bump `latestSchemaVersion`.
  3. Edit `user_schema.drift`.
  4. `cd app && dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/ && python ../tools/trim_schema_fixture.py`.
  5. Regenerate.
  6. Add `fromNToN+1`.
  7. `migration_test` opens every version.
  8. Update `docs/02-data/user-database.md`.

  Most M4–M6 tables already exist (quiz/exam attempts and answers, custom_words, translation_cache).

**Navigation (go_router, typed)**
- Every documented route already exists in `routes.dart`. Unbuilt ones render `PlaceholderScreen`, and your issue replaces it.
- Full-screen routes are pushed through their helpers (`QuizRoute.open(context, QuizArgs)`, `WordRoute.open`, …). In-tab destinations use `context.jumpToTab(Route(...))`.
- A new route, or a new `extra`-carrying route, also needs:
  - a row in `docs/01-architecture/navigation.md`, which `app_router_test` parses;
  - an `extraFor` entry;
  - a guard entry in `route_guards.dart` if it needs session data.
- Anything that must survive process death goes in the path, not `extra` (the exam attempt id).

**Theming**
- Widgets read `context.tokens`, never hex.
- Every card, sheet, header and bar is a `DpSurface(kind:)`. In scrolling lists use `DpSurfaceKind.bar`: glass allows three blur layers on screen.
- Glass screens wrap the scaffold in `AuroraBackdrop` with a transparent background (see `categories_screen.dart`). The tab colours are Today = primary, Learn = accent, Search = die, Me = der.

**Reuse before you write**

| Need | Use |
|---|---|
| a word list row | `WordRow` (+ `step:`) |
| meanings in the learner's language | `withMeanings` (step_words.dart) |
| level names and colours | `CourseLevel` (learn_screen.dart) |
| a practice header or strip | `PracticeHeader` / `PracticeStrip` (grammar_practice_screen.dart) |
| an answer field | `StudyAnswerField` (study_cloze.dart) |
| a session argument | `SessionArgs` / `SessionBlock` |
| quiz arguments | `QuizArgs` (routes.dart) |
| today's date | `todayProvider` |
| the course's progress | `stepProgressProvider` |
| categories | `categoriesProvider` |

## 6. Coding guidelines

`docs/05-dev-guide/coding-standards.md` is binding. What it says, and what
practice adds:

- **Lints:** flutter_lints + riverpod_lint + `prefer_final_locals`, `avoid_dynamic_calls`, `require_trailing_commas`, `always_declare_return_types`. Zero warnings. `dart format` is the style.
- **Imports:** package imports (`package:deutschplan/...`) everywhere. That is the practice, whatever the doc says about relative ones.
- **Value types:** `@immutable` classes, records and `sealed` class hierarchies. Not freezed: it is a dependency but unused.
- **Text:** `DpText(role:)`, never `Text`. Headwords use `DpHeadword`. Every string is in ARB:
  - `app_en.arb` needs an `@key` with a description that names the screen id.
  - `app_bn.arb` has the same key, no metadata, and plurals with `other` only.
  - German course text comes from content.db. Fixed German UI copy is ARB, and says so in its description.
- **Comments** explain *why*, and name the FR/BR ids and docs they implement. Look at any file in `features/learn/` for the tone. A deliberate simplification is marked `// ponytail: <why, and its ceiling>`.
- **Accessibility:**
  - Every tappable thing is a button in semantics, with a label.
  - Targets ≥ 48 dp / 44 pt.
  - Nothing is conveyed by colour alone.
  - It must survive 200 % text and reduce-motion.
- **Privacy:** no network call without a user action. No analytics, no logging of content.
- **Scope:** build what the issue and its spec ask, reusing what exists. No speculative abstraction. A bug fix goes to the root cause, where all callers route through.
- **Commits and PRs:** Conventional Commits, lower-case, no trailing full stop, British spelling. Scope names are the area: learn, study, today, words, domain, data, router, adaptive, components, theme, l10n, …

## 7. Testing

Layers, per `docs/05-dev-guide/testing.md`:

- **Domain:** pure unit tests. Aim for 95 %.
- **Data:** drift over an in-memory DB with a content fixture.
  - `ContentFixture.write(path)` builds a small content.db from the pipeline DDL: uids `uid-haus`, `uid-tuer`, `uid-strasse`, steps A1.1/A1.2, category 1, topic `g1`.
  - Then `AppDatabase(DatabaseConnection(NativeDatabase.memory()))`, `ATTACH DATABASE '<path>' AS c`, and `SettingsRepository(db)..load()`.
  - Write state through drift's typed API, so the stream tests are honest.
- **Widgets:**
  - A `ProviderScope(key: UniqueKey(), overrides: [...])` over `MaterialApp.router`, with a local `GoRouter` whose stub routes record where you went.
  - Pump at the phone size (390×844 at dpr 3).
  - Load l10n with `AppLocalizations.delegate.load(supportedLocales.first)`.
  - The test font draws every glyph 1 em wide, so wrapping tests need short strings.
- **Shared stubs:** `test/features/today_fixtures.dart`. `todayStub()` overrides every DB-backed screen provider with artboard fixtures (`artboardToday`, `artboardCourse`, `artboardCategories`, …). The router and golden tests pump the real route table with it and no database, so **a new DB-backed screen must add its providers to `todayStub()`**, or unrelated tests fail.
- **Goldens:** `goldenTest('<artboard_name>', builder: ...)` from `test/golden/golden_harness.dart` gives six files, `test/golden/goldens/<name>_{light,dark,glass}_{phone,tablet}.png`. For an iOS variant, add `goldenTest('<name>_ios', modes: [GoldenMode.light], devices: [GoldenDevice.phone], chrome: AdaptiveChrome.cupertino, …)`. Generate them per file, on Windows. Only your gate run checks them now (CI is off), so run the whole suite, not just your file.
- **Tests that read docs:**
  - `app_router_test` reads `navigation.md`'s route table.
  - `architecture_test` reads `state-management.md`'s provider map.
  - `settings_repository_test` reads `user-database.md`'s settings table.

  Change the doc with the code.
- **Placeholders asserted by text:** the router tests (`app_router_test`, `back_behaviour_test`, `route_guards_test`, `deep_links_test`) and `backlog_test`/`sentences_test` look for texts like `'R1'`, `'M1'`, `'W1 $haus'`. Replacing a placeholder means updating those assertions.
- **Planted violations:** `tools/plant.py` (§4, step 8). It never kills other agents' processes. If a stale `flutter_tester` from *your* worktree holds a DLL, run it with `--kill-own-testers`.

## 8. Working in parallel without collisions

The files every feature touches, and how to keep merges cheap:

| File | What features do there | Rule |
|---|---|---|
| `app/lib/l10n/app_en.arb`, `app_bn.arb` | add keys | Add your keys **after the last key of the most related screen** (quiz keys after the `quiz…` keys, placed after that key's `@key` block in `app_en.arb`), not at the end of the file, where every PR collides. A brand-new screen goes after the keys of the screen it is reached from. On conflict, keep both blocks and fix the commas. `test/l10n_test.dart` checks the result. |
| `app/lib/router/routes.dart` | replace a placeholder, add imports and helpers | Keep your edit inside your route's class. Put your import in alphabetical order. Rebase just before merging. |
| `app/test/features/today_fixtures.dart` | add fixtures and `todayStub` overrides | Put your fixtures in `test/features/<feature>_fixtures.dart` and add one spread line (`...searchStub(),`) to `todayStub()`. |
| `app/test/router/*_test.dart` | screen tables, placeholder assertions | Change only your rows. |
| `app/lib/core/providers/app_providers.dart` | new repository or service providers | Append to the right section. A keepAlive provider also needs its row in `state-management.md`. |
| `navigation.md`, `state-management.md`, `user-database.md` tables | rows that tests parse | Rows in order. Keep both sides on conflict. |
| `core/*` shared widgets | new optional parameters | An optional parameter needs no lock. A change that re-renders other screens takes `shared-look`, and you regenerate only the goldens it changes and look at them. |
| golden PNGs | your screen's own | You can't merge PNGs: rebase, regenerate yours, review them. |
| `pubspec.yaml`/`.lock`, `decisions.md`, `drift_schemas/`, the (disabled) workflow files | rare but exclusive | Take the lock (§3). |
| `domain/quiz_builder.dart` | lanes A and B (#142, #143) | Message the owner of the file before you change it. |
| `AndroidManifest.xml`, `Info.plist` | lanes A (#134) and D | Small, separate hunks. Rebase often. |

Rebase on `origin/main` whenever someone reports a merge (a `report` handoff)
that touches your files. It is cheap early and expensive late.

## 9. Documentation map

| Question | Document |
|---|---|
| What is the product, who is it for | `docs/00-product/overview.md`, `glossary.md` |
| What must always be true | `docs/00-product/business-rules.md` (BR-COURSE, BR-STATUS, BR-PLAN, BR-FSRS, BR-ANS, BR-SEARCH, BR-QUIZ, BR-EXAM, BR-CONTENT, BR-PRIV) |
| What a screen does | `docs/04-screens/<screen>.md` (FR-<id>-nn; the screen index is in `docs/README.md`) |
| How an engine works | `docs/03-domain/` (quiz-engine, exam-generator, fsrs-scheduler, plan-engine, answer-checking, search, tts, translation, notifications-widget, sentences, grammar-practice) |
| The data | `docs/02-data/user-database.md` (tables, settings keys, migrations, backups), `content-database.md`, `content-pipeline.md` |
| How the app is built | `docs/01-architecture/` (project-structure, state-management, navigation, theming, accessibility-performance, tech-stack) |
| How to work | `docs/05-dev-guide/` (getting-started, coding-standards, testing, decisions = ADRs 1–25, release, adding-content). This guide adds the team layer. |
| What it looks like | `deutsch-plan-design-html/<android-light, android-dark, ios-light, ios-dark>/screens/<Screen>-<suffix>.html` (PNGs in `docs/design/<canvas>/`); glass: `deutsch-plan-v2-aurora-glass-html/…` (no PNGs, so render with `tools/artboard.py`); `Foundations.html` per canvas holds the tokens |
| Goldens | `app/test/golden/README.md` |
| What to do next | the `team` branch: `PLAN.md`, `TASKS.md`, `STATUS.md` |

Docs are the source of truth: when code and docs disagree, the docs win until
they are deliberately changed, in the same PR as the code.

## 10. The plan for M4–M7

`PLAN.md` on the team branch is the living version. In short:

| Lane | Agent | Focus | Order |
|---|---|---|---|
| **A** | agent-0 (lead) | the quiz and exam runner (the critical path), then release | #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131–#134 → #135 → #136 → #169 → #170 → #171 → #175 |
| **B** | agent-1 | the voice seam, words, search, translation, polish | #151 → #140 → #137 → #141 → #138 → #139 → #156 → #142 → #143 → #280 → #152 → #153 → #155 → #154 → #173 → #166 → #164 → #167 → #174 → #163 |
| **C** | agent-2 | Me, settings, exam engine, platform, accessibility | #144 → #83 → #84 → #127 → #129 → #128 → #146 → #157 → #158 → #159 → #160 → #147 → #145 → #148 → #149 → #150 → #172 → #161 → #162 → #165 → #168 |
| **X** | anyone | follow-ups #281, #282, #284, and closing epics | — |

Things only the owner decides:
- #245 (Supertonic)
- #283 (Hy-MT source)
- #239 (FSRS doc)
- #173 (Hy-MT regions)
- app ids and signing (#170, #171)
- store listing (#175)
- branch protection

When a lane is blocked, in this order:
1. handoffs
2. reviews
3. a ready issue from another lane that doesn't touch that lane's files
4. building ahead against a fake
5. never guessing a decision

## 11. Known stale docs

Until #284 lands, trust these corrections over the docs:

- **Commands.**
  - There is no `make` or `fvm` on this machine. Run the Makefile recipes by hand (§2, §4).
  - `make goldens` rewrites the *whole* golden suite. Update per file.
  - `dart run`, not `flutter pub run`.
  - It is `tools/render_design.py`, not `tool/`. It renders only Paper & Ink; use `tools/artboard.py` for glass.
- **Content.**
  - The workbooks are in the gitignored `data/`, not the repo root. `make content` fails in a fresh worktree, and a normal issue doesn't need it: content.db is committed.
  - Content DB tests are in `test/db/`, not `test/data/`.
- **Tooling.**
  - Goldens use `matchesGoldenFile`, not alchemist. Mocks are provider overrides and hand-written stubs, not mocktail.
  - There is no `integration_test/` yet (#169).
  - Android compileSdk/targetSdk are 37, not 35.
- **Structure.**
  - There is no `app.dart`, `data/files/`, `tables.dart` or `migrations.dart`.
  - The feature folders are the ones in §5.
  - Grammar screens are in `features/learn/`.
  - Screen providers sit at the top of the screen file, not in `<screen>_providers.dart`.
- **Code style.**
  - "freezed for all value types" and "relative imports inside a feature" are not the practice (§6).
  - The adaptive API is `Adaptive.showSheet`/`showConfirm`/`showTimePickerFor`, not `AdaptiveSheet`/`AdaptiveDialog`.
- **ADRs and PRs.**
  - ADR 26 (content.db attached by plain path, read-only by construction) is cited in code but missing from `decisions.md`.
  - The PR template's checklist is the minimum. The M3 PR body (§4, step 11) is the practice.
- **Stale issue numbers in code.**
  - `routes.dart` `TODO(#119)` should be #132, and `TODO(#136)` should be #140/#141.
  - `main.dart` "#143 wires it" should be #146 (the glass theme).
  - `aurora_backdrop.dart` "#157" should be #167.

## 12. Troubleshooting

| Symptom | Cause, fix |
|---|---|
| `Target of URI doesn't exist: ...g.dart`, `schema_versions.dart` missing | Generated code is not committed: run the gen sequence (§2) |
| `dart analyze` clean for you, riverpod errors for someone else | You passed paths or used `flutter analyze`. Run `dart analyze --fatal-infos` with no arguments. |
| A screen shows stale data after a write | A raw `customStatement` with no `updates:`/`markTablesUpdated` |
| `The argument type ... can't be a provider return type` / the generator can't find a type | A drift row class in a provider signature: wrap it |
| Unrelated router or golden tests throw `UnimplementedError` from `appDatabaseProvider` | Your new screen isn't in `todayStub()` |
| `Flutter failed to delete ... sqlite3.dll` | A stale `flutter_tester` from *your* worktree. `python tools/plant.py x --kill-own-testers`, or stop the process whose command line has your path. Never kill by name. |
| `team.py`: `refused: ...` | Read it. It is the board telling you someone else has it, or it is blocked. `team.py status` shows what is ready. |
| `team.py`: "the board is busy" | Many agents pushed at once; run it again |
| `gh pr merge` prints `Aborting` | You passed `--delete-branch` in a worktree. The merge may have happened: check `gh pr view P --json state`, then delete the branch with `git push origin --delete`. |
| GitHub says "Head branch is out of date" / PR `CONFLICTING` | Rebase on `origin/main`, regenerate, run the gate, push |
| The PR doesn't show your last push | Check `gh api repos/MdRahmatUllah/DeutschPlan/pulls/P --jq .head.sha`; close and reopen the PR if GitHub is stuck |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Release x64 APK only. `tools/device.py install` trims caches and retries. |
| uiautomator dumps are empty | An ANR dialog: `adb reboot`, then wait for `sys.boot_completed` |
| `LF will be replaced by CRLF` warnings | Noise (`core.autocrlf=true`) |
| A generated script has broken `\n` or quotes | You used a bash heredoc. Write the file with the editor or Write tool. |
