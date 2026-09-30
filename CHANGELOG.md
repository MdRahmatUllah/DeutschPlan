# Changelog

Sogda's releases (named DeutschPlan up to 1.0.1; see ADR 28). The version is `pubspec.yaml`'s; each entry is dated in the commit that tags it (`docs/05-dev-guide/release.md`, step 7).

## [1.1.0] — not yet tagged

Polish and Russian, the first build as Sogda (`de.sogda.app`), and the production review's fixes.

### Added
- The app in Polish and Russian: every screen, notification and the home-screen widget (#1078, #1079).
- Meanings in English, Bangla, Russian or Polish: a first language, and an optional second shown under it, chosen in setup and in Settings (#1081).
- In Russian and Polish, each word's meaning and pronunciation, its example sentences, the grammar topics, interference tips for their speakers and the category names (#1083, #1084, #1119, #1128).
- The pronunciation guide follows the first meaning language: Bangla letters, Russian or Polish spelling, or an English respelling (#1082), with a one-line key to read it (#1122). English + Bangla keeps the Bangla guide while *Show Bangla pronunciation* is on (#1150).
- Search finds a word by its meaning in the chosen languages (#1121). Quizzes, mock exams, the placement check and the compare quiz ask in them, and a typed Polish or Russian answer may leave out its marks: `zolty` for *żółty*, `елка` for *ёлка* (#1120).

### Changed
- The app is Sogda: a new name, application id, icon, themed and notification icons, and splash (ADR 28).
- 5,069 words to learn: each word is taught once, and lesson notes and comparisons are listed, never studied.
- A smaller download: the arm64 APK went from 72.3 to 51.2 MB (ADR 29).
- Setup offers *Restore a backup* on its first page.
- Setup's meaning page opens on the app language: Русский for a Russian app, Polski for a Polish one, বাংলা + English for a Bangla one (#1156).

### Fixed
- About a hundred fixes from the production review: answers graded more fairly, a mock exam that keeps every answer through interruptions, backup and import checked and merged correctly, progress kept across content updates, deep links that never take over a running exam, screen-reader labels in Bangla, and no screen left hanging on a failed read.
- At large text in Russian and Polish, the rating buttons go to two rows rather than break a word, and a card's counter keeps "1 / 7" together (#1155).
- A comma inside a Russian or Polish meaning belongs to the phrase: "счёт, пожалуйста!" is one answer, not two (#775).

## [1.0.1] — 2026-09-26

Large text, in English and in Bangla.

### Fixed
- Typing with text past 130 %, or on a short phone at any size: the question stays in view above the field, a prompt that doesn't fit is one size smaller and then scrolls, and a verdict scrolls into view (L8, L12, T2's cloze, R2, Writing, the Reset dialog).
- The timed exam keeps its clock in view while typing, and it turns Coral near the end.
- A field's hint wraps whole instead of ending in "…" (R1, T2's cloze, L15's gap, R2).
- In Bangla at 200 %: the rating label, Backlog's day line, the navigator's numbers, the back button's label and the Speaking timer show whole.
- Phones stay portrait; tablets turn.

### Checked
- The 150 % and 200 % screen audit runs in Bangla as well as English, with the keyboard up on every screen with a field.

## [1.0.0] — 2026-09-26

The first release, on Android.

### The course
- 12 steps from A1.1 to C2.2: 5,593 words and 182 grammar topics, in English and Bangla, fully offline, with no account.
- Setup: the meaning language (which also sets the app's), a starting step or a short placement check, the daily pace and study days, a reminder, and the optional voice.
- Today's plan: revision by FSRS, new words, the week's grammar topic and practice sentences, with rest days, a backlog and a reminder only when something is due.
- Word cards, cloze cards after two Good or Easy ratings, word detail with examples and the pronunciation in Bangla letters, near-synonym comparisons, and words of the learner's own.
- Quizzes in six directions, grammar practice, and three mock exams per step (vocabulary, grammar, listening, writing, speaking) with results by section.
- Progress: the streak, twelve weeks of activity, whether the course is on track, and export and import of the learner's data.

### The app
- Light, dark and glass themes; English or Bangla; text up to 200 %; screen readers; reduce motion and transparency.
- The phone's German voice, or Supertonic (~400 MB, optional, on-device), with a notification while it downloads.
- An Android home-screen widget with a word to hear.
- Content updates that keep progress and say what changed.

### Not in 1.0.0
- iOS (the owner's decision, 2026-09-26).
- On-device translation: Hy-MT is off in every build (ADR 9); a licence-clean replacement is #533.
