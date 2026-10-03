# The Sogda handbook

The whole project in one readable place: what the app is and why it exists,
what it does, how it is built, how its quality is assured, how it is released,
and where it is going. It is written for the owner, for a new developer or
agent, and for anyone deciding something about the product.

The handbook explains and connects. The detailed specifications in
[`docs/`](../README.md) remain the source of truth: **if the handbook and a
spec disagree, the spec wins**, and the handbook is the one to fix.

State described: **v1.2.0** as built on main by 2026-10-03 (`f5151b64`),
ahead of its release commit (#1235); the last tag is v1.1.0, 2026-10-02 on
`4106e393` (Android). Where a chapter gives a count or a measurement from an
earlier release, it names that release.

## The product in one page

Sogda is a complete German course on the phone, from the first word
(A1.1) to mastery (C2.2), for people who think in **Bangla** or **English**,
and since v1.1.0 in **Russian** or **Polish**.

- **The course.** 12 steps, 5,142 words and 182 grammar topics. Every meaning is in the learner's language (a first and an optional second), and so is the pronunciation guide: Bangla, Russian or Polish letters, or an English respelling.
- **The daily plan.** It decides each day's revision (scheduled by FSRS), the new words, the week's grammar topic and practice sentences. It respects rest days and keeps a backlog when a day is missed.
- **The practice.**
  - Word cards, and cloze cards once a word is known.
  - Word detail, with examples and near-synonym comparisons.
  - Quizzes in six directions and grammar practice.
  - Three mock exams per step, each with vocabulary, grammar, listening, writing and speaking sections.
- **Learn from your documents** (v1.2.0). A letter, a PDF, a photographed page or text shared from another app: Sogda marks the words the learner doesn't know yet, by level, and adds the ones they choose, each with the sentence it was met in. All of it is read on the phone.
- **The voice.** The phone's German voice, or Supertonic, an optional ~400 MB on-device voice.
- **Translation** (v1.2.0). Hy-MT2, an optional 1.1 GB download, translates on the phone: examples without a line in the learner's language, a word outside the course, a search with no result.
- **It works offline, with no account, no ads and no analytics.** Progress stays on the phone; export and import move it. The app itself sends nothing: it goes online only for a model download the learner starts, a web link the learner taps (Duden, DWDS and the others, FR-R1-06), *Report a problem*, which opens a pre-filled GitHub issue in the browser, and Me's *Rate Sogda on Google Play* (v1.2.0), which opens the Play listing.
- **It is built to be used by everyone.**
  - English, Bangla, Polish or Russian, light, dark and aurora-glass themes, and text up to 200 %, checked on every screen in every language with the keyboard up.
  - Screen readers, reduced motion and transparency.
  - A home-screen widget and daily reminders.

It is a Flutter app, released on Android. The iOS code paths exist and are
tested, but the iOS release waits for a Mac. It was built in eight
milestones (M0–M7) in six days (2026-09-21 to 2026-09-26): M0–M3 by one Claude Code
session working alone (101 PRs), and M4–M7 by a team of three developer agents
plus a dedicated SQA agent (see [`developer-agents/`](../../developer-agents/README.md)).
M8 brought the meaning languages (v1.1.0), and M9 the documents (v1.2.0).

## Chapters

| # | Chapter | For | What it answers |
|---|---|---|---|
| 1 | [Business](01-business.md) | the owner, partners | Who it is for, why offline, how it compares, the principles, the risks, where it can grow |
| 2 | [Features](02-features.md) | everyone | Everything a learner can do, screen by screen, with links to each screen's spec |
| 3 | [Capabilities](03-capabilities.md) | the owner, QA, partners | The non-functional side: offline, languages, accessibility, voice, performance, privacy, limits |
| 4 | [Architecture](04-architecture.md) | developers | The layers, startup, state, navigation, theming, platform integration, with diagrams |
| 5 | [Technical reference](05-technical-reference.md) | developers | The stack and versions, the databases, the content pipeline, every engine, components, tools, ADRs |
| 6 | [Quality](06-quality.md) | developers, QA | The gate, architecture tests, goldens and the text audit, plants, device checks, perf, SQA |
| 7 | [Operations](07-operations.md) | developers, the owner | Machine setup, everyday commands, building and releasing, signing, content updates, troubleshooting |
| 8 | [History and roadmap](08-history-and-roadmap.md) | everyone | How it was built, milestone by milestone, the decisions, and what comes next |

Beside the handbook:

- **The brand kit:** [`docs/sogda-brand-kit/`](../sogda-brand-kit/README.md): the name Sogda (ADR 28), the tiles mark (an "a" behind, an "Ä" in front), the colours, the type, and the icon, lockup and store files with their rules.
- **The team:** [`developer-agents/`](../../developer-agents/README.md), covering who builds the app, how each agent works, their memory, and the setup on a new device.
- **The working guides:** [`ONBOARDING.md`](../../ONBOARDING.md) (the full team process) and [`CLAUDE.md`](../../CLAUDE.md) (the one-page version).
- **The changes:** [`CHANGELOG.md`](../../CHANGELOG.md), one entry per release.

## Reading paths

- **Deciding about the product:** 1 → 2 → 3 → 8, then the brand kit.
- **Joining as a developer:** this page → 4 → 5 → 6 → 7, then `ONBOARDING.md` and your `developer-agents/agent-N/` folder.
- **Testing the app:** 2 → 3 → 6, then [`developer-agents/agent-3/`](../../developer-agents/agent-3/README.md).
- **Releasing:** 7 → [`release.md`](../05-dev-guide/release.md) → [`store-listing.md`](../05-dev-guide/store-listing.md).

## Keeping it true

A change that alters behaviour updates its spec in `docs/` in the same PR
(the project rule). When it changes something the handbook states, such as a
count, a feature, a rule or a tool, update the handbook in that PR too. At each
release, check the summary above and chapter 8.
