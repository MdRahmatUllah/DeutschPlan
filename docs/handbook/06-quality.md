# 6. Quality

Quality in Sogda rests on layers that each catch a different kind of
mistake: a static gate (analyser and formatter), tests that enforce the
architecture and the copy, unit, data and widget tests named after the
requirements they prove, golden images of every screen in three themes and
two sizes, an audit of every screen at 150 % and 200 % text in English and
Bangla with the keyboard up, planted violations that prove each PR's tests can
fail, device checks on an Android emulator, an integration smoke, performance
baselines, and a dedicated SQA agent that tests every closed issue. GitHub CI
is off by the owner's decision (#302), so all of this runs locally, and this
chapter says what runs when.

> The detailed specs in [`docs/`](../README.md) win if anything here
> disagrees with them, chiefly [`testing.md`](../05-dev-guide/testing.md),
> [`getting-started.md`](../05-dev-guide/getting-started.md) and
> [`accessibility-performance.md`](../01-architecture/accessibility-performance.md).

## The numbers (v1.0.1)

| | |
|---|---|
| Files under `app/test/` | 766 |
| Dart test files (`*_test.dart`) | 207: domain 18, data 24, db 8, core 17, router 5, services 9, features 64, golden 56, and 6 at the root (architecture, l10n, bootstrap, fonts, reminders start, widget) |
| Golden test files | 55, plus `golden_coverage_test.dart` |
| Golden images | 539 PNGs in `app/test/golden/goldens/`, 40 of them iOS chrome |
| Integration tests | 4 in `app/integration_test/`: the three smoke flows and the perf driver |
| Last full suite | 4,598 passed, 0 failed (`flutter test`, at milestone completion) |
| Tools' tests | 339 passed (`python -m pytest tools/tests -q`, 22 test files) |
| ARB keys | 972 in English, 972 in Bangla |
| SQA | milestone SQA (#9): 52 issues closed, 0 open |

## The gate

From `app/` in a worktree (`make` is not installed, so these are the real
commands):

```bash
dart analyze --fatal-infos                         # no path arguments (ADR 18)
dart format --output=none --set-exit-if-changed .
python -m pytest ../tools/tests -q                 # when tools/ changed
flutter test --timeout 60s <the touched test files and their goldens>
```

The owner's rule (2026-09-25):

- **Every PR merges on this basic check**, run at current `origin/main`, plus
  its planted violations, all caught. If `main` moves before the merge, rebase,
  regenerate and run it again.
- **The full suite runs once, when a milestone completes**:
  `flutter test -j 2 --timeout 60s`, in the foreground, in three chunks. Two
  workers, because the machine is short of memory and several agents test at
  once. The full suite includes every golden, so it runs on Windows.
- If a clean `origin/main` fails the gate, fixing it comes first for everyone,
  and nobody else merges until it is green (ONBOARDING §4, step 15).
- Never `taskkill /IM flutter_tester.exe`: it kills every agent's tests. A
  stale tester from your own worktree is stopped with
  `python tools/plant.py x --kill-own-testers`.

`dart analyze` rather than `flutter analyze` matters: `riverpod_lint` is an
analyser plugin that only `dart analyze` loads, so `flutter analyze` passes
with every Riverpod rule silently off.

## The architecture test

`app/test/architecture_test.dart` reads the source and fails the build when a
rule is broken, so the rules don't depend on review:

1. No file under `lib/` imports `package:flutter/material.dart` or
   `cupertino.dart` (use `material_ui` and `cupertino_ui`).
2. `lib/domain/` imports nothing from Flutter, drift, sqlite3, Riverpod,
   go_router, `dart:ui` or `dart:io`, nor anything of the app's outside
   `domain/` (`package:sogda/core/`, `data/`…, or a `../` import).
3. Only `lib/core/theme/` names a raw colour (`Color(0x…)`, `Colors.x`);
   escape hatch `// ponytail: allow-raw-colour`.
4. Screens reach for chrome only through the adaptive wrappers: `Scaffold`,
   `AppBar`, `Switch`, `SegmentedButton`, `TabBar`, `showModalBottomSheet`,
   `AlertDialog`, `showDialog` and the other dialogs, `IconButton`,
   `SnackBar`, `showTimePicker`, the Material buttons and chips, and their
   Cupertino equivalents, are banned elsewhere, `main.dart` included; escape
   hatch `// ponytail: allow-chrome`, on the line or ending the comment above
   it. A `TextField` is allowed.
5. Only `lib/data/` touches drift.
6. Nothing writes to the attached course: not in SQL (`OR IGNORE` included,
   in any `.drift` file) and not through drift's API (`into(db.words)`).
7. No I/O inside a widget's `build()` (FR-S1-01).
8. The keepAlive providers are exactly those `state-management.md` lists, the
   doc's four core ones are all there, and the word and plan repositories
   are not kept alive.
9. Navigation goes through the typed routes, their helpers and
   `context.jumpToTab`: no inline paths (either quote, any verb), no route
   names, no `SomeRoute().go(context)`.
10. `runApp` is handed a `ProviderScope`.
11. Every `MaterialApp` takes `appLocalizationsDelegates`, not gen_l10n's list.
12. `DateTime.now` (called or torn off) and `DateTime.timestamp()` appear only
    in the clock provider and a short, commented allow-list (export and
    update timestamps, the synthesis cache, the time picker).
13. A `Semantics` button that hides its child's gesture carries the tap itself
    (#312).
14. No text colour is a token faded on the screen (#437).
15. Text is `SgText` (`SgOneLine`, `SgHeadword`, `SgRuns`): no raw `Text(`,
    `Text.rich(` or `RichText(` outside `core/typography/` and
    `core/adaptive/`; escape hatch `// ponytail: allow-raw-text`.

## The l10n test

`app/test/l10n_test.dart` checks the copy:

- every key in `app_en.arb` has an `@key` description;
- every key is translated in `app_bn.arb`, and a Bangla message equal to the
  English one is allowed only on its `onPurpose` list (German content, a name,
  a unit);
- one digit system per Bangla string, Bangla digits; an `int` placeholder is
  formatted, and a number written into text goes through `l10n.digits` (#425);
- Bangla numerals never reach German content, such as Today's German date
  (#166);
- every supported locale resolves every key;
- no user-facing string is hard-coded under `lib/` (in `Text(…)`, `tooltip:`,
  `label:`, `hintText:`, `semanticsLabel:`; escape hatch
  `// ponytail: allow-literal`), and a shared component words nothing itself;
- every key is read somewhere under `lib/`, as `l10n.<key>` or
  `AppLocalizations.of(context).<key>` (#640): a key goes
  in with the code that reads it, and out of both ARBs with the last one.

## Tests that read the docs

Three tables in `docs/` are parsed by tests, so the doc and the code can't
drift apart: `app_router_test` reads the route table in `navigation.md`,
`architecture_test` reads the provider map in `state-management.md`, and
`settings_repository_test` reads the settings table in `user-database.md`.
`app_database_test` checks `ownTables` against `user-database.md`, and on the
Python side `test_schema.py` checks the pipeline DDL against
`content-database.md` and `test_reader.py` checks `HEADER_MAP` against
`content-pipeline.md`. Changing one of those behaviours means changing the doc
in the same PR.

## Test layers

| Layer | How | Aim |
|---|---|---|
| Domain | Pure unit tests with a fake clock: FSRS reference values, plan scenarios, answer-checking vectors, the exam generator's no-repeat property over every step, grammar items over every topic | 95 % |
| Data | drift over an in-memory database with a small content fixture attached: `ContentFixture.write(path)`, `AppDatabase.memory()`, `ATTACH … AS c`, `SettingsRepository(db)..load()`; migrations from every fixture; the export and import round trip | 90 % |
| Widgets | A `ProviderScope` with overrides over `MaterialApp.router`, pumped at 390 × 844 at 3×, with hand-written fakes for the voice, translator and downloader | key flows |
| Goldens | `goldenTest` in `test/golden/golden_harness.dart` | every screen |
| Integration | `integration_test` on the emulator, through `tools/smoke.py` | the two flows that must never break |
| Performance | `tools/perf.py` against `tools/perf_baseline.json` | the budgets |

**Shared fixtures.** `test/features/today_fixtures.dart` has `todayStub()`,
which overrides every database-backed screen provider with artboard data, so
the router and golden tests can pump the real route table with no database.
Each feature adds its own stub in `test/features/<feature>_fixtures.dart`
(`quizStub`, `examRunStub`, `searchStub`, `wordStub`, …) and one spread line
in `todayStub()`; a new screen that forgets it makes unrelated tests throw
`UnimplementedError` from `appDatabaseProvider`. A test about the real
course's counts reads them from `app/assets/db/content_manifest.json` rather
than hard-coding them. `test/flutter_test_config.dart` loads the real fonts
(Inter, Noto Sans Bengali, the Material icons) once per suite.

**Test names carry requirement ids**: `test('FR-T1-03 primary button label
shows remaining count', …)`, so a failure names the behaviour it broke and a
reviewer can map tests to the spec.

## Goldens

Goldens are the design contract ([`app/test/golden/README.md`](../../app/test/golden/README.md)).

- **The matrix.** `goldenTest('<name>', builder: …)` emits six images:
  `<name>_{light,dark,glass}_{phone,tablet}.png`, on a 390 × 844 phone (3×) and
  a 1024 × 768 tablet (2×). Glass renders with blur on; its opaque fallback has
  its own tests (`glass_capability_test.dart`).
- **iOS chrome.** Where the iOS chrome differs (a back row, a sheet, a
  segmented control), a second case renders it:
  `goldenTest('<name>_ios', modes: [GoldenMode.light], devices: [GoldenDevice.phone], chrome: AdaptiveChrome.cupertino, …)`.
- **Coverage.** `golden_coverage_test.dart` pairs every screen doc in
  `docs/04-screens/` with its goldens and fails a screen drawn in fewer than
  the three modes on both devices. The native widget is named as the
  exception.
- **Windows only.** Text rendering differs across operating systems, so the
  goldens carry the `golden` tag and are verified on Windows.
- **Updating, per file.** `flutter test --update-goldens test/golden/<screen>_golden_test.dart`
  for the screens a change touches, then look at every changed image.
  Rewriting the whole suite hides an unintended change among hundreds of
  files, and PNGs can't be merged: after a rebase, regenerate your own.
- **Against the design.** `tools/artboard.py` tiles the artboard (a rendered
  PNG, or the glass HTML rendered by headless Edge or Chrome) beside the
  golden, to compare by eye.

### The text audit

`goldenTest` also runs every case, with no image, at 150 % and 200 % text on
the phone in light, first in English and then in Bangla (`'<name> · text 200 % · bn'`,
#581), under Android 14+'s nonlinear text scaling. Each run expects no layout
exception and:

- `expectNothingClipped`: no text cut to a fixed box;
- `expectNoWordBroken`: no word split across lines except at a soft hyphen;
- `expectAllLinesShown`: no text cut to its `maxLines`, a field's hint
  included;
- at 200 %, on a screen with a text field, **the keyboard pass**
  (`expectKeyboardFits`, #584): its last field is focused with SQA's phone's
  room (a 24 dp status bar, the keyboard's top at 396 dp), and the field must
  sit below the status bar, above the keyboard and hit-testable, with nothing
  clipped or broken.

A case sits out the Bangla pass only through `noBanglaAudit:`, which is
allowed only for an iOS case; none uses it today. `textAudit: false` is for a
case that is itself a large-text golden. Today, T2's front, Settings, the exam
runner and R1's long words also have 200 % goldens, and L8, L12, L15, T2, R2
and Reset have keyboard tests of their own on several phone sizes.

## Accessibility testing

- **Labels and targets.** Each golden case runs once more as
  `'<name> · labels'`: every control a screen reader can press must have a
  name (`labeledTapTargetGuideline`) and be at least 48 dp (44 pt under iOS
  chrome); no grown target may reach more than 2 dp into another's box
  (`expectTargetsApart`); and under Material chrome every icon-only control
  needs a tooltip (`expectIconButtonsTipped`). Dense controls (Me's step
  badges) are marked `dense:` and skipped.
- **Contrast.** `test/core/theme/contrast_test.dart` measures WCAG 2.2 AA over
  the tokens in every mode: 4.5:1 for text, 3:1 for large text, icons and
  progress graphics, with glass text checked against the brightest blob.
- **Motion.** `test/core/reduce_motion_test.dart` covers the reduce-motion
  paths.
- **Large text.** The audit above, the 200 % goldens and the keyboard tests.
- **On a device.** The SQA agent re-checks 200 % text, labels and contrast
  on its emulator.

## Planted violations

A test that has never failed is not a guard. `tools/plant.py` proves a PR's
tests can fail: each **plant** replaces one exact snippet in one file with a
deliberately wrong one, runs the named tests, restores the file, and reports
the verdict.

```json
{
  "tests": ["test/features/today_screen_test.dart"],
  "plants": [
    {"name": "no ring", "file": "lib/features/today/today_view.dart",
     "old": "revise.done + newToday.done", "new": "revise.done"}
  ]
}
```

- Write the file outside the repository (for example
  `$TEMP/plants-N.json`) with an editor, not a heredoc, and run
  `python tools/plant.py "$TEMP/plants-N.json"`. Paths are relative to `app/`.
- **Verdicts.** `CAUGHT` (the tests failed: good), `*MISSED*` (strengthen the
  test and plant again), `COMPILE?` (the plant doesn't compile, so it proves
  nothing: rewrite it), `ERROR?` (the run broke without a test failing: fix the
  run), `HUNG?` (it timed out: plant it again), `SKIP` (the snippet isn't in
  the file exactly once). Only `CAUGHT` counts, and it needs a non-zero exit
  with failing tests. The same tests first run unplanted and must pass, or
  nothing is planted (#685).
- A plant in a codegen input (a `.drift` file, or a file with a generated part
  it affects) sets `"codegen": true`, and build_runner runs around it.
- One plant per behaviour the PR claims: an ordering, an edge case, a route, an
  l10n key, a bar's value. Typically 12–22 per issue, all caught, and the PR
  body says how many and which.

## Device checks

Goldens run in the test renderer with fake plugins; a device shows what they
can't: the real renderer, storage, plugins and keyboard. Every Android screen, and anything with platform behaviour, is checked on the
emulator with the real content.db:

```bash
python tools/team.py device                         # take the emulator lock; if refused, do other work
cd app && flutter build apk --release --target-platform android-x64 -P allowDebugSigning=true && cd ..
python tools/device.py install launch tap:Learn "tap:Word categories" shot:l5.png
python tools/team.py device --release
```

- Always a **release x64 APK**: debug APKs don't fit the emulator's storage.
- `device.py` steps: `tap:`, `find:`, `at:x,y`, `type:`, `wait:`, `shot:`,
  `back`, `swipe`, `sleepN`, `labels`. Screenshots go to the temp directory,
  never into the repository.
- The developers share `emulator-5558` under the device lock, held from the
  build to the last screenshot and broken automatically after 45 minutes.
  `device.py` refuses `emulator-5554` to anyone but the SQA agent. A plain
  `adb` call needs `-s emulator-5558`.
- iOS-only behaviour is written blind and marked unverified (no Mac).

## The integration smoke

`python tools/smoke.py` (under the device lock) runs the flows that must never
break, on the real app and content ([`testing.md`](../05-dev-guide/testing.md#integration-smoke-169)):

1. uninstall, and trim caches for the debug APK;
2. `first_day_test.dart`: S1 → S2 with its defaults → T1 → the day's session
   → T3 → T5 (when the day has sentences) → T6, back on Today reading "All done";
3. `exam_start_test.dart`: L10 → L11 → L12, three answers, left mid-exam;
4. force-stop, and check with `pidof` that no process is left;
5. `exam_resume_test.dart`: a new process resumes at question 4 with the
   answers kept, then leaves.

It passes `--no-uninstall` so user.db carries from one file to the next,
prints PASS or FAIL per step, and stops at the first failure. It runs with
the milestone's full suite and before a release, not per PR.

## Performance

`python tools/perf.py all`, under the device lock, on `emulator-5558`, with the
milestone's full suite and before a release. It compares each number with
`tools/perf_baseline.json` and fails when it grows past its margin: size 3 %,
search 25 %, frames and start 50 % (the shared host moves them by a quarter).
The baseline at v1.0.1:

| Measure | How | Baseline |
|---|---|---|
| Size | arm64-v8a APK of `flutter build apk --release --split-per-abi` | 72.33 MB |
| Frames | `integration_test/perf_test.dart` under `flutter drive --profile`: five cards rated, L2's list flung under glass | card: build 4.0 ms, raster 63.4 ms on average; list: build 2.9 ms, raster 68.7 ms |
| Search | `SearchRepository.search` per keystroke over the real content.db | median 17.8 ms, slowest 32.6 ms (budget 50 ms, enforced) |
| Start | release x86_64, fresh install, median of five, Android's "Fully drawn" | cold 2,799 ms, warm 1,048 ms on the emulator |

The emulator is not a mid-range phone: it catches regressions, and the
absolute budgets (cold start under 1.5 s, warm under 500 ms, 16 ms frames) are
reported, not enforced, except search's. The owner times cold and warm start
on a real phone before each release. `--update-baseline` records new numbers.
`--profile year` measures frames and start again on a learner with a year
behind them (#818: about 13,500 ratings seeded by
`app/integration_test/year_profile.dart`), whose metrics are `year.<metric>`
with baselines of their own.

## The content pipeline's checks

A content change is verified by `python tools/verify_content.py` after every
build (PIPE-08) and by the pipeline's own tests in `tools/tests/` (the reader,
splits, uids, search keys against `test_vectors.json`, FTS, tips, the
manifest). `test/domain/text_norm_test.dart` loads the same vectors, so the
Dart and Python search keys stay byte-identical.

## Documents: how they are checked (v1.2.0)

The documents feature reads text nobody on the team wrote in advance, so it
is tested on a corpus, not only case by case
([`document-matcher.md`](../03-domain/document-matcher.md), *Tests*).

- **The corpus** is in `app/test/fixtures/documents/corpus/`, all
  team-written, with no real person's document: three official letters (a
  landlord's, a Jobcenter's, a health insurer's) and three articles; a
  bank's letter held out, written after the rules were tuned and never tuned
  on; and three more held out by SQA (a school letter, a doctor's letter, a
  news item, #1267). Each has a reader's `.labels.json` of the course words
  in it. `english.txt` and `bangla.txt` are there for the not-German check.
- **The figure.** `test/domain/documents/lemmatiser_test.dart` asserts at
  least 95 % precision and 90 % recall on course words, stop words left
  out. On main on 2026-10-03 it printed **precision 1.000, recall 0.998**.
  The held-out texts are also pinned word for word, so a broken rule shows
  even while the corpus clears its floor; the one known miss is «Bänken»,
  the bench plural the course's *Bank* doesn't have.
- **Named cases.** Separable verbs, compounds, ambiguity, salutations and
  gender forms each have their own test, the classes are tested BR-DOC-03
  case by case, and `matcher_test` holds a two-page letter under 500 ms on
  the host.
- **Privacy** is tested too: `photo_privacy_test.dart` on what
  `withoutMetadata` keeps and drops, and `test/services/page_photos_test.dart`
  on the manifest lines that cut ML Kit's metrics off.
- **On the device,** with a release build, because R8 is where the
  documents broke: a release build without ML Kit's keep rules crashed at
  launch or on its first read, and a debug run showed neither.
  `integration_test/ocr_threshold_test.dart` checks FR-D1-03's 0.7 on a
  letter it draws (0.87 sharp, 0.80 lightly blurred, 0.41 heavily blurred),
  and `integration_test/pdf_probe.dart` reads a PDF where R8 has run.
- **Goldens** for D1, D2 and D3 (`doc_import`, `doc_words`,
  `my_documents`), with the 150 % and 200 % audit in English and Bangla like
  every screen.

## Review

- Every PR is reviewed by another agent before it merges. Reviews beat new
  work. Findings are inline review comments on the exact line, through the
  GitHub API; "no blocking findings" is posted as a review comment too, since
  every agent acts as the same GitHub user and can't formally approve.
- The reviewer reads the diff as a stranger: real content (content.db has
  61-character phrases), races such as double taps, stale derived state, and
  other callers of anything shared. Should-fixes in an approval are read
  before merging.
- The author fixes every finding with a test and a plant, in one push, and
  replies on the thread. A PR body starts with `**Agent-N**` on line 1 and
  lists the tests, the goldens compared, the plants and the device check.

## SQA

A dedicated agent, agent-3, is the project's SQA engineer. It doesn't write
features. It takes every *closed* milestone issue, oldest first, and tests it
on its own emulator (`emulator-5554`, which `tools/device.py` reserves for
it; on the first machine it ran on `emulator-5556`) with a fresh release x64 build of `main`. What it finds becomes a
GitHub issue in the **SQA milestone (#9)**, with steps to reproduce, expected
and actual behaviour, and links to the source issue and PR, and a priority.
The developer agents fix them, and SQA verifies each fix once it merges,
sometimes checking a PR before it merges. It made passes over M0–M6 and a
full pass before v1.0; at v1.0.1 the SQA milestone had 52 issues closed and
none open, and by 2026-10-03 it has 86 closed and none open. SQA also
reports on how the agents work, and keeps its own ledger.

For v1.2.0, SQA's pass is #1234: every input path on its emulator with a
release build, in the UI and meaning languages. Its findings go into M9 with
the `sqa` label rather than the SQA milestone: by 2026-10-03, #1309, #1310,
#1311, #1315 and #1320 (fixed) and #1317 (open). Its review of the
lemmatiser added the corpus's three held-out texts (#1267).

## CI is off

GitHub CI is switched off by the owner's call (2026-09-24, #302): both
workflows are disabled, so a push starts nothing. Nobody waits for, re-runs or
re-enables a workflow. What CI used to check is now each PR's job: analyse,
format, tests and goldens (the basic check, and the full suite at milestone
completion), the PR title format `<type>(<scope>): <what> (#N)`, and a local
content rebuild and verification when the pipeline changes.
