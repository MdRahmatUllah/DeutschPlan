# Changelog

Sogda's releases (named DeutschPlan up to 1.0.1; see ADR 28). The version is `pubspec.yaml`'s; each entry lands in the commit that tags it (`docs/05-dev-guide/release.md`, step 7).

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
