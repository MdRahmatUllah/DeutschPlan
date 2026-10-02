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
| `/search/import` (`?arrival=`: the share's number, #1227) | D1 | pushed from R1; a share's arrival replaces the stack |
| `/me` | M1 | tab root (branch 3) |
| `/me/progress` | M2 | pushed |
| `/me/settings` | M3 | pushed |
| `/me/settings/reminder` | M5 | pushed |
| `/me/models` | M4 | pushed |
| `/me/export` | M6 | pushed |
| `/me/about` · `/me/about/licences` | M9 · M8 | pushed |
| `/study` (extra: `SessionArgs`) | T2 → T3 | full-screen modal (declared outside the shell's branches, so on the root navigator) |
| `/sentences` | T5 | full-screen modal |
| `/day-complete` (`?day=`: the plan day the session studied) | T6 | full-screen overlay |
| `/grammar-practice` (extra) | L15 | full-screen modal |
| `/quiz` (extra: `QuizArgs`) | L8 → L9 | full-screen modal |
| `/exam/:attemptId` | L12 → L13 → L14 | full-screen modal; swipe-dismiss disabled |
| `/word/:uid` | W1 | `WordRoute.open` shows it over the opener without navigating: a sheet on phones, a right-hand pane on tablets. The route is the deep link's full page (`?speak=1` plays the headword) |
| `/compare/:uid` | W2 | pushed |

Session args are passed as `extra` **only** for ephemeral data (which cards); anything that must survive process death (an exam attempt) is keyed by an id in the path.

## Behaviour rules

- **Tabs keep state**; re-tap scrolls to top, second re-tap pops to root.
- **Android back**: pops the current route; on a tab root returns to Today; on Today exits (predictive back enabled). **iOS**: edge swipe on pushed routes; none on tab roots.
- **Cross-tab jumps** (`T1 → L2`, `M1 → L10` …) switch the branch, then push, so back walks the target tab's natural parents.
- **Modals never switch tabs**; closing returns to the opener.
- **Guards**: `/exam/*` and `/study` require an existing session/attempt id; otherwise redirect to the tab root. `/onboarding/*` redirects to `/today` once enrolled.
- **Deep links**: `sogda://today`, `…/learn/A2.1`, `…/word/<uid>`, `…/exam/A1.2`, `…/import`. Local scheme only; also used by the reminder notification, the widget and Android's share sheet. `sogda://import` is "Share → Sogda" (#1227): Android's `ShareActivity` takes the shared text (`ACTION_SEND`, `text/plain`), keeps it in the process, and opens `MainActivity` as the widget does, in the app's own task, with this link alone: never the text on an intent, which another app or a web page could fill. D1 takes it once (`sogda/share`), and each share is numbered (`?arrival=`), as a *Pronounce* is, so a second one onto D1 is read too. A running exam is never taken over by a link: an exam pushed over its step and a tapped reminder included, since go_router's `onEnter` blocks any outside arrival while the top route is `/exam/…` and its attempt is still in progress, leaving the stack as it is (#676). A share held there says so in a toast, «Finish the exam first, then share it again.» (#1282): it comes from another app, so nothing else would show. Any other held arrival is silent, the learner already looking at the exam. Once it is submitted, its results (L13) and review (L14), drawn in the same route, hold nothing: a link and a tapped reminder navigate as anywhere else (`RouteGuards.isExamRunning`, #935). With nobody enrolled, a link opens setup from its first page: a cold start from a link (the widget, placed before the first launch) takes the link over bootstrap's first location, and would otherwise skip setup (#674). A learner mid-setup stays on their page, which `onEnter` blocks the arrival for too, since setup's pages are pushed and a redirect would rebuild the stack from page 1. A launch link that isn't a URI at all (`sogda://[::1/x`) is dropped, and the app opens where bootstrap says, rather than failing the start and every Retry (#747). A link that arrives while bootstrap still runs is kept by `BootstrapHost` and opened once the app is ready, under the same rules as any arrival, rather than thrown at the splash (#748). A link that parses but whose escape isn't UTF-8 (`sogda://word/%FF`, `sogda://today?x=%FF`) is read as `sogda://today`: at launch the app opens where bootstrap says, and a pushed one goes on as Today's from `BootstrapHost`, under the same rules as any arrival, rather than throwing in the router's redirect (#980). Any other URI is not the app's (#613): Android's `MainActivity` drops another app's intent data, and a `route` extra, before Flutter reads them, so the app opens as from the launcher; one that reaches the router all the same (a foreign scheme, or a host) lands on Today, however well its path matches a route, and never takes over a running exam.
