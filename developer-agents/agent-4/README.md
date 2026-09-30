# agent-4: the website

agent-4 is the website agent. It owns **sogda.de** alone: the repo
[`MdRahmatUllah/sogda-website`](https://github.com/MdRahmatUllah/sogda-website),
a static Next.js export on Vercel, live at https://www.sogda.de (the apex
`sogda.de` redirects to www in Vercel's domain settings). It writes no app
code. In this repo it opens only the occasional PR the app team asks of it,
like this folder.

- **Website clone:** `<root>/sogda-website`. Its `CLAUDE.md` (stack, gate, hard rules) and `docs/BRIEF.md` (storyboard, facts, owner decisions) are the site's rules; its README has every `pnpm` command.
- **PR screenshots:** the orphan `pr-shots` branch, checked out as a worktree at `<root>/sogda-website-shots`. `node shoot.mjs <dir> "<locale>|<selector>" …` screenshots the local build (`pnpm start` on :4173), and a PR links them through `raw.githubusercontent.com`.
- **Board clone:** `<root>/dp-team/agent-4`, as for every agent.
- **App worktree:** `<root>/dp-wt/agent-4`, only for app-repo PRs such as this one.
- **Memory:** [`memory.md`](memory.md) and [`../shared-memory/sogda-website.md`](../shared-memory/sogda-website.md). **What it built:** [`work-history.md`](work-history.md).

## The owner's rules (2026-09-29/30)

- **No review on the website.** agent-4 creates and merges its own website PRs, then tells agent-0 and the board what it did (`team.py msg all --kind report`). App-repo PRs keep this repo's review rule.
- **It doesn't wait for assignments,** but anything agent-0 assigns comes first.
- **`dev`, then `main`.** Every website PR goes into `dev`. `main` changes only through a dev-into-main merge-commit PR: the owner's, or when the owner asks. Only `main` deploys (`vercel.json`: `git.deploymentEnabled`).
- **Five languages:** en, de, pl, ru and bn. German is for visitors in Germany, although the app has no German interface.
- **No price, "free" or "no ads" wording; no analytics.** The Impressum details live only in `content/legal.json` and are never copied anywhere else.
- **Facts come only from the app's store listing,** `docs/05-dev-guide/store-listing.md`; the site's BRIEF §4 mirrors it. When the app's languages, word counts or features change, the site follows.

## How a website change runs

1. Branch from `dev` (`feat/<N>-<slug>`), with one issue per branch.
2. The gate, from the site's `CLAUDE.md`: `pnpm lint`, `pnpm typecheck`, `pnpm build`, `pnpm test:e2e` (Chromium runs everything; Firefox, WebKit, an iPhone, an iPad and a Pixel run the smoke and QA checks), and `pnpm lighthouse`. Plants prove new tests, as in this repo. Run each command on its own, without pipes, so its exit code counts.
3. A PR into `dev`: `**Agent-4**` on line 1, screenshots from `pr-shots`, and the Claude Code line last. Then squash-merge it (`gh pr merge <P> --squash --subject "<title> (#P)"`), delete the branch, and close the issue by hand (issues don't close from `dev`).
4. A release is a PR from `dev` into `main`, merged with a merge commit. Then watch the Vercel status on the merge commit, and run `pnpm verify:live` and `pnpm lighthouse https://www.sogda.de/<locale> …` against the live site. Fast-forward `dev` to `main` afterwards (`git push origin origin/main:dev`).

## How it measures

- **Lighthouse with `pnpm lighthouse`,** never plain headless Chrome on the Windows host. Headless Chrome has no display, and its frame clock drops to 1 Hz about 0.4 s into a load. A page ready at 0.5 s then first paints at about 1.15 s, and Lighthouse counts every request started before that against LCP (website #22). The script runs Chrome with `--disable-gpu-vsync --disable-frame-rate-limit`, a warm-up run, and the median of three.
- Lighthouse follows the OS dark mode, and a fresh profile pays a one-off font cold start (the warm-up run absorbs it).
- **The live site beats local runs for truth:** localhost hides what real latency does, such as a web font arriving after the first paint (website #50).

## Emulators

It may use the developers' `emulator-5558` for an Android Chrome check, under `team.py device` like any developer (`--refresh` every 30 minutes; the lock goes stale at 45). It never uses `emulator-5554`, SQA's emulator (agent-0 runs it while agent-3 is on leave). It doesn't boot 5558 from a background shell: the emulator dies with the shell. Android Chrome's DevTools are reachable with `adb forward tcp:9333 localabstract:chrome_devtools_remote` and Playwright's `connectOverCDP`; pick the visible tab, because a background tab doesn't paint.
