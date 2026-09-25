# State management (Riverpod 3)

## Principles

- **Providers own state; widgets render it.** No `setState` for anything that outlives a gesture.
- **Codegen everywhere:** `@riverpod` functions and `@riverpod class … extends _$…` notifiers. Hand-written providers are not allowed (lint `riverpod_lint` enforces).
- **Database is the source of truth.** Screens watch drift `Stream`s exposed as `StreamProvider`s, so a rating in the study session updates Today's ring, the Learn bars and the streak without manual invalidation.
- **Auto-dispose by default.** Keep-alive only for: database, settings, TTS service, audio player, active session state.

## Provider map

| Provider | Type | Scope | Notes |
| --- | --- | --- | --- |
| `appDatabase` | keepAlive | app | Opens user.db, attaches content.db. |
| `settings` | keepAlive | app | The `SettingsRepository` that `bootstrap()` loaded, and overrides this with. `read(key)` answers from memory, typed by its `SettingKey`, and throws before `load()`. `write(key, value)` persists and fires `changes`, and a provider that follows a setting watches it with `switchOn`. |
| `clock` | keepAlive | app | `DateTime Function()`; overridden in tests for date logic. |
| `todayPlan` | autoDispose Future | Today | `PlanEngine.openDay(today)`. It watches `today`, so a new date re-plans and the same date plans nothing (FR-T1-05). The open rows, as they change, are `todayOpen`, over plan_items. Both are in `features/today/today_providers.dart`. |
| `studySession(args)` | keepAlive Notifier | study modal | Queue of cards, position, undo stack; survives app backgrounding; cleared on close. |
| `wordDetail(uid)` | autoDispose Stream | sheet | Word + state (watched) + examples + tip, with the meaning language and `show_pron_bn`. `wordHistory(uid)` watches `review_log` for the history caption. |
| `compareView(uid)` | autoDispose Stream | W2 | The set word and its members' columns (`ContentDao.compareSet`, read once), with the members' words watched for *Add all to today*. |
| `searchResults(query)` | autoDispose, debounced | Search | Runs in a drift background isolate. |
| `stepProgress` | Stream | Learn/Me | Aggregates per sub-level. |
| `grammarCourse` | autoDispose Future | L4, L15 | The course's German forms and example sentences, which grammar practice checks its wrong forms against and borrows *Pick the form*'s sentence from (#330). The provider disposes, but `loadCourseText` keeps the one it built in an `Expando` keyed by the open `AppDatabase`: about 17,000 rows are read once per app run, and the mocks' pool shares it. Built in `Isolate.run`. A read that fails gives `CourseText.none`. |
| `examRunService` | autoDispose | exam modal | L12's reads and writes. The timer, answers and flags are the runner's widget state, each answer and flag written as given and the clock every 10 s (#130). |
| `modelManager` | keepAlive AsyncNotifier | Me | Download tasks, statuses, storage. |
| `tts` | keepAlive | app | Engine selection + fallback. Every speaker speaks through it; until #153 it is `systemTts`. |
| `systemTts` | keepAlive | app | The phone's German voice (`SystemTts`): S2's preview and the fallback. One instance, because flutter_tts reports playback to the last one made. |
| `theme` | keepAlive Notifier | app | light/dark/glass + system following. |
| `languages` | keepAlive Notifier | app | `meaning_language` + `ui_language`; the root reads `ui_language` for the locale. S2 page 2 sets both from one choice; M3 sets each on its own. |
| `onboarding` | keepAlive Notifier | S2 | `OnboardingNotifier`: S2's plan values as a draft — step, pace, reminders — until the finish commits them in one transaction (#92). Kept alive because the pages come and go and FR-S2-02 wants the values on the way back. |
| `modelRepository` | keepAlive | app | Model files on disk and the parsed manifest, which it caches. |
| `notificationPermission` | keepAlive | app | Asks whether the app may post (FR-S2-05). Stateless; kept with the draft that asks it. |
| `modelDownloads` | keepAlive | app | The model download manager (FR-M4-01, #156): queues, pauses, resumes and retries a model's files with the platform downloader, follows its updates and records, and verifies before activating. `attach()` runs once at launch. |

## Patterns

- **Actions** are methods on notifiers (`ref.read(studySessionProvider.notifier).rate(4)`); widgets never write to repositories.
- **Undo**: `rate()` pushes an `UndoToken` (previous `word_state` row + review_log id); `undo()` restores the row and deletes the log entry within one transaction.
- **Refresh after midnight**: `today` doesn't tick. T1 invalidates it on app resume and on pull-to-refresh, and `todayPlan` watches it, so a new date re-runs `openDay`.
- **Errors**: `AsyncValue.error` renders the shared `ErrorPanel` with Retry; database write failures never lose the last saved card (writes are per-card transactions).
