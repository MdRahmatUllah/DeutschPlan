# Changelog

Sogda's releases (named DeutschPlan up to 1.0.1; see ADR 28). The version is `pubspec.yaml`'s; each entry is dated in the commit that tags it (`docs/05-dev-guide/release.md`, step 7).

## [1.2.0] — unreleased

Learn from your own documents, 73 everyday words, and translation on the phone.

### Added
- **Learn from a document** (D1): paste or share a text from any app (#1227), photograph pages or pick photos, read on the phone by ML Kit with *Check the text* for a hard page (#1229), or choose a PDF, read from its text layer up to 30 pages, a scan sent to the photos (#1228). Over 20,000 characters or 30 pages, D2 says what was left out (#1320).
- **The words in your text** (D2): every word marked by its class, the new ones by level; a card to *Add*, mark *I know this*, or keep a word outside the course as your own; *Add all new* or your level at once, and a long press to add (#1230). An added word joins the plan, a few a day (BR-PLAN-11, #1272), with the sentence you met it in.
- **My documents** (D3): the documents you kept, to reopen, rename or delete with their photos (#1295). Settings sets the words a day, whether photos are kept, and when documents delete themselves (#1296).
- **Your own sentence** on the word's card, in W1 and as a cloze when it's short enough to gap (#1232).
- **73 everyday words** the course used but never taught on their own: Zeit, Name, Dank, zahlen, Raum, bereit, the bench *Bank* and more, with meanings and guides in all four languages (#1257). The course is now 5,142 words.
- **Rate Sogda on Google Play** in Me, and Play's own rating card once, as you leave your first passed mock exam (#1237).
- **Translation on the phone** with Hy-MT2, an optional download where the phone has the memory: W1's examples and T5's sentences (#154), and suggested meanings for a word outside the course, never filled in for you (#1233).

### Changed
- **A bigger download for the on-device reader:** arm64 52.15 → 66.24 MB. ML Kit's text recogniser and its Latin models +12.33 MB, pdfbox +0.40 MB once its CJK maps went (#1318), the code +1.20 MB (#1306).

### Fixed
- **D2's marks:**
  - a word's level is its lowest reading's, and readings that share a spelling say their step and meaning (#1294);
  - an ambiguous word is classed as it's drawn (#1310) and wears a «?» until you choose (#1333);
  - a split verb's particle is never «outside the course», and a letter's salutation isn't part of its first sentence (#1297);
  - the check and the «?» stay on their word's line, and a screen reader doesn't stop on bare spaces (#1339, #1344).
- **D2's notes:**
  - the switch reads once (#1309);
  - the bulk toast says what happened: all today, some, none, or waiting (#1311);
  - a word already in today's plan says today (#1315);
  - the cap note says why words wait at a cap of 0 or under the backlog pause (#1334), and counts the words already queued ahead (#1341).
- **Shares:**
  - a share during a running mock exam says it was held (#1282);
  - a share while a sheet is open lands on top (#1317).
- A failed model download can be deleted in Voice & translation, and leaves no part-files behind (#1265).

### Privacy
- A kept photo loses its metadata (location, camera, time) (BR-DOC-05, #1229), and the picker's and a shared PDF's copies are deleted once read (#1298, #1228).
- A shared file is taken only as another app's content, never a path to Sogda's own files (#1228).
- ML Kit's usage metrics are never sent (BR-PRIV-01): its DataTransport backend is removed from the app.

## [1.1.0] — 2026-10-02

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
- Search's *In sentences* shows each sentence in the learner's first meaning language, not always in English (#1188), and the search field's hint names German and the learner's own meaning languages (#1189).
- In Polish and Russian, decimals take a comma: the speech rate, points and sizes (#1197).
- Settings' retention and speech-rate rows say their value once to a screen reader (#1190).

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
