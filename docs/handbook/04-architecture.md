# 4. Architecture

DeutschPlan is one Flutter package (`app/`, package `deutschplan`) built in
layers. Screens render state from Riverpod providers. Providers wrap
repositories. Repositories are the only code that touches drift, which holds
two SQLite files: the learner's `user.db` and the read-only course `content.db`,
attached to it as schema `c`. The rules of the course (scheduling, planning,
quizzes, exams, answer checking) live in pure-Dart engines under `domain/`,
and platform features (voice, reminders, background work, the widget, model
downloads) sit behind small interfaces under `services/`. A test,
`app/test/architecture_test.dart`, enforces the layering mechanically. This
chapter explains the layers, startup, state, data, navigation, theming,
typography, localisation and platform integration, with the reasons behind
each rule.

> The detailed specs in [`docs/`](../README.md) win if anything here
> disagrees with them: [`01-architecture/`](../01-architecture/) for how the
> app is built, [`02-data/`](../02-data/) for the databases and
> [`03-domain/`](../03-domain/) for the engines.

## The layers

```mermaid
flowchart TD
  F["features/<br/>screens, with their providers at the top of each file"]
  K["core/<br/>adaptive chrome, Dp components, tokens and DpSurface, DpText"]
  RT["router/<br/>typed go_router routes, the 4-tab shell, guards, deep links"]
  P["Providers (Riverpod 3, codegen)<br/>core/providers/app_providers.dart"]
  R["data/repositories/<br/>the only layer that touches drift"]
  DB["data/db/ AppDatabase (drift)<br/>background isolate, WAL, foreign keys"]
  U[("user.db<br/>the learner's data, writable")]
  C[("content.db<br/>the course, read-only")]
  E["domain/<br/>pure Dart engines: fsrs, plan_engine, quiz_builder,<br/>exam_generator, answer_check, grammar_item_generator, …"]
  S["services/<br/>TtsService and engines, reminders, WorkManager tasks,<br/>widget snapshot, model downloads, recorder, backup files"]
  PL[("platform plugins<br/>flutter_tts, flutter_onnxruntime, just_audio, record,<br/>flutter_local_notifications, workmanager, home_widget,<br/>background_downloader, 3 method channels")]

  F --> K
  F --> RT
  F --> P
  P --> R
  P --> S
  P --> E
  R -- "uses engines, implements PlanStore, QuizStore, SentenceStore" --> E
  R --> DB
  DB --> U
  DB -- "ATTACH DATABASE … AS c" --> C
  S --> PL
```

What each layer is, and the rule that keeps it that way:

| Layer | Folder | What it holds | The rule, and why |
|---|---|---|---|
| Features | `app/lib/features/<group>/` | One folder per screen group: `backlog`, `bootstrap`, `day_complete`, `exam`, `learn`, `me`, `onboarding`, `quiz`, `search`, `sentences`, `splash`, `study`, `today`, `words` | Widgets read providers and act through notifiers and services; they never call a repository or run a query in `build()`. A screen's providers sit at the top of its own file (Today's are in `today_providers.dart`). |
| Core | `app/lib/core/` | `adaptive/` (all platform chrome), `components/` (the Dp widgets), `providers/` (every repository and service provider), `theme/` (tokens, `DpSurface`, aurora, glass), `typography/` (`DpText`) | Shared by every screen, so a change here re-renders other screens' goldens (the `shared-look` lock, [06-quality](06-quality.md)). |
| Router | `app/lib/router/` | `routes.dart` (typed routes, args, `open`/`instead` helpers), `app_router.dart`, `app_shell.dart`, `cross_tab.dart`, `route_guards.dart`, `back_behaviour.dart`, `deep_links.dart` | Navigation outside this folder uses the typed routes, their helpers or `context.jumpToTab`: no inline paths, so every destination is a route the tests can see. |
| Data | `app/lib/data/db/`, `app/lib/data/repositories/` | `AppDatabase`, the `.drift` files, `ContentDao`, `ContentUpdater`; repositories and services such as `PlanRepository`, `RatingService`, `ExamRepository`, `SearchRepository`, `SettingsRepository` | The only layer that imports drift. Nothing writes to the course tables (ADR 26). |
| Domain | `app/lib/domain/` | The engines, as pure functions and small classes, with interfaces for what they need from storage (`PlanStore`, `QuizStore`, `SentenceStore`) | Imports nothing from Flutter, drift, Riverpod, go_router or any plugin, so every engine is unit-testable with plain Dart and a fake clock. |
| Services | `app/lib/services/` | `tts/` (`TtsEngine`, `SystemTts`, `SupertonicTts`, `TtsService`), `translation/` (`Translator`), `model_downloads`, `reminder_notifications`, `background_tasks`, `widget_snapshot`, `exam_recorder`, `backup_files`, `device_storage`, `notification_permission`, `start_report` | Each plugin sits behind a small interface with a `Platform…` implementation, so widget tests pass a fake (`test/services/fake_tts.dart`). |
| Copy | `app/lib/l10n/` | `app_en.arb` (the template, with descriptions), `app_bn.arb`, `ui_digits.dart` | Every user-facing string is an ARB key; German course text comes from content.db, never from ARB. |

`architecture_test.dart` holds these rules (the full list is in
[06-quality](06-quality.md#the-architecture-test)): no
`package:flutter/material.dart` or `cupertino.dart`, a pure `domain/`, drift
only in `data/`, no raw colours outside `core/theme/`, no Material or
Cupertino chrome outside `core/adaptive/`, no writes to content tables, no I/O
in `build()`, `DateTime.now()` only through `clockProvider`, typed navigation
only, and keepAlive providers only where `state-management.md` lists them.

## Startup

Startup is `main()` and `bootstrap()` (`app/lib/main.dart`,
`app/lib/bootstrap.dart`), specified by [`splash.md`](../04-screens/splash.md)
(FR-S1-01 to -03).

1. `main()` sets edge-to-edge system bars and calls
   `runApp(const ProviderScope(child: BootstrapHost()))` straight away, so S1
   (the splash) draws while the disk work runs. S1 needs only a theme; it
   follows the platform's brightness until settings are read.
2. `BootstrapHost` starts `OrientationLock` (a phone stays portrait, a tablet
   of 600 dp or more turns, #577) and runs `bootstrap()`.
3. `bootstrap()` does all startup I/O, in order, and never throws:
   - opens user.db (`AppDatabase.open`, creating the schema or migrating it)
     and forces the open with `PRAGMA user_version`;
   - peeks `ui_language` so the splash can switch language early;
   - installs the course: `ContentDao.attach()` copies the bundled asset on a
     first run and attaches it as `c`, then `ContentUpdater.runIfNeeded()`
     replaces it when the bundled `content_version` differs (see the sequence
     below);
   - loads every setting into memory (`SettingsRepository.load()`);
   - asks the platform whether glass can blur (`GlassCapability`, bounded to
     150 ms);
   - builds the one `GoRouter`, starting at `/today` for an enrolled learner
     and at S2 page 1 otherwise, with the route guards.
4. The result is `BootstrapReady` (with the provider overrides for
   `appDatabaseProvider` and `settingsProvider`) or `BootstrapFailed` (with the
   step that failed and the database if it opened). A failure shows FR-S1-03's
   error screen, with *Retry* (a content failure deletes the installed copy
   first) and, when the database opened, *Export progress*.
5. On success `main` builds a `ProviderContainer` from the overrides, then
   starts the reminders and background tasks (`startReminders`), the widget
   snapshot (`followWidget`), the model download manager
   (`modelDownloadsProvider.attach()`) and, after the first frame, warms the
   Supertonic voice (`warmTodaysVoice`). `DeutschPlanApp` is a
   `MaterialApp.router` whose theme, locale and theme mode are watched from
   providers.

The cold-start budget is under 1.5 s to Today on a mid-range phone. The app
reports Android's "Fully drawn" once Today shows its plan (the
`deutschplan/start` channel calls `reportFullyDrawn()`), so `tools/perf.py`
measures the real time to Today rather than the splash frame
([`accessibility-performance.md`](../01-architecture/accessibility-performance.md)).

## State

State management is Riverpod 3, with code generation only
([`state-management.md`](../01-architecture/state-management.md)).

- Providers are declared with `@riverpod` or `@Riverpod(keepAlive: true)` and a
  `part 'x.g.dart'`, generated as `xProvider`. `riverpod_lint` runs as an
  analyser plugin, which is why the lint command is `dart analyze`, never
  `flutter analyze` (ADR 18).
- **The database is the source of truth.** Anything the UI watches is a
  `Stream` provider over a drift `.watch()` query, so a rating in a study
  session updates Today's ring, the Learn bars and the streak with no manual
  invalidation. One-shot and derived values are `Future` providers.
- **Auto-dispose by default.** keepAlive is reserved for what must outlive a
  screen, and `architecture_test.dart` holds the set to the doc's list: in
  `app_providers.dart` `appDatabase`, `settings`, `clock`, `theme`,
  `languages`, `modelRepository`, `systemTts`, `supertonicTts`,
  `supertonicVoice`, `tts`, `notificationPermission` and `modelDownloads`; in
  features, `studySession` (the session queue survives backgrounding) and
  `onboarding` (S2's draft survives its pages coming and going).
- **One clock.** `clockProvider` is a `DateTime Function()` and the only
  source of "now"; `todayProvider` derives the local date string from it. It
  does not tick: Today re-reads it on resume and on pull-to-refresh, and
  `todayPlan` watches it, so a new date re-runs `PlanEngine.openDay`.
- **Settings are synchronous.** `SettingsRepository` reads the `settings`
  table once and serves typed values (`SettingKeys`) from memory, because a
  theme or a language is read during `build`. A write persists and fires a
  change that providers follow.
- **Actions are notifier methods** (`ref.read(studySessionProvider.notifier).rate(…)`);
  widgets never write to repositories. A failed answer write goes through
  `guardWrite` (`features/study/write_guard.dart`): the card stays, and a sheet
  offers *Retry* and *Export progress* (#174).
- Drift row classes can't be provider return types, so they are wrapped in a
  class or a record (`WordWithState`, `StepWord`, `CategoryProgress`).

Rating a card shows the whole loop, from a tap to every screen that depends on
the result:

```mermaid
sequenceDiagram
  actor L as Learner
  participant T2 as StudyScreen (T2)
  participant N as StudySession notifier
  participant RS as RatingService
  participant F as Fsrs (domain)
  participant PR as PlanRepository
  participant DB as user.db (drift isolate)
  participant W as Stream providers
  L->>T2: taps Good
  T2->>N: rate(Rating.good), through guardWrite
  N->>RS: rate(uid, good, source: daily, planDate, kind, seconds)
  RS->>DB: read the word_state row
  RS->>F: review(cardState, good, now in UTC)
  F-->>RS: stability, difficulty, due, scheduledDays
  RS->>PR: rate(ScheduledState with status and card mode)
  PR->>DB: one transaction: word_state, review_log, plan_items, daily_stats, undo_stack
  DB-->>W: the .watch() queries fire
  W-->>T2: Today's ring, the Learn bars and the streak rebuild
  N-->>T2: the next card, its headword focused
```

The status (learning or done) follows `done_stability_days`; two consecutive
Good or Easy ratings switch the card to cloze unless the learner chose its
mode (BR-FSRS-06); *Undo* restores the previous `word_state` row and deletes
the log entry in one transaction.

## Data

Two databases, by design (ADR 2): content updates must never touch progress.

- **user.db** is created from `app/lib/data/db/user_schema.drift`, which is
  both the DDL and the source drift generates typed tables from (ADR 22). It
  lives in app-support storage and opens on a background isolate
  (`DriftNativeOptions(shareAcrossIsolates: true)`), so writes stay off the UI
  isolate. Every connection sets `journal_mode = WAL`, `foreign_keys = ON` and
  `busy_timeout = 5000` (`configureConnection`). The schema version is
  `PRAGMA user_version` (ADR 23), now 3.
- **content.db** is the compiled course, bundled at
  `app/assets/db/content.db`, copied to app-support storage and attached by
  plain path as schema `c` (ADR 26). drift generates nothing for an attached
  database, so `ContentDao` runs hand-written SELECTs from `content.drift`,
  type-checked against `content_schema.drift` (a mirror of the pipeline's
  DDL). It is read-only by construction: the content queries are SELECTs only,
  and the architecture test fails on any write to a content table.
- `AppDatabase.allSchemaEntities` filters to `ownTables`, so drift never
  creates an empty `words` table in user.db that would shadow `c.words`.
- Writes use drift's typed API or `customUpdate(…, updates: {…})`. A bare
  `customStatement` would leave every watcher stale.
- Plan dates are local `YYYY-MM-DD` strings (a study day is a local day);
  timestamps are UTC ISO-8601.

A content update happens at launch, inside `bootstrap()`, before any screen
can read the course:

```mermaid
sequenceDiagram
  participant B as bootstrap()
  participant D as ContentDao
  participant U as ContentUpdater
  participant FS as app-support storage
  participant DB as user.db
  B->>D: attach()
  D->>FS: first run only: copy the asset to content.db
  D->>DB: ATTACH DATABASE 'content.db' AS c
  B->>U: runIfNeeded()
  U->>FS: read the kept content_manifest.json (the previous version)
  U->>D: bundledVersion() from the bundled manifest
  alt the versions differ
    U->>D: replaceWithBundled()
    D->>FS: copy the asset to content.db.new
    D->>DB: DETACH c, rename .new over content.db, ATTACH c again
    U->>U: diff the two manifests: added, removed, changed, meaning
    U->>DB: insert content_updates (seen = 0, recorded_at)
    U->>FS: keep the new manifest as the next baseline
  else the same version
    U-->>B: null, nothing to do
  end
  B->>B: load settings, build the router
```

Progress is keyed by word uid, so it survives. A removed word keeps its
`word_state` rows, but plan generation and queries join to `c.words`, so it
disappears from the app without being deleted. Today shows one update card
while `seen = 0`, and words whose meaning changed wear an *Updated* chip for 7
days (BR-CONTENT-02, -03). The manifest is saved last, so an update
interrupted at launch simply runs again next time
([`content-database.md`](../02-data/content-database.md)).

## Navigation

Navigation is go_router 18 with typed routes generated by `go_router_builder`
([`navigation.md`](../01-architecture/navigation.md), ADR 5).

- **Four tabs** under a `StatefulShellRoute.indexedStack` (`AppShellRoute`):
  Today (`/today`), Learn (`/learn`), Search (`/search`) and Me (`/me`). Tabs
  keep their state; a re-tap scrolls to the top, and a second re-tap pops to
  the root.
- **Full-screen tasks** (`/study`, `/sentences`, `/day-complete`,
  `/grammar-practice`, `/quiz`, `/exam/:attemptId`) are declared outside the
  shell, on the root navigator, so they cover the tab bar and close back to
  their opener. Modals never switch tabs.
- **Helpers.** A route is opened with its static `open` (push) or `instead`
  (replace) helper: `StudyRoute.open(context, SessionArgs)`,
  `QuizRoute.open(context, QuizArgs)`, `ExamRoute.open(context, attemptId)`.
  A destination in another tab uses `context.jumpToTab(Route(…))`
  (`cross_tab.dart`), which switches the branch and builds the target tab's
  parents, so back walks them.
- **Arguments.** Ephemeral session data (which cards) travels as `extra`;
  anything that must survive process death, such as an exam attempt, is an id
  in the path.
- **Guards** (`route_guards.dart`): `/exam/*` and `/study` need an existing
  attempt or session, and `/onboarding/*` sends an enrolled learner to Today.
- **Back.** Android back pops, returns to Today from another tab root, and
  exits from Today; predictive back is on (`enableOnBackInvokedCallback`). iOS
  has the edge swipe on pushed routes.
- **Deep links** use the private `deutschplan://` scheme only:
  `deutschplan://today`, `…/learn/A2.1`, `…/word/<uid>?speak=1` and
  `…/exam/A1.2`. `resolveDeepLink` maps each to a location (the exam link opens
  the step's exams tab, not the runner). The reminder notification and the
  widget are the only senders, and a running exam is never interrupted by one.
- **Sheets and panes.** W1 (word detail) is shown over its opener without
  navigating: `WordRoute.open` calls `showWordDetail`, a sheet with medium and
  large detents on a phone (`Adaptive.showSheet`) and a right-hand pane on a
  tablet whose shortest side is 600 dp or more (`Adaptive.showPane`). The
  route `/word/:uid` is the deep link's full page.

`app_router_test.dart` parses the route table in `navigation.md`, so a new
route means a new row there in the same PR.

## Theming

Three modes share one layout and one component set; only tokens and the
surface renderer differ ([`theming.md`](../01-architecture/theming.md), ADR 11).

| Mode | Name | Character |
|---|---|---|
| Light | Paper & Ink | Cream paper, near-black ink, solid fills, hard 3 px offset shadows |
| Dark | Night Ink | Violet-black paper, light ink, the same fills lifted one step |
| Glass | Aurora Glass | Drifting colour blobs behind frosted translucent panels; buttons stay solid. A smoked dark variant follows the system's dark mode |

- **Tokens.** `AppTheme` exposes one `DpTokens` (`ThemeExtension`) per mode:
  colour, surface, typography, shape, spacing and motion. Widgets read
  `context.tokens`, never hex; a raw `Color(0x…)` outside `core/theme/` fails
  the architecture test. The gender colours (der, die, das) and verdict
  colours are fixed tokens, which is why there is no dynamic Material You
  colour (ADR 12). Material's `ColorScheme` fields are pinned too (ADR 21).
- **One surface.** Every card, sheet, header and bar is a
  `DpSurface(kind:)`, with kinds `card`, `cardStrong`, `bar` and `tint(colour)`.
  In light and dark it is a filled box with an outline and offset shadow; in
  glass it is a clipped `BackdropFilter` with a border and top highlight.
  Adding glass changed no screen file.
- **Glass budget and fallback.** At most three blur layers on screen (header,
  one panel, tab bar), so scrolling lists use `DpSurfaceKind.bar`.
  `GlassCapability` falls back to a 92 %-opaque tint below Android 12 (API
  31), after 2 s of missed frame budgets, or when the OS asks to reduce
  transparency. `AuroraBackdrop` drifts its blobs on 18–24 s loops, with the
  leading blob in the current tab's colour.
- **Contrast.** WCAG 2.2 AA in every mode, measured over the tokens by
  `test/core/theme/contrast_test.dart`; glass has its own darkened text
  palette, and progress tracks use `surface.track` for 3:1 (#437).
- **Reduce motion** gives cross-fades, no shake, no confetti and no aurora
  drift, read live from `MediaQuery.disableAnimationsOf`; iOS's Reduce Motion
  is folded into it at the app root (`stillOnReduceMotion`).

## Adaptive chrome

Flutter 3.47 moved Material and Cupertino into the standalone packages
`material_ui` and `cupertino_ui`, and the in-SDK libraries are deprecated. The
app started on the packages (ADR 6), so no file imports
`package:flutter/material.dart` or `cupertino.dart`.

All platform chrome goes through `app/lib/core/adaptive/adaptive.dart`:
Material 3 on Android and Cupertino on iOS (`AdaptiveChrome`), with identical
content components on both.

| Instead of | Use |
|---|---|
| `Scaffold`, `AppBar` | `AdaptiveScaffold` (with `AdaptiveBackButton`) |
| `Switch`, `SegmentedButton`, `TabBar` | `AdaptiveSwitch`, `AdaptiveSegmented`, `AdaptiveTabBar`; the shell uses `AdaptiveNavBar` |
| `showModalBottomSheet`, `AlertDialog`, `showTimePicker` | `Adaptive.showSheet`, `Adaptive.showPane`, `Adaptive.showConfirm`, `Adaptive.showTypedConfirm`, `Adaptive.showTimePickerFor` |
| `FilledButton`, `ElevatedButton`, `OutlinedButton`, `TextButton` | `DpButton` (primary, secondary, text) |
| `Chip`, `ActionChip`, `FilterChip` | `DpChip` (step, status, filter, streak, webLink) |

The same file provides `AdaptiveRefresh`, `AdaptiveTooltip` (an icon-only
control shows its name on a long press under Material chrome),
`AdaptiveTapTarget` (grows a small control's hit area and semantics node to
48 dp, or 44 pt under iOS chrome, without growing its layout) and
`AdaptiveToastScope`. A deliberate exception is marked
`// ponytail: allow-chrome`.

## Typography

Inter (Latin) and Noto Sans Bengali are bundled as variable fonts; every
style falls back to Noto Sans Bengali, because Inter has no Bangla glyphs
(`core/typography/app_fonts.dart`). Text is always drawn through
`core/typography/dp_text.dart`, never `Text`:

- `DpText(role:)` for copy, on the scale display 40 · headline 28 · title 20 ·
  bodyLarge 17 · body 15 · label 13 · caption 12. **Bangla runs are set one
  role larger** than the German or English beside them, per run, so a mixed
  string ("die Wohnung · ফ্ল্যাট") reads evenly.
- `DpHeadword` draws a German headword in its article's colour; `DpOneLine`
  cuts a title after its last whole word with "…"; `DpRuns` and
  `DpGermanRuns` draw runs in their own styles and voices.
- **Screen-reader languages.** German spans are tagged `de-DE` and Bangla
  `bn-BD` (`DpScript.spans`), so TalkBack and VoiceOver switch voices
  mid-string. The app's own copy is untagged.
- **Breaking long words.** German compounds break at syllables, by German's
  syllable rule rather than a dictionary (`DpScript.allowBreaks`, soft
  hyphens), only above 100 % text or when a word is wider than its line, and
  the line shows its "-" (`_Hyphenated`, since Flutter draws none at a soft
  hyphen). A Bangla word wider than its line first shrinks to 80 % in a run of
  its own (`DpScript.banglaShrink`) and only then breaks between aksharas
  (`DpScript.banglaBreaks`), never inside a conjunct and with no "-" (the
  owner's call, #522).
- **Large text.** Up to 200 % on every screen. Past 130 % (`DpScript.large`)
  side-by-side layouts stack; a fixed box grows by its text's factor with
  `DpScript.grow`, never `textScaler.scale(n)`, because Android 14+ scales text
  nonlinearly ([`accessibility-performance.md`](../01-architecture/accessibility-performance.md)).

## Localisation

- **Two UI languages**, English and Bangla, in `app_en.arb` (the template,
  where every key has an `@key` description naming its screen) and
  `app_bn.arb`: 972 keys each at v1.0.1. `flutter pub get` generates
  `AppLocalizations` into `lib/l10n/generated/` (gitignored).
- **The UI language and the meaning language are separate settings**
  (`ui_language`, `meaning_language` = en, bn or both). S2's first choice sets
  both; Settings changes each alone. The locale comes from `ui_language`, not
  the device.
- `appLocalizationsDelegates` in `main.dart` must be used by every
  `MaterialApp`, because `material_ui` and `cupertino_ui` look up their own
  localisation types; gen_l10n's default list left Bangla without them.
- **Bangla digits.** Every number in Bangla UI text is in Bangla digits (#425):
  an `int` placeholder is `decimalPattern`-formatted, and a number the code
  writes itself goes through `l10n.digits` (`lib/l10n/ui_digits.dart`). German
  content keeps its own digits, and Today's date is always German on purpose.
- Category names are course content and stay English in both UI languages
  (owner, #425).

## Platform integration

| Feature | How | Where |
|---|---|---|
| Home-screen widget | The app writes a JSON snapshot (step, remaining, total, minutes, word of the day, tomorrow, and its copy in the UI language) to `home_widget`'s store; a Glance widget draws it in two responsive sizes | `services/widget_snapshot.dart`, `android/…/widget/DeutschPlanWidget.kt`, [`notifications-widget.md`](../03-domain/notifications-widget.md) |
| Daily reminder | `flutter_local_notifications`, one inexact alarm per study day for the week ahead, rescheduled after a reboot; permission asked only when the reminder is switched on | `data/repositories/reminder_scheduler.dart`, `services/reminder_notifications.dart` |
| Background work | WorkManager unique work: `plan_pregenerate` (00:05, opens the day), `reminder_compose` (10 minutes before the reminder, writes or cancels its text) and `widget_refresh` (hourly). Each opens user.db on its own connection | `services/background_tasks.dart`, `services/background_work.dart` |
| Model downloads | `background_downloader`: resumable, Wi-Fi-only by default, a progress notification, checksum-verified before use | `services/model_downloads.dart`, `data/repositories/model_repository.dart`, `assets/models/manifest.json` |
| Voice | `SystemTts` (flutter_tts, `de-DE`) and `SupertonicTts` (ONNX Runtime, four sessions, clips cached on disk), chosen by `TtsService` with a fallback | `services/tts/`, [`tts.md`](../03-domain/tts.md) |
| Speaking exam | `record` for the recording, `just_audio` for playback | `services/exam_recorder.dart` |
| Export and import | `share_plus` and `file_picker` | `services/backup_files.dart`, `data/repositories/backup_repository.dart` |
| Orientation | A phone is locked portrait; a tablet (shortest side 600 dp or more) turns | `core/adaptive/orientation.dart` |
| Method channels | `deutschplan/glass` (can the device blur), `deutschplan/storage` (free and total space), `deutschplan/start` (report fully drawn) | `android/…/MainActivity.kt` |

Android specifics (app id `io.github.rahmatullah.deutschplan`, minSdk 26,
targetSdk 37, signing) are in [05-technical-reference](05-technical-reference.md)
and [07-operations](07-operations.md). The iOS code paths (Cupertino chrome,
BGTaskScheduler identifiers, the App Group for the widget) exist and the iOS
chrome has goldens, but iOS ships after v1.0 and those native parts are
unverified on a device.

## Privacy and offline

Everything except web-search links and model downloads works in airplane
mode, and no network call happens without a user action (BR-PRIV-01). There
are no accounts and no analytics (ADR 13): no `print`, no logging of content,
and a handled error worth a trace goes to `debugPrint`. user.db leaves the
phone only through the learner's own export.
