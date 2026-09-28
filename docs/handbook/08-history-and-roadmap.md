# 8 · History and roadmap

Sogda went from its first commit to v1.0.1 in six days, 21 to 26
September 2026: 294 commits on main, 304 issues and 290 merged pull requests.
It was built in eight milestones (M0–M7) from issues generated out of the
specs in `docs/`, by one agent for M0–M3 and then by a team of three
developer agents and a dedicated SQA agent, with the owner making every
product, licence and release decision. This chapter tells that story with
its dates, summarises the decisions that shaped the app, and sets out what
comes next, as direction rather than commitment.

> The detailed specs in [`docs/`](../README.md) are the source of truth. If
> anything here disagrees with them, the spec wins and this page is wrong.

Dates come from git and GitHub. Times, where given, are the repository's
local time (CEST, UTC+2).

## Timeline

| Date | What happened |
|---|---|
| **2026-09-21** | First commit (17:25). The HTML design prototype and the specs in `docs/` were committed the same day, and issues #1–#175 were generated from them and the artboards, each with its goal, design, specification, acceptance criteria and dependencies, in milestones M0–M7 under epics. M0 began: the Flutter project, dependencies, lint, l10n, the architecture test, fonts, the three token sets and `SgSurface` |
| **2026-09-22** | M0's content pipeline (Excel to SQLite, uids, search keys, FTS5, interference tips, integrity gates) and data layer (the drift schema, migrations, settings). M1 began |
| **2026-09-23** | M0 and M1 closed: the engines (FSRS, answer checking, the plan engine), splash, onboarding and placement. M2 began |
| **2026-09-24** | M2 closed at 09:44 and M3 at 10:44: the daily loop and Learn. The team board opened at 10:45, and at 11:27 the work became three agents with agent-0 as the lead (#285, #286). GitHub CI was switched off by the owner at 17:00 (#302): the local gate became the only check. The SQA milestone was created, and the SQA agent joined at 21:25 |
| **2026-09-25** | M4 closed (quizzes and mock exams) and M5 (search, words, Me). SQA pass 1 (M0–M6, about two dozen issues) ended at 00:31 and pass 2 at 14:41; pass 3 followed M5–M7 as they closed, into the night |
| **2026-09-26** | The owner's release decisions: Android only, Hy-MT off in every build (ADR 9). M6 closed (voice, widget). "Later · after v1.0" was created. SQA pass 4 found no P1 and three P2s, all fixed and rechecked. **v1.0.0 tagged at 14:00** on `2b424e33` (#558, closing #175), and M7 closed at 14:01. Seventeen PRs of large-text and Bangla work followed, and **v1.0.1 was tagged at 19:34** on `0d23968e` (#594, closing #593) |
| **2026-09-26, evening** | The owner renamed the app **Sogda** (sogda.de), with the application id `de.sogda.app`, internals included (ADR 28, #601), and adopted the brand kit in `docs/sogda-brand-kit/` (#602) |

Commits on main per day: 22, 46, 22, 44, 74 and 86.

## How the work was organised

### Specs first

The product was specified before it was built: the product
overview and business rules (BR-*), one spec per screen with functional
requirements (FR-*), the engines, the data model, and a clickable HTML
prototype of 58 screens in four canvases, plus the Aurora Glass set. The
specs are the source of truth: "docs win", and a behaviour change updates
`docs/` in the same PR. Issues were generated from the specs, so each one
names its artboards, its spec and its dependencies.

### Phase 1: one agent (M0–M3, 21–24 September)

A single agent worked through M0 to M3 in order, one issue, one branch and
one squash-merged PR at a time: 110 issues. Work was checked by the local
gate (`dart analyze`, `dart format`, pytest, `flutter test` with goldens)
and by GitHub CI, which ran until the owner switched it off on 24 September.

### Phase 2: a team of three developer agents (M4–M7, from 24 September)

With M3 closed, the remaining four milestones were split into lanes and
built in parallel ([`ONBOARDING.md`](../../ONBOARDING.md) §10):

| Agent | Role | Lane |
|---|---|---|
| **agent-0** | The lead: assigns work, reviews the others' PRs, closes epics and milestones, relays the owner's decisions | A: the quiz and the exam runner (the critical path), then the release |
| **agent-1** | Developer | B: the voice seam, words, search, translation, polish |
| **agent-2** | Developer | C: Me, settings, the exam engine, platform work, accessibility |

How they coordinated:

- **A shared board** on the `team` branch: `TASKS.md` (the tasks and
  handoffs), `STATUS.md`, `PLAN.md` (the lanes and the critical path),
  `MEMORY.md` (the owner's rules, decisions already made, lessons) and
  `WORKLOG.md`, driven by `tools/team.py` (claim, log, review, done, lock,
  decision).
- **One worktree per agent**, never the main checkout.
- **Locks** for the shared things that collide: the user-database schema, ADR
  numbers, `pubspec`, the shared look, and the emulator (`team.py device`).
- **Reviews** by another agent before a merge, and planted violations
  (`tools/plant.py`) to prove each PR's tests catch what they claim to.
- **The owner decides.** Anything the specs don't settle goes to the owner
  (`team.py decision`); agents never guess app ids, signing, licences or
  store questions.
- **The local gate** is the only check once CI was off (#302), and a PR
  merges on `dart analyze`, `dart format`, the touched tests and the plants;
  the full suite and `tools/perf.py` run at each milestone's end.

The detail of who built what is in [`developer-agents/`](../../developer-agents/README.md).

### The SQA agent (from 24 September, evening)

A fourth agent, agent-3, took the role of the one SQA engineer: it tests
every closed issue of the milestones on its own emulator, with a fresh
release build, and files what it finds in the milestone **SQA**, with steps,
expected and actual results, and links to the source issue and PR. The
developers fix; SQA rechecks.

| Pass | Ended | Scope | Found |
|---|---|---|---|
| 1 | 2026-09-25 00:31 | M0–M6's closed issues | About two dozen issues (22 on the board) |
| 2 | 2026-09-25 14:41 | Newly closed issues and the SQA fixes | 18 fixes verified; 6 new issues (#388, #389, #390, #396, #405, #406) |
| 3 | 2026-09-26 about 04:00 | M5–M7's issues as they closed, almost in real time | See [agent-3's work history](../../developer-agents/agent-3/work-history.md) |
| 4 | 2026-09-26 13:31 | Before v1.0.0: about 30 closed issues on a release build, then the final re-checks | No P1; three P2s (#548, #550, #554), fixed and rechecked before the tag |
| 1.0.1 | Pending | The v1.0.1 changes | Findings go into 1.0.2 |

The SQA milestone holds 52 issues, all closed.

## Milestone by milestone

| Milestone | Issues | Work ran | Closed | What it delivered |
|---|---|---|---|---|
| **M0 · Foundations** | 60 | 21–22 Sep | 23 Sep | The project, dependencies and codegen, lint and the architecture test, l10n, fonts, the light, dark and glass tokens, `SgSurface`, `SgText`, the adaptive wrappers, shared components, the golden harness, the user database and migrations, settings, and the whole content pipeline |
| **M1 · First run** | 19 | 22–23 Sep | 23 Sep | `text_norm`, FSRS-4.5, answer checking, the plan engine (backlog, rest days, auto-advance, streak); S1 splash and its error state; S2's five pages; S3 placement |
| **M2 · Daily loop** | 19 | 23–24 Sep | 24 Sep | The sentence picker; T1 Today in all its states; T2's card states, rating bar, undo and swipe; T3, T4, T5, T6 |
| **M3 · Learn & grammar** | 12 | 24 Sep | 24 Sep | The grammar practice generator; L1, L2 and its tabs, L3, L4, L15, L5, L6 |
| **M4 · Quiz & mock exams** | 22 | 24–25 Sep | 25 Sep | The quiz builder, the exam generator and grading; L7–L9; L10–L14 with Writing and Speaking |
| **M5 · Search, words, Me** | 19 | 24–25 Sep | 25 Sep | R1, R2, W1 and its actions, W2; M1, M2, M3, M5, M6, M7, M8/M9 |
| **M6 · Voice, translation, widget** | 13 | 24–26 Sep | 26 Sep | The TTS seam, Supertonic 3, engine selection and fallback, the download manager and M4; notifications, background tasks, the widget snapshot and the Android widget. The Hy-MT translator (#154) was deferred |
| **M7 · Polish & release** | 25 | 24–26 Sep | 26 Sep | The screen-reader pass, contrast, reduce motion and transparency, 200 % text, localisation, performance budgets, the full golden matrix, the integration smoke test, the Android release pipeline, licences, the Hy-MT region decision, the error matrix, the store listing and the tag |

### v1.0.0 (2026-09-26, `2b424e33`)

The first release, on Android. The release checklist on its code: the full
gate green (4,166 Flutter tests and 339 pytest), the smoke test 7 of 7 on the
release build, content rebuilt, licences current, Hy-MT off, the 16 KB check
passing, `perf.py all` passing, the store listing in English and Bangla with
screenshots. Two items were left to the owner: signing with the upload key,
and a start-time check on a real phone. What it contains:
[`CHANGELOG.md`](../../CHANGELOG.md).

### v1.0.1 (2026-09-26, `0d23968e`)

Large text in English and Bangla: 17 PRs. Typing past 130 %, or on a short
phone, keeps the question in view, the exam clock
stays visible, a field's hint wraps whole, Bangla labels at 200 % show whole,
and phones stay portrait while tablets turn. The audit itself now runs in
Bangla too, with the keyboard up. The gate: 4,598 Flutter tests and 339
pytest. The owner said to tag it without waiting for SQA's 1.0.1 pass.

## Key decisions

### The ADRs

All 27 are in [`decisions.md`](../05-dev-guide/decisions.md).

| Area | ADRs | The decision in short |
|---|---|---|
| **Content and data** | 1, 2, 3, 14, 22, 23, 24, 25, 26 | Author in Excel, compile to SQLite (1). Two databases: a read-only course and the learner's own (2). drift for typed SQL and migrations (3), on `sqlite3` 3.x (14). One `.drift` file is both the schema and the codegen source (22); the version lives in `PRAGMA user_version` (23); schema fixtures are committed (24); `skill_prompts.prompt`, not `text` (25). The course is attached by path and read-only by construction (26) |
| **App structure** | 4, 5, 6, 11, 12, 21 | Riverpod 3 with codegen (4). go_router with a stateful shell for the tabs (5). The standalone `material_ui` and `cupertino_ui` packages from the start (6). Three themes through one surface renderer (11). No dynamic colour, so the gender colours hold (12). The Material colour scheme pinned field by field (21) |
| **Learning** | 7, 10 | FSRS-4.5 with default weights, tuned later (7). One exam generator with seeds 1–3, never hand-written papers (10) |
| **Voice and translation** | 8, 9, 27 | Supertonic 3 through ONNX Runtime, the phone's voice as fallback (8). Hy-MT behind a build flag, off in every v1.0 build because its licence excludes the EU, UK and South Korea (9). llama.cpp's CPU backend only: the arm64 APK from 159.5 to 72.3 MB (27) |
| **Privacy** | 13 | No analytics, no accounts |
| **Tooling and build** | 15, 16, 17, 18, 19, 20 | No `custom_lint` (15). Current majors for eight plugins (16). Generated code isn't committed (17). Lint with `dart analyze --fatal-infos`, which runs riverpod_lint (18). Android API 37, minSdk 26, desugaring (19). Non-incremental Kotlin on Windows (20) |

### The owner's decisions

The owner settled these when the specs left them open (from the issues and
the team board's "Decisions already made"):

| Decision | Issue |
|---|---|
| GitHub CI off; the local gate is the only check | #302 |
| A dedicated emulator for SQA, another shared by the developers | #310 |
| The Supertonic voice is offered in setup, over Wi-Fi, with its honest ~400 MB size; the default voice style F1 | #245 |
| Voices: Anna = F1, Jonas = M1, Lena = F2 | #152 |
| The Hy-MT build, if ever offered, is Q4_K_M | #409 |
| About's *Contact* and *Report a problem* go to GitHub issues, since the app has no email | #150, #100 |
| Bangla digits for every number in the Bangla UI; category names stay English for now | #425 |
| Non-text contrast 3:1 everywhere, even against the artboards | #437 |
| Performance: an emulator baseline for regressions, the owner's phone before a release, size by the one-ABI download | #167 |
| The FSRS reference chain in the doc follows the code | #239 |
| The duplicate C2 row is dropped in the pipeline | #407 |
| v1.0 ships on Android only; iOS waits for a Mac | #171, #161 |
| Hy-MT off in every build | #173 |
| The app id `io.github.rahmatullah.deutschplan`; the upload key added later | #170 |
| The app is Sogda, with the app id `de.sogda.app`, internals included | #601 (ADR 28) |
| llama.cpp's CPU backend only | #463 |
| Controls keep their look; invisible 48 dp hit areas are the fix | #478, #492 |
| The Bangla pronunciation follows the meaning language in setup | #527, #537 |
| The update card shows the newest update's counts | #496 |
| A model download may ask for the notification permission | #501 |
| A too-wide Bangla word shrinks to 80 %, then breaks with no hyphen | #522 |
| Phones stay portrait; tablets turn | #577 |

## Roadmap

Everything below is direction, not commitment. Priorities and timing are
the owner's.

### Now: finishing the Play release

| Item | Who | State |
|---|---|---|
| **Sign with the upload key** | The owner | Until `app/android/key.properties` exists, a release build fails unless it opts in to the debug key (`-P allowDebugSigning=true`, #705); Play refuses a debug-signed upload ([`release.md`](../05-dev-guide/release.md), checklist step 5) |
| **Cold and warm start on a real mid-range phone** | The owner | The emulator only tracks regressions; the absolute budgets (1.5 s cold, 500 ms warm) are checked on a phone (checklist step 6) |
| **A native reader checks the Bangla store text** | Not assigned | [`store-listing.md`](../05-dev-guide/store-listing.md) asks for it before the first upload |
| **SQA's 1.0.1 pass** | agent-3 | Pending. Its findings become 1.0.2 |

### Next: "Later · after v1.0"

The milestone's open issues, each blocked on the owner or on a Mac:

| Issue | What | Blocked on |
|---|---|---|
| #171 | The iOS release pipeline: iOS 16+, the privacy manifest, background modes, the widget extension | A Mac with Xcode |
| #161 | The iOS home-screen widget (WidgetKit), the same two sizes, reading the same snapshot | A Mac |
| #398 | The integration smoke test on an iOS simulator, and in CI when it returns | A Mac, and CI (#302) |
| #154 | The Hy-MT translator behind its licence flag | Deferred with ADR 9; the owner |
| #533 | Bring translation back with the Firefox/Bergamot tiny models (MPL-2.0, about 51 MB, bundled)? If yes, a quality check on about twenty course sentences needs reference translations checked by a native Bangla speaker | The owner's decision |

### Noted in the specs, not scheduled

- **Content:** B1 "to be expanded" (379 words); Bangla translations of
  examples, grammar rules and category names; a `compare_group` and word
  senses, so compare sets stop resolving a homograph to the wrong word.
- **Learning:** FSRS weights optimised on the phone once a learner has 1,000
  reviews (ADR 7).
- **Language:** a German UI as an immersion mode.
- **Voice:** a memory budget for Supertonic (the owner's call); the first
  sound of a never-heard word under 300 ms.
- **Size:** measuring the real Play download with `bundletool get-size`.
- **Content updates:** net counts across several unseen updates, if the
  owner wants them.

### The direction: more languages, and more robust features

The owner's stated direction (2026-09-26, in the request that produced this
handbook):

- **More meaning languages.** Learners who think in other languages, with the
  same course. This is mostly data: translations through the workbooks, a
  schema that holds meanings by language, and wider language settings.
- **More languages to learn.** Courses beyond German on the same engines.
  The plan, FSRS, quizzes, exams, export, reminders and the widget carry
  over; the German-specific learning logic (articles and gender, umlauts, the
  cloze's separable verbs, the grammar generator's inflections) would have to
  become pluggable per language.
- **More robust features**, in the owner's words. What that covers is not
  written down yet. The open items above (the iOS release, a licence-clean
  translator, deeper content where it is thin) and whatever SQA and
  learners report are the obvious candidates; that reading is this
  handbook's, not the owner's.

[Chapter 1](01-business.md#growth-more-languages-to-learn-and-more-meaning-languages)
has the full analysis of what the current design already supports and what
would change. The name is already one for many languages: Sogda (ADR 28),
with the brand kit in [`docs/sogda-brand-kit/`](../sogda-brand-kit/README.md),
whose mark changes only its front tile for each new course.
