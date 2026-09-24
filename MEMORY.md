# Project memory

What every agent on DeutschPlan should know that the code and the docs don't
tell you. It collects the owner's rules, the decisions already made, and
lessons that cost time. Read it at the start of every session. Add to it
with `python tools/team.py remember <topic> -m "..."` when you learn
something the next agent would otherwise learn the hard way. It lands under
"Learned by the team" at the bottom.

## The owner's rules (binding)

- **Identity.** Every change that reaches GitHub is made as the owner: git author `MdRahmatUllah <rahmat.ullah@infinitibit.com>` (set in the repo's `.git/config` for every worktree), and `gh` is logged in as `rahmat-ullah`. The global git config has a different email: never commit outside this repo's config, and never override it.
- **Attribution.** Commit messages end with the `Co-Authored-By:` line your system prompt gives you. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **CI minutes.**
  - One PR per issue, with CI.
  - Push only when the branch is ready for review, not work in progress.
  - Batch review fixes into one push.
  - Cancel superseded runs with `gh run cancel <id>`.
  - Never run CI "just to see". The `team` branch never triggers CI.
- **Scope.** Build what the issue and its spec ask. A deliberate simplification is marked `// ponytail: <why, and the ceiling>` in the code and named in the PR.
- **Decisions.** Where the docs don't decide something and it is not a pure spec gap (see PLAN.md), it is the owner's call: `team.py decision`. Never guess #239, #245, #283, #173, signing, store or app-id questions.
- **Report a problem** in the app opens a pre-filled GitHub issue on MdRahmatUllah/DeutschPlan. Never invent an email address.
- **iOS** can't be built on this Windows machine. iOS-only work is written blind and marked "unverified" in the PR (the owner's call on #238).

## Decisions already made (don't reopen them)

- M3 L6 *Quiz* pushes the quiz route with `source: 'category'`. There is no standalone L7 screen: #116 built the quiz setup as L2's tiles, and #122 adds the custom sheet. It is gated at 10 learned words, the same floor as L2's tiles.
- Today counts grammar practised in L15 through `todayGrammarDueProvider`, which watches `grammar_state`. The plan's list stays the day's total (#119).
- On iOS, `AdaptiveScaffold` lays the bar out with `NavigationToolbar`, so a long title moves clear of the back label (#121). #280 still has to set iOS titles to 17 pt and add an ellipsis.
- `WordRow` caps the headword at one line with an ellipsis (content.db has phrases of up to 61 characters). The word card itself wraps.
- Value types are `@immutable` classes, records and `sealed` classes. freezed is a dependency but is not used, whatever coding-standards.md says.
- Screen providers are declared at the top of the screen or tab file (Today is the exception, with `today_providers.dart`).
- Report-a-problem uses GitHub issues (#100). Debug APKs don't fit on the emulator, so device checks use a release x64 APK.

## Technical lessons (each one cost at least an hour)

**drift**
- A raw `customStatement` does NOT notify stream watchers, and screens show stale data (bug #114). Use typed drift writes, `customUpdate(sql, updates: {db.table})`, or `customStatement` followed by `db.markTablesUpdated({...})`.
- Drift caches a just-closed query stream for a moment. A test that changes rows with a raw statement and then reads `.first` again can get the old rows. Notify the table.

**Riverpod**
- Drift-generated row classes (`Word`, `GrammarTopic`, ...) cannot be a provider's return type, not even inside a generic: riverpod_generator runs before drift has written them. Wrap them in your own class or a record.
- `import 'package:flutter_riverpod/misc.dart' show Override;`
- In a widget test that pumps twice, give the `ProviderScope` a `UniqueKey()`, or the second pump keeps the first overrides.

**Lint and the gate**
- `dart analyze --fatal-infos` with NO path arguments (ADR 18). With paths, or with `flutter analyze`, riverpod_lint silently turns off.
- Run pytest as well as flutter test. A green Flutter suite with a red pytest failed CI once (PR 241).

**Test fixtures**
- `todayStub()` (`app/test/features/today_fixtures.dart`) must stub every DB-watching screen provider. The router and golden tests pump the real routes with no database, so a new screen that isn't stubbed throws in tests you didn't touch.
- The widget test font renders every glyph 1 em wide. Layout tests about wrapping need short names, or they must pump at a known size (390×844 at dpr 3).

**Goldens**
- Regenerate them per file: `flutter test test/golden/<x>_golden_test.dart --update-goldens`. Never regenerate the whole suite.
- Goldens are generated on Windows, and CI verifies them on `windows-latest`.
- Compare against the artboard with `tools/artboard.py`, using your eyes.

**GitHub and CI**
- Watch the run named `CI`, not the `PR title` run.
- Before merging, check that your last push reached the PR: `gh api repos/MdRahmatUllah/DeutschPlan/pulls/N --jq .head.sha`. GitHub once didn't update a PR's head until it was closed and reopened.
- Merge with `gh pr merge N --squash --subject "<title> (#N)"` and **without** `--delete-branch`, which tries to check out `main` and aborts in a worktree. Then `git push origin --delete <branch>`.
- Merging and rebasing are separate steps. Check `gh pr view N --json state` = `MERGED` before you rebase anything on it.

**Windows shell**
- Never `taskkill /IM flutter_tester.exe`: it kills every agent's tests. Use `python tools/plant.py --kill-own-testers ...`, or stop only the processes whose command line holds your worktree path.
- A bash heredoc mangles `\\n` and quotes inside generated scripts. Write scripts and JSON with the editor/Write tool.
- Git Bash rewrites `/sdcard/...` into a Windows path. `tools/device.py` drives adb from Python, which avoids it; by hand, prefix with `MSYS_NO_PATHCONV=1`.
- The working tree is CRLF (`core.autocrlf=true`), and the "LF will be replaced by CRLF" warnings are noise. Match snippets on `\n` (as `tools/plant.py` does).

**Emulator** (one emulator, `emulator-5554`, Pixel_8, API 34)
- Hold `team.py device` for the whole check.
- Empty uiautomator dumps usually mean an ANR dialog: `adb reboot`.
- Remove `/sdcard/ui.xml` before each dump (`tools/device.py` does).
- Clock travel is device-wide, so restore it afterwards (`settings put global auto_time 1`).

**Content**
- content.db is committed and read-only (attached as schema `c`).
- The workbooks live only in the main checkout's `data/`, which is gitignored. `make content` can't run in a fresh worktree; only content issues need it (copy `data/` in).

**Planted violations**
- A plant that doesn't compile proves nothing: rewrite it.
- A test that still passes with its fix reverted is not a test: strengthen it until the plant is caught.

## Learned by the team

- **bootstrap** (2026-09-24, agent-1): the board, the guide (ONBOARDING.md, CLAUDE.md) and the tools (team.py, plant.py, artboard.py, device.py) were set up in PR "docs: the team onboarding guide".
- **gen** (2026-09-24, agent-0): After the gen sequence, git status shows app/lib/data/db/content_schema.drift as modified: mirror_content_schema.py rewrites it with LF line endings. git diff is empty; staging it changes nothing. Ignore it.
- **emulator** (2026-09-24, agent-2): Install failing with 'Requested internal only, but not enough space' (emulator /data ~93% full; tools/device.py only retries on INSUFFICIENT_STORAGE, and trim-caches frees nothing): adb shell pm uninstall -k com.example.deutschplan, then adb install the release APK — -k keeps the app's data, the same debug key reinstalls over it. Also: device.py labels needs PYTHONIOENCODING=utf-8.
- **decisions** (2026-09-24, agent-1): GitHub CI is being removed (owner, 2026-09-24): don't watch or wait for the run named CI before merging. The full local gate (analyze, format, pytest, flutter test with goldens) is the check; cancel any run that still starts.
