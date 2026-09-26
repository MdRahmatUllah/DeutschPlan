# Product overview

## One sentence

An exam-structured, fully offline German study plan from A1.1 to C2.2 that tells the learner exactly what to do today, revises what they have learned with spaced repetition, and lets them verify each step with generated mock exams — with meanings in English and Bangla.

## Who it is for

Adults learning German for work, study or residence. First audience: Bangla speakers (the Bangla pronunciation and meaning columns are the differentiator), then English speakers. Typical session is 10–20 minutes on a phone, often without signal.

## What it is not

- Not a game: no hearts, lives or leaderboards. Streaks exist but are quiet.
- Not a cloud service: no account, no server, no analytics. Network is used only for web-search links and optional model downloads.
- Not an official exam: mock exams are generated from course content and say so. Goethe and telc are named only to describe the target level.

## Content

| | Count |
| --- | --- |
| Words and phrases | 5,593 (A1 1,316 · A2 1,038 · B1 379 → to be expanded · B2 1,219 · C1 963 · C2 678) |
| Example sentences | 11,186 |
| Grammar topics | 182 |
| Course steps | 12 (A1.1 … C2.2) |

Content is authored in Excel (one workbook per tracker at the repository root; more may be added) and compiled into a read-only SQLite database that ships inside the app. See `02-data/content-pipeline.md`.

## Core loop

1. **Today** shows a ring (cards done / planned) and one primary action.
2. **Study session** runs Revise (FSRS-due words) → New today → Grammar due, one card at a time, rated Again / Hard / Good / Easy.
3. **Practice sentences** show learned words in context.
4. **Day complete** closes the day; missed items go to a **Backlog** with no penalty.
5. When ~90 % of a step is introduced, **mock exams** unlock; passing one badges the step.

## Themes

Three visual modes share identical layouts and behaviour: **Light** (Paper & Ink), **Dark** (Night Ink) and **Glass** (Aurora Glass). The learner picks one in Settings; the default follows the system light/dark setting. See `01-architecture/theming.md`.

## Platforms

Android 8.0+ (API 26) and iOS 16+. Tablet layouts are two-pane where documented. No web or desktop target in v1.

## Success measures

There is no telemetry. Success is judged by store reviews, support mail and the learner's own dashboard. Design targets: a returning learner reaches the first card in two taps and under three seconds; a 20-card day takes about 12 minutes.
