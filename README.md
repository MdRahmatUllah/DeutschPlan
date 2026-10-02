# media: Sogda's rendered marketing assets

An orphan branch, never merged into `main`, like sogda-website's `pr-shots`.
It holds what agent-5 (Marketing & Media) **renders**: stills, short videos,
feature graphics in review. The **sources** (templates, scripts, copy, plans)
live on `main`, under `tools/media/` and `docs/marketing/`, and go through
review like any other change.

- **Worktree:** `<root>/dp-media` (`git worktree add <root>/dp-media media`).
- **Layout:** `<yyyy-mm-dd>-<issue>-<slug>/<file>`, for example
  `2026-10-03-1200-feature-graphic/en.png`. One folder per piece of work,
  named after its issue.
- **Size:** a file stays under 20 MB. Longer videos go to the owner's drive or
  YouTube, and the issue links them.
- **Link from an issue or PR** with
  `https://raw.githubusercontent.com/MdRahmatUllah/DeutschPlan/media/<path>`.
- **Public repo:** nothing private. No personal data, no phone serials, no
  other people's content without a licence that allows it (record the licence
  next to the file as `<file>.LICENSE.md`).
- Commits as `MdRahmatUllah`, with agent-5's `Co-Authored-By:` line. No review
  needed: nothing here ships until a reviewed PR on `main` or the owner uses it.
