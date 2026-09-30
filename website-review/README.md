# Website review: sogda.de against its competitors (the owner, 2026-09-30)

> **Superseded:** the review runs on **sogda-website#55** (agent-0's thread, with its own split and template). This folder only keeps agent-1's raw material: `audit/agent-1.md`, and research for other agents' slices, which is offered as input on #55.

## The goal, in the owner's words
Review the website and its user experience, SEO, GEO, AEO "or anything". Check the competitors' websites. First research every competitor and record the findings; then analyse sogda.de in depth, "each and every small detail". When everyone is done, discuss how to do best, so the site is far better than the competitors. People should be interested just by looking at it, and in Google and in any AI search (Gemini, Claude, ChatGPT) the app's website should appear first. Find out how by discussing, then write a master plan.

## The process
1. **Research the competitors.** Each agent takes its share (below) and writes `competitors/<agent>.md`.
2. **Audit sogda.de.** Each agent writes `audit/<agent>.md` from its own angle, down to the small details.
3. **Wait** until every agent's two files are in, and post a one-line note on the board (`team.py msg all`).
4. **Discuss** in `discussion.md`: each agent adds its proposals and replies under the others', and disagreements are settled there.
5. **The master plan** goes in `master-plan.md`: one plan, with priorities, owners (the site is agent-4's), and how each step is measured.

## Proposed split (agent-0 may change it)
| Agent | Competitors | Also |
|---|---|---|
| agent-0 | Duolingo, Babbel, Busuu, Memrise | the release view: what the Play listing and the site must say together |
| agent-1 | German-specialist and exam-prep sites: DW Learn German, Goethe-Institut, Lingoda, Seedlang, Nicos Weg, Deutsch-Akademie, Clozemaster; German-learning sites for Bangla, Russian and Polish speakers | GEO/AEO: how AI engines choose and cite sources |
| agent-2 | SRS and AI tutors: Anki, Drops, Mondly, LingQ, Lingvist, Speak, Praktika | app-store optimisation (the Play listing as a search result) |
| agent-4 | German-market search ("Deutsch lernen App", "Goethe B1 Vorbereitung") | the deep technical audit of sogda.de (it built it) |

## Ground rules for proposals (the site's standing rules)
- **Facts** come only from the site's `BRIEF.md` §4, in sync with the app's `docs/05-dev-guide/store-listing.md`.
- **No** price or "free" wording, and **no** analytics.
- The Impressum details live only in `content/legal.json`.
- The site's languages are en, de, pl, ru and bn.
- The site is agent-4's: it builds and merges. Proposals go through the plan.
- **Evidence:** every competitor finding cites its URL and the date seen. Every audit finding cites the page, the locale and what was measured.
