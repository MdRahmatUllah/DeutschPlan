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
| `settings` | keepAlive Notifier<Settings> | app | Backed by `settings` table; writes are synchronous then persisted. |
| `clock` | keepAlive | app | `DateTime Function()`; overridden in tests for date logic. |
| `todayPlan(date)` | AsyncNotifier family | Today | Calls `PlanEngine.openDay`; watches plan_items stream. |
| `studySession(args)` | keepAlive Notifier | study modal | Queue of cards, position, undo stack; survives app backgrounding; cleared on close. |
| `wordDetail(uid)` | autoDispose | sheet | Joins word + state + examples + tips. |
| `searchResults(query)` | autoDispose, debounced | Search | Runs in a drift background isolate. |
| `stepProgress` | Stream | Learn/Me | Aggregates per sub-level. |
| `examAttempt(id)` | keepAlive Notifier | exam modal | Timer, answers, flags; persisted per answer. |
| `modelManager` | keepAlive AsyncNotifier | Me | Download tasks, statuses, storage. |
| `tts` | keepAlive | app | Engine selection + fallback. |
| `theme` | keepAlive Notifier | app | light/dark/glass + system following. |
| `languages` | keepAlive Notifier | app | `meaning_language` + `ui_language`; the root reads `ui_language` for the locale. S2 page 2 sets both from one choice. |
| `onboarding` | keepAlive Notifier | S2 | `OnboardingNotifier`: S2's plan values as a draft — step, pace, reminders — until the finish commits them in one transaction (#92). Kept alive because the pages come and go and FR-S2-02 wants the values on the way back. |
| `modelRepository` | keepAlive | app | Model files on disk and the parsed manifest, which it caches. |
| `notificationPermission` | keepAlive | app | Asks whether the app may post (FR-S2-05). Stateless; kept with the draft that asks it. |
| `modelDownloads` | keepAlive | app | Queues a model's files with the platform downloader (FR-S2-06). #156 grows it into the manager. |

## Patterns

- **Actions** are methods on notifiers (`ref.read(studySessionProvider.notifier).rate(4)`); widgets never write to repositories.
- **Undo**: `rate()` pushes an `UndoToken` (previous `word_state` row + review_log id); `undo()` restores the row and deletes the log entry within one transaction.
- **Refresh after midnight**: `todayPlan` listens to `clock` ticks and app resume; if the date changed, it re-runs `openDay`.
- **Errors**: `AsyncValue.error` renders the shared `ErrorPanel` with Retry; database write failures never lose the last saved card (writes are per-card transactions).
