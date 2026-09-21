# Navigation

`go_router` 18 with typed routes (`go_router_builder`). Four tab stacks under a `StatefulShellRoute.indexedStack`; full-screen tasks are top-level routes pushed over the shell.

## Route table

| Path | Screen | Presentation |
| --- | --- | --- |
| `/splash` | S1 | replace on complete |
| `/onboarding/:page` | S2 (1–5) | full-screen flow |
| `/onboarding/placement` | S3 | full-screen flow |
| `/today` | T1 | tab root (branch 0) |
| `/today/backlog` | T4 | pushed |
| `/learn` | L1 | tab root (branch 1) |
| `/learn/step/:code` | L2 (`?tab=words|grammar|quiz|exams`) | pushed |
| `/learn/grammar` | L3 | pushed |
| `/learn/grammar/:uid` | L4 | pushed |
| `/learn/categories` | L5 | pushed |
| `/learn/categories/:id` | L6 | pushed |
| `/learn/exam/:step/intro/:seed` | L11 | pushed |
| `/search` | R1 | tab root (branch 2) |
| `/search/add` · `/search/add/:id` | R2 | pushed |
| `/me` | M1 | tab root (branch 3) |
| `/me/progress` | M2 | pushed |
| `/me/settings` | M3 | pushed |
| `/me/settings/reminder` | M5 | pushed |
| `/me/models` | M4 | pushed |
| `/me/export` | M6 | pushed |
| `/me/about` · `/me/about/licences` | M9 · M8 | pushed |
| `/study` (extra: `SessionArgs`) | T2 → T3 | full-screen modal (`parentNavigatorKey: root`) |
| `/sentences` | T5 | full-screen modal |
| `/day-complete` | T6 | full-screen overlay |
| `/grammar-practice` (extra) | L15 | full-screen modal |
| `/quiz` (extra: `QuizArgs`) | L8 → L9 | full-screen modal |
| `/exam/:attemptId` | L12 → L13 → L14 | full-screen modal; swipe-dismiss disabled |
| `/word/:uid` | W1 | sheet on phones (shown via `showModalBottomSheet` from lists); route only for deep links |
| `/compare/:uid` | W2 | pushed |

Session args are passed as `extra` **only** for ephemeral data (which cards); anything that must survive process death (an exam attempt) is keyed by an id in the path.

## Behaviour rules

- **Tabs keep state**; re-tap scrolls to top, second re-tap pops to root.
- **Android back**: pops the current route; on a tab root returns to Today; on Today exits (predictive back enabled). **iOS**: edge swipe on pushed routes; none on tab roots.
- **Cross-tab jumps** (`T1 → L2`, `M1 → L10` …) switch the branch, then push, so back walks the target tab's natural parents.
- **Modals never switch tabs**; closing returns to the opener.
- **Guards**: `/exam/*` and `/study` require an existing session/attempt id; otherwise redirect to the tab root. `/onboarding/*` redirects to `/today` once enrolled.
- **Deep links**: `deutschplan://today`, `…/learn/A2.1`, `…/word/<uid>`, `…/exam/A1.2`. Local scheme only; also used by the reminder notification and the widget.
