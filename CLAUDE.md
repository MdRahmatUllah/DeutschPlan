# DeutschPlan — read this first

An offline German course for Bangla and English speakers: Flutter (Android +
iOS), 12 steps A1.1 → C2.2, FSRS spaced repetition, mock exams, on-device
voice. M0–M3 are done; **M4–M7 are being built by three agents in parallel:
`agent-0` (the lead: the critical path, assignments, reviews), `agent-1` and
`agent-2`.** You are one of them. This page is the overview; `ONBOARDING.md` is the full
guide — read it once per identity, and whenever something here is unclear.

## Start every session like this

1. `python tools/team.py agents` — who is active. Take an **idle** identity:
   `python tools/team.py join agent-N` (run it in your own worktree; setting
   one up is `ONBOARDING.md` §2 — never work in the main checkout).
2. Read your memory — the board is cloned at `F:/appDevs/dp-team/agent-N/`
   (the main checkout's parent + `dp-team`; `join` prints it): `agents/agent-N.md`
   (Now, Next, Memory) and the project memory `MEMORY.md`.
3. `python tools/team.py status` — handoffs for you (act on them, then
   `team.py ack`), your work, what is in flight, what is ready.
4. Reviews first: an open review request from another agent beats new work.
5. Continue your `Now`, or `team.py claim <issue>` — the first ready issue in
   your lane (`PLAN.md` in the same folder).

While working: `team.py log -m "..."` at each real step, `team.py next -m`
when your plan changes. Ending: `team.py next`, `team.py note` (what your next
session must know), `team.py leave -m "..."`.

## Where the truth is

| What | Where |
|---|---|
| Behaviour (the source of truth: docs win over code) | `docs/` — `docs/README.md` indexes it; screens `docs/04-screens/`, engines `docs/03-domain/`, rules `docs/00-product/business-rules.md` (BR-*), data `docs/02-data/` |
| How it is built | `docs/01-architecture/` (structure, state, navigation, theming, a11y/perf), `docs/05-dev-guide/` (standards, testing, ADRs in `decisions.md`, release) |
| What it looks like | artboards `deutsch-plan-design-html/<canvas>/screens/*.html` (PNG: `docs/design/<canvas>/`), glass `deutsch-plan-v2-aurora-glass-html/…` |
| What to do, who does it | the `team` branch, cloned at `F:/appDevs/dp-team/<you>/`: `TASKS.md` (the task file + handoffs), `STATUS.md`, `PLAN.md`, `MEMORY.md`, `WORKLOG.md`, `agents/` |
| Each issue | GitHub issue (Goal, Design, Specification, Acceptance criteria, Dependencies) |

## Architecture in one screen

```
app/lib/
  main.dart, bootstrap.dart      startup: open user.db, attach content.db (schema c), load settings
  core/adaptive/                 ALL platform chrome: AdaptiveScaffold, AdaptiveBackButton, Adaptive.showSheet/showConfirm…
  core/components/               DpButton, DpChip, DpPill, DpSegmentedBar, DpErrorPanel, DpUmlautBar, DpToast…
  core/theme/                    DpTokens (context.tokens), DpSurface (the only surface), AuroraBackdrop, glass
  core/typography/dp_text.dart   DpText (never Text), DpHeadword, DpOneLine
  core/providers/app_providers.dart   every repository/service provider
  data/db/                       user_schema.drift (user.db DDL), *_queries.drift, content.drift, app_database.dart
  data/repositories/             the only layer that touches drift
  domain/                        pure Dart engines (no Flutter, no drift): fsrs, plan_engine, answer_check, …
  features/<group>/              screens; a screen's providers sit at the top of its file
  router/routes.dart             typed go_router routes + open()/instead() helpers; unbuilt screens = PlaceholderScreen
  l10n/app_en.arb, app_bn.arb    all copy (German course text comes from content.db)
```

`app/test/architecture_test.dart` enforces: no `package:flutter/material.dart`
(use `material_ui`); `domain/` pure; drift only in `data/`; no raw colours
outside `core/theme/`; no Material/Cupertino chrome outside `core/adaptive/`
(Scaffold, AppBar, TextButton, Chip, dialogs, sheets…); nothing writes to
content tables; no I/O in `build()`; `DateTime.now()` only via `clockProvider`;
navigation only through typed routes, their helpers and `context.jumpToTab`;
keepAlive providers must be listed in `docs/01-architecture/state-management.md`.
`test/l10n_test.dart` enforces ARB descriptions, bn coverage, no literals.

## Non-negotiables

- **Identity:** commits as `MdRahmatUllah <rahmat.ullah@infinitibit.com>` (the
  repo's `.git/config` sets it — never override); `gh` as `rahmat-ullah`.
  Commits end with your `Co-Authored-By:` line; PR bodies end with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **One issue → one branch `feat/<N>-<slug>` → one PR** (`Closes #N`), title
  `<type>(<scope>): <what> (#N)` (check it yourself: nothing else does). Squash
  merge.
- **GitHub CI is off** (the owner turned it off, 2026-09-24, #302: both
  workflows are disabled). **The local gate below is the only check.** Run it in
  full before you push, and again before you merge if `origin/main` moved.
  Never wait for, watch, re-run or re-enable a workflow. Push when ready for
  review, and batch fixes into one push.
- **Docs win.** A behaviour change updates `docs/` in the same PR. A spec gap
  you fill is named in the PR; a real decision goes to the owner
  (`team.py decision`) — never guess #239, #245, #283, #173, app ids, signing.
- **Tests carry FR/BR ids** in their names; every screen gets goldens (light,
  dark, glass × phone, tablet; plus iOS where chrome differs); every PR is
  proved by planted violations (`tools/plant.py`) — all caught.
- **Never `taskkill /IM flutter_tester.exe`** (it kills everyone's tests).
- **Emulators** (the owner, 2026-09-24): `emulator-5554` is agent-3's (SQA)
  alone. Never install on it or drive it. The developer agents share
  `emulator-5558`, `tools/device.py`'s default, under `team.py device` before any
  APK build or device check. `device.py` refuses 5554 to anyone but agent-3.
- Deliberate shortcuts are marked `// ponytail: <why + ceiling>`.

## The gate (from `app/` in your worktree; `make` is not installed)

```bash
dart analyze --fatal-infos                         # NO path args (ADR 18)
dart format --output=none --set-exit-if-changed .
python -m pytest ../tools/tests -q
flutter test --timeout 60s                         # includes goldens (Windows)
```

## One issue, start to finish (details: `ONBOARDING.md` §4)

claim → branch from `origin/main` → read the issue, its spec and artboards →
implement → tests → goldens (per file) + compare with `tools/artboard.py` →
gate → plants (`tools/plant.py`, all caught) → device check (release x64 APK,
`tools/device.py`, under `team.py device`) → commit → PR → `team.py review N
--pr P` → review (another agent, or a self-review pass) → fix in one push →
rebase on `origin/main` and re-run the gate if main moved →
`gh pr merge P --squash --subject "<title> (#P)"`
(no `--delete-branch`) → `git push origin --delete <branch>` →
`team.py done N --pr P -m "what others should know"` → next.

## Parallel work: where agents collide

ARB files, `routes.dart`, `test/features/today_fixtures.dart` (`todayStub`),
`app_router_test.dart`, `app_providers.dart`, the doc tables tests parse
(`navigation.md` routes, `state-management.md` providers, `user-database.md`
settings), shared components, goldens. Recipes: `ONBOARDING.md` §8. Take the
lock (`team.py lock`) for `user-db-schema`, `adr-number`, `pubspec`,
`ci-config`, `shared-look`.

Some docs are stale about tooling (fvm, make, alchemist, `tool/`…): the
corrections are in `ONBOARDING.md` §11 and issue #284.
