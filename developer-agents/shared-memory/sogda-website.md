---
name: sogda-website
description: "sogda.de, repo MdRahmatUllah/sogda-website, agent-4's alone: dev branch -> owner/agent-4 merges dev into main (only main deploys on Vercel); no review needed; state 2026-09-30"
metadata:
  type: project
---

The owner bought sogda.de (GoDaddy) and gave the whole website to **agent-4**: repo https://github.com/MdRahmatUllah/sogda-website, clone `<root>/sogda-website`, static Next.js on Vercel, live at https://www.sogda.de (www canonical; the apex redirects in Vercel's settings).

Owner rules (2026-09-30):
- agent-4 creates and merges its own PRs **without review**, and tells agent-0 and the board what it did. It doesn't wait for assignments; anything agent-0 assigns comes first.
- Every PR goes into `dev`. `main` changes only through a dev-into-main merge-commit PR: the owner's, or when the owner asks. Only `main` deploys.
- The site's languages are en, de, pl, ru and bn.
- No price or "free" wording, no analytics, and the Impressum details only in `content/legal.json`.

State 2026-09-30: all issues done except #45 (the Play link: blocked until the app is on Play, app #1123) and #52 (the owner's hand checks: a real phone, a screen reader, Safari). Live Lighthouse is 98–100 on every locale. The team's review of the site and its competitors runs on #54.

**Why:** the owner wants a state-of-the-art site that explains the app at a glance, and doesn't want to review it.

**How to apply:**
- Facts on the site come only from BRIEF §4, in sync with the app's `store-listing.md`.
- Measure Lighthouse with `pnpm lighthouse`, never plain headless Chrome on the Windows host: its 1 Hz frame clock fakes a ~1 s paint delay (the site's README).
- Screenshots for PRs go on the `pr-shots` branch (worktree `<root>/sogda-website-shots`, `shoot.mjs`).

Related: [[sogda-rename]], [[v1-release]].
