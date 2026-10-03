# 2 · Features

Everything a learner can do in Sogda v1.2.0, grouped the way the app
groups it: first run, Today and its study sessions, the word cards, word
detail and compare, Learn (the course, grammar, quizzes), the mock exams,
search and the learner's own words, the learner's own documents (v1.2.0), Me
(progress, settings, voice, data), translation, and the reminder and widget
that reach outside the app. Each feature names its screen id (S1, T2, L12,
D2…) and links to its spec, which has the full layout, functional
requirements (FR-*), business rules (BR-*) and states. Every screen in the
route table is built: none is a placeholder.

> The detailed specs in [`docs/`](../README.md) are the source of truth. If
> anything here disagrees with them, the spec wins and this page is wrong.

## The app at a glance

Four tabs, each with its own stack, and full-screen tasks pushed over them
([`navigation.md`](../01-architecture/navigation.md)):

| Tab | Root screen | What lives under it |
|---|---|---|
| **Today** | T1 Today | T4 Backlog; T2 study sessions, T3, T5 and T6 open over it |
| **Learn** | L1 Course map | L2 Step detail, L3 Grammar library, L4 Grammar topic, L5/L6 Categories, L11 Exam intro |
| **Search** | R1 Search | R2 Add / edit my word; D1 Learn from a document, D2 The words in your text, D3 My documents (v1.2.0) |
| **Me** | M1 Me | M2 Progress, M3 Settings, M4 Voice & translation, M5 Study days & reminder, M6 Export / import, M9 About, M8 Licences |

Full-screen tasks: S1–S3 (first run), T2 study session, T5 practice
sentences, T6 day complete, L15 grammar practice, L8 quiz, L12 exam (with
L13/L14 in the same route), W1 word detail (a sheet on phones, a side pane
on tablets) and W2 compare.

### Screen index

| ID | Screen | Spec |
|---|---|---|
| S1 | Splash | [`splash.md`](../04-screens/splash.md) |
| S2 | Onboarding (five pages) | [`onboarding.md`](../04-screens/onboarding.md) |
| S3 | Placement check and result | [`placement.md`](../04-screens/placement.md) |
| T1 | Today | [`today.md`](../04-screens/today.md) |
| T2 | Study session | [`study-session.md`](../04-screens/study-session.md), [`study-session-states.md`](../04-screens/study-session-states.md) |
| T3 | Session summary | [`session-summary.md`](../04-screens/session-summary.md) |
| T4 | Backlog | [`backlog.md`](../04-screens/backlog.md) |
| T5 | Practice sentences | [`practice-sentences.md`](../04-screens/practice-sentences.md) |
| T6 | Day complete | [`day-complete.md`](../04-screens/day-complete.md) |
| L1 | Learn · course map | [`learn.md`](../04-screens/learn.md) |
| L2 | Step detail (Words · Grammar · Quiz · Exams) | [`step-detail.md`](../04-screens/step-detail.md) |
| L3 | Grammar library | [`grammar-library.md`](../04-screens/grammar-library.md) |
| L4 | Grammar topic | [`grammar-topic.md`](../04-screens/grammar-topic.md) |
| L15 | Grammar practice | [`grammar-practice.md`](../04-screens/grammar-practice.md) |
| L5 / L6 | Categories · Category words | [`categories.md`](../04-screens/categories.md) |
| L7–L9 | Quiz setup · runner · result | [`quiz.md`](../04-screens/quiz.md) |
| L10 / L11 | Mock exam hub · Exam intro | [`exam-hub.md`](../04-screens/exam-hub.md) |
| L12 | Exam runner | [`exam-runner.md`](../04-screens/exam-runner.md), [`exam-writing-speaking.md`](../04-screens/exam-writing-speaking.md) |
| L13 / L14 | Exam results · review | [`exam-results.md`](../04-screens/exam-results.md) |
| R1 | Search | [`search.md`](../04-screens/search.md) |
| R2 | Add / edit my word | [`add-word.md`](../04-screens/add-word.md) |
| D1 | Learn from a document | [`doc-import.md`](../04-screens/doc-import.md) |
| D2 | The words in your text | [`doc-words.md`](../04-screens/doc-words.md) |
| D3 | My documents | [`my-documents.md`](../04-screens/my-documents.md) |
| W1 | Word detail | [`word-detail.md`](../04-screens/word-detail.md) |
| W2 | Compare words | [`compare.md`](../04-screens/compare.md) |
| M1 | Me | [`me.md`](../04-screens/me.md) |
| M2 | Progress detail | [`progress.md`](../04-screens/progress.md) |
| M3 | Settings | [`settings.md`](../04-screens/settings.md) |
| M4 | Model manager (Voice & translation) | [`model-manager.md`](../04-screens/model-manager.md) |
| M5 | Study days & reminder | [`reminder-days.md`](../04-screens/reminder-days.md) |
| M6 | Export / import | [`export-import.md`](../04-screens/export-import.md) |
| M7 | Reset | [`reset.md`](../04-screens/reset.md) |
| M8 / M9 | Licences · About & privacy | [`about-licences.md`](../04-screens/about-licences.md) |
| X1 | Home-screen widget | [`widget.md`](../04-screens/widget.md) |

The Me-tab screens M1–M9 share their letters with the milestones M0–M7. "M4"
here is the model manager, not the milestone.

## First run

### Splash · S1

The Sogda mark (the brand kit's tiles) and the name show while the app
opens its database and, on the first start
or after an app update with new content, copies the course into place. A
thin progress line appears only if this takes over 600 ms. If anything
fails, a full-screen error offers *Retry* and *Export progress* (*Share your
data file* when user.db itself won't open), never a blank screen. Notification and widget taps are honoured once the app is
ready. Spec: [`splash.md`](../04-screens/splash.md).

### Onboarding · S2

Five pages set the course up in about a minute, with safe defaults at every
step. *Skip* (from page 3) finishes with what the learner has chosen, and the defaults for what they never touched (#1011).

| Page | The learner chooses |
|---|---|
| 1 Welcome | The app language (English, বাংলা, Polski, Русский; the phone's by default when Sogda speaks it), then three promises: offline, 12 exam-structured steps, progress stays on the phone |
| 2 Meaning language | A first language from the course's (English, বাংলা, Русский, Polski), and an optional second shown under it (*Also show*, v1.1.0). The Bangla pronunciation line is on while Bangla is chosen; the app language stays as page 1 set it |
| 3 Starting point | One of the 12 steps (A1.1 pre-selected), or *Not sure? Take a 3-minute check* (S3) |
| 4 Daily pace | New words a day (3–30; presets Relaxed 5, Steady 7, Intensive 15) with a live estimate ("A1.1 takes about 91 days at 7 words a day", from `courseDays`), revisions a day (10), and the study days |
| 5 Reminder & voice | A daily reminder (off by default, 19:30) and the optional Supertonic voice: *Download now* or *Later*, with a "Guten Tag!" sample in the phone's voice |

Finishing opens Today with the first day planned and a one-time coach mark
on the start button. Settings → *Restart setup* runs it again without the
welcome page, keeping progress. Spec: [`onboarding.md`](../04-screens/onboarding.md).

### Placement check · S3

For a learner who already knows some German: an adaptive check of up to 20
questions (a word's meaning, its article, or a sentence gap), starting at
A1.1. Two right answers in a row move up a step, two wrong move down, and it
can stop after 8 once the level holds. The result suggests a step with a
breakdown by area. Nothing is written: skipped steps stay browsable and are
not marked as known. Spec: [`placement.md`](../04-screens/placement.md).

## Today and the daily loop

### Today · T1

One glance answers "what do I do now, and how long will it take":

- **The ring:** cards done of today's total, with a time estimate (25 s per
  revision, 45 s per new word, 60 s per grammar topic, 40 s per sentence,
  replaced by the learner's own median timings after 7 sessions: BR-PLAN-09).
- **Today's blocks:** Revise (10 by default), New today (7 by default, from
  the active step in teaching order, plus words from the learner's
  documents, 5 a day by default, named apart: "7 new · {category} · 5 from
  your documents", #1280), Backlog (when there is one), Grammar
  due (when a topic is due) and Practice sentences (3 by default). Each
  block opens its own work: Revise or New a session of that block alone,
  Backlog T4, Grammar due L15, Sentences T5.
- **One primary button**, whose label follows the day: *Start today · n
  cards* → *Continue · n left* → *Practice sentences · n* → *Review backlog ·
  n* → *All done — see you tomorrow*.
- **At most one contextual card**, the first that applies: step complete,
  course updated, a backlog pause offer, exams unlocked, a better voice to
  download, course complete.
- **"Grammar this week"**: the active step's next topic with a one-line rule.
- The header has the date in German, a greeting with the learner's name if
  given, the streak and a gear for Settings.

Special days: an **all-done** day shows tomorrow's preview; a **rest day**
(a weekday switched off) has no new words and no backlog growth, keeps the
streak, and offers optional revision; a **finished course** switches to
revision only. Spec: [`today.md`](../04-screens/today.md). Rules:
BR-PLAN-01…10 in [`business-rules.md`](../00-product/business-rules.md).

### Study session · T2

The focused loop: hear the word, think of its meaning, reveal, rate. A
session runs its blocks in a fixed order (Revise → New → Grammar), with a 1 s
banner between blocks and a progress strip per block. Progress is saved
after every card, so closing, backgrounding or a crash resumes on the same
card. The card itself is the next section. Spec:
[`study-session.md`](../04-screens/study-session.md).

### Session summary · T3

A sheet at the end of a session: "Gut gemacht!", cards and minutes, the
ratings given, up to five "words to watch" (rated Again) with play buttons,
and the next useful step: the day's next open block, then the backlog, and
always *Done for now*. Spec: [`session-summary.md`](../04-screens/session-summary.md).

### Backlog · T4

New words from missed or skipped days wait here, grouped by their original
day, "without a deadline". Nothing is ever shown as overdue or in red. The
learner can *Study all*, *Study this day*, or act on one word (*Mark known*,
*Suspend*, *Remove from course*), and can pause new words until the backlog
is clear (revisions continue). Today offers that pause when the backlog is
over three days of new words. Spec: [`backlog.md`](../04-screens/backlog.md).

### Practice sentences · T5

Example sentences built from words the learner already knows (3 a day by
default, stable for the day, not repeated within 14 days). The learner hears
each one (long-press for slow), can show its translation (in the first
meaning language, English where the course has none), taps any word for its
course meaning, and rates it *Understood*, *Partly* or *Not yet*. A word the
course doesn't have shows a Duden link, and with translation on, Hy-MT2's
translation above it (FR-T5-03). *Not yet* brings the word back sooner (it
rates it Hard). Spec:
[`practice-sentences.md`](../04-screens/practice-sentences.md).

### Day complete · T6

A short reward, once a day, when the last open item is done: the ring
completes, paper-cut confetti falls once, "Tag geschafft!", the streak, and
tomorrow's numbers. No share prompts, ads or upsells; with reduce motion, no
confetti. Spec: [`day-complete.md`](../04-screens/day-complete.md).

## Word cards and cloze

What a card in T2 offers ([`study-session.md`](../04-screens/study-session.md),
[`study-session-states.md`](../04-screens/study-session-states.md)):

- **Front:** the article in its gender colour (der blue, die pink, das
  green, and always printed, so colour is never the only cue), the headword,
  its part of speech and forms, the pronunciation in the first meaning
  language's letters (Bangla, Russian or Polish, or an English respelling;
  Bangla's a setting), with a one-line key to read it (v1.1.0), and a large
  speaker.
- **Back:** the meanings in the learner's languages, the first then the
  second, examples with play buttons and translations (in Russian or Polish
  for those learners, English otherwise), collocations, register notes, and an
  interference tip when the word has one ("bekommen = to get, not 'to
  become'"). A meaning a course update changed in the last 7 days wears an
  *Updated* chip.
- **Rating:** Again · Hard · Good · Easy, each showing the interval FSRS
  would give ("Good 8 d"). A 4 s *Undo* reverts a rating fully.
- **New words** add *I know it* (rated Easy) and *Skip → backlog*.
- **Cloze cards:** after two Good or Easy ratings in a row, a word's card
  becomes a sentence with the word blanked, to type with the umlaut row's
  help. A rating below Good turns it back (BR-FSRS-06). The learner can pick
  either card for a word in W1, and the choice then sticks.
- **Swipe to rate** (left Again, right Good) is an option in Settings; the
  buttons stay.
- **Voice:** the headword plays as the card appears (a setting), the first
  example optionally on reveal, long-press a speaker for 0.75×, long-press
  the headword to copy it.
- **The ⋯ menu:** auto-play, speech speed, the word's details (W1), and
  *Report a problem*, which opens a pre-filled GitHub issue page.
- **The learner's own words** come up as revisions like any word, with a *My
  word* chip.

## Word detail and compare

### Word detail · W1

Everything about one word, over whatever screen opened it, returning to
exactly where it was: a sheet on phones, a 420 dp side pane on tablets, a
full page from a link. It shows the gendered header with its step and status
chips, the forms and Bangla pronunciation, the meanings, every example with
play and translation, collocations, register, the interference tip, and the
review history ("Next review in 8 days · reviewed 5 times · last: Good").

The actions, each with *Undo*: *Add to today* (a word not started yet),
*Mark known*, *Suspend* / *Resume*, *Reset word*, *Copy*, the plain or cloze
card, *Compare a synonym set* where there is one, and web chips for Duden,
DWDS and Wiktionary. With translation on, *Translate* fills in the examples
that have no line in the first meaning language (FR-W1-05): today that is a
Bangla learner's, since the course has no Bangla example lines. Spec:
[`word-detail.md`](../04-screens/word-detail.md).

### Compare words · W2

Near-synonym sets ("Grund / Ursache / Anlass") side by side: meaning,
register, the case or preposition each takes, an example with play, and
"use it when". The first column stays while the others scroll sideways (all
show on a tablet). *Quiz these* builds a short which-word-fits quiz from the
members' sentences, and *Add all to today* plans the members not started
yet. Spec: [`compare.md`](../04-screens/compare.md).

## Learn

### Course map · L1

The whole course as a path: six level bands with two step tiles each, every
tile showing its words, grammar topics, progress and badge (*Passed*,
*Current*, *Exams unlocked*, or a lock). Every step can be browsed at any
time; new words come only from the active step (BR-COURSE-04). The current
tile has *Study*, and cards lead to the grammar library and the word
categories. Spec: [`learn.md`](../04-screens/learn.md).

### Step detail · L2

One step on four inner tabs, with a header giving its size and how long it
will take at the learner's pace:

- **Words:** filter by status (To do, Learning, Done) and category; a banner
  offers to start this step if it isn't the active one.
- **Grammar:** the step's topics in teaching order, each with its rule
  preview and when it is next due; *Practise all due*.
- **Quiz:** Quick (10), Standard (20), Long (30), Forms, and Custom (the L7
  sheet), with the last quiz's score. It opens once 10 of the step's words
  are learned.
- **Exams:** the mock exam hub (L10).

Spec: [`step-detail.md`](../04-screens/step-detail.md).

### Grammar library · L3 and grammar topic · L4

All 182 topics by level, filterable by *Not learned yet* and *Due*
([`grammar-library.md`](../04-screens/grammar-library.md)). A topic page
([`grammar-topic.md`](../04-screens/grammar-topic.md)) has the rule, its
examples with play and translation, a *Watch out* note, *Practise this rule*
and *Mark as learned* (which puts it on the revision schedule), and links to
the previous and next topics of the step.

### Grammar practice · L15

Three to five items generated from a topic's rule and examples: gap fill,
pick the form, spot the error, order the sentence, and rule recall (C1/C2).
Feedback is immediate, with the rule on a wrong answer. The set is rated as a
whole into the topic's own FSRS schedule: all right is Good, one wrong Hard,
more Again (BR-FSRS-05). Due topics also come inline in the day's session.
Spec: [`grammar-practice.md`](../04-screens/grammar-practice.md); the
generator: [`grammar-practice.md`](../03-domain/grammar-practice.md).

### Categories · L5 and category words · L6

The vocabulary by topic across all 12 steps (159 categories), each with its
word count and progress; a category's words sorted by step, then frequency,
with a level filter and a *Quiz* button. Spec:
[`categories.md`](../04-screens/categories.md).

## Quizzes · L7, L8, L9

Quick practice from learned words, which doubles as revision: the words the
learner is most likely to forget are asked most
([`quiz-engine.md`](../03-domain/quiz-engine.md)).

- **Setup (L7):** from L2's tiles, or the custom sheet: direction (DE → EN,
  DE → বাংলা, EN → DE, Articles, Listening, Mixed), length (10, 20, 30),
  source (this step's learned words, all learned words, or a category) and an
  optional 15 s timer. The direction starts on the learner's meaning
  language. A category opens once 10 of its words are learned.
- **Runner (L8):** typed answers with the umlaut row, der/die/das buttons,
  four tiles for DE → বাংলা, a listening item, and word forms ("Perfekt of
  …"). Feedback after each answer: *Correct*, *Almost* (a one-letter typo
  in a word of six letters or more, worth half a point), *Article: die, not
  der*, or the right answer. Wrong answers are asked once more at the end.
- **Result (L9):** the score, time, and the mistakes with what was typed;
  *Retry mistakes*, *Add mistakes to revision*, *Done*.
- Every answer also rates the word into FSRS: right is Good, almost Hard,
  wrong Again (BR-FSRS-03).
- **Quizzes also open from** a category (L6) and a compare set (W2).
  All-learned quizzes also ask the learner's own words when Settings' *My
  words in quizzes* is on.

Answer rules (umlauts as ä/ae/a, synonyms, articles): BR-ANS-01…04 and
[`answer-checking.md`](../03-domain/answer-checking.md). Spec:
[`quiz.md`](../04-screens/quiz.md).

## Mock exams · L10–L14

Exam-style tests that verify a step. They are generated from the step's own
words and grammar, and say that they are not official Goethe or telc papers
([`exam-generator.md`](../03-domain/exam-generator.md)).

- **Hub (L10):** the exams unlock when 90 % of the step's words have been
  introduced (a setting, 50–100 %). Until then a card shows how far there is
  to go. Unlocked, it offers three mocks per step, each drawn with its own
  seed so that no item repeats across a step's three (steps with few grammar
  topics reuse one or two, and say so), with the best score and the attempts
  per mock, and *Resume* for an attempt that was interrupted.
- **Intro (L11):** the paper's sections and counts, the rules (no feedback
  until the end, flag and come back, the timer can pause) and a *Timer on*
  switch.
- **The paper (L12):** Vocabulary 10 · Reverse 8 · Articles 6 · Word forms
  4 · Gap fill 6 · Grammar 4 · Listening 2, then a Writing task and a
  Speaking task: 40 questions, 48 points, about 20 minutes, the clock turning
  Coral in the last 2 minutes. Every answer is saved as it is given, so a
  crash or a kill resumes the attempt. A navigator grid jumps to any
  question and shows the answered, flagged and empty ones. Pause opens the
  leave dialog and stops the clock: *Keep going* runs it again, *Leave* ends
  the attempt unfinished, counted without a score. With listening switched
  off in Settings, Vocabulary and Reverse take its two questions.
- **Writing:** a task for the level on one of the step's categories ("Write
  an email to a friend about …"), with 10 target words that light up as they
  are used, a live word count against the level's minimum (A1 30 up to C2
  250) and the connectors found. The app gives a point for 6+ target words
  and a point for the minimum length; the learner's two rubric ticks (task
  covered, structure) add a point each, so the task is worth 4 (BR-EXAM-03).
  Until #597 the ticks were worth half a point and Writing topped out at 3.
- **Speaking:** a spoken task of 60, 90 or 120 seconds by level, recorded on
  the phone (one retake), played back, and self-assessed on four rubric
  points. The recording never leaves the phone. If the microphone is
  refused, the task can be skipped.
- **Results (L13):** "Bestanden!" or "Noch nicht", the percentage (rounded
  down, so a fail never reads as the pass mark), the points, a comparison
  with the previous attempt, and the score by section. The Writing and
  Speaking rubrics can be ticked here afterwards. *Add missed words to
  revision*, *Try another mock*, *Back to step*.
- **Review (L14):** every question with the answer given and the right one,
  filterable by *Wrong only* and *Flagged*, with an explanation (the word's
  example, or the grammar rule) and *Open word* / *See rule*.
- Passing any mock marks the step *Passed* (pass mark 60 %, a setting from
  50 to 90 %).
- **The first pass** (v1.2.0) asks Google Play for its review card as the
  learner leaves L13, once ever and with no question before it; Play decides
  whether it shows (FR-L13-04, BR-RATE-01).

Specs: [`exam-hub.md`](../04-screens/exam-hub.md),
[`exam-runner.md`](../04-screens/exam-runner.md),
[`exam-writing-speaking.md`](../04-screens/exam-writing-speaking.md),
[`exam-results.md`](../04-screens/exam-results.md). Rules: BR-EXAM-01…06.

## Search and my words

### Search · R1

Look up any word, in German, English or Bangla, or by its meaning in the
learner's Russian or Polish (v1.1.0), across the whole course.
Results come in four groups: **Exact match**, **Starts with**, **Similar
words** (typos tolerated: "strase" finds Straße) and **In sentences**, with
the match highlighted. Each row plays the word without opening it. Chips
narrow the results by status and step, and a search from a step (L2, L6)
starts filtered to it.

- **Idle:** the last 10 searches, the learner's own words, *Add a word I
  found*, and *Learn from a document* under it (D1, or D3 once a document is
  kept).
- **No results:** says the course has none spelled like it, offers the web
  chips large, and *Add "…" as my word*. With translation on, *Translate
  «…»* shows the query from German into the first meaning language and from
  it into German, since a query can be either.
- **Web chips:** Duden, DWDS, Wiktionary, Linguee and Google open in an
  in-app browser. These chips (and W1's), T5's Duden link, *Report a
  problem*, About's *Contact* and Me's *Rate Sogda on Google Play* are, with
  a model download, the only ways the app goes online.

Spec: [`search.md`](../04-screens/search.md); the engine:
[`search.md`](../03-domain/search.md).

### Add / edit my word · R2

Save words met in daily life: article, German (with the umlaut row), meaning,
where it was seen, and an optional example. A live check says when the course
already has the word, with *Open* and *Log it* (one more real-life
sighting). *Save*, or *Save and add to revision*, which puts it on the FSRS
schedule from today like any course word. Saved words can be edited or
deleted. They appear in all-learned quizzes when the setting is on, and never
in exams. Opened from D2's *Add as my word*, it starts with the word's
German, its sentence as the example and the document's title as where it
was seen (FR-D2-05). Spec: [`add-word.md`](../04-screens/add-word.md).

## Learn from your documents (v1.2.0)

The learner brings the German they meet, and Sogda finds the words they
don't know yet and adds the ones they choose, each with the sentence it came
in (epic #1219). Everything happens on the phone (BR-DOC-01). The engine is
[`document-matcher.md`](../03-domain/document-matcher.md); the rules are
BR-DOC-01…08 and BR-PLAN-11 in
[`business-rules.md`](../00-product/business-rules.md). The feature is free,
with no limits (BR-DOC-08).

### Learn from a document · D1

Four large choices, under "Everything stays on this phone":

- **Take photos:** the phone's camera app, a page at a time, the pages
  listed with *Done* and *Add a page*, up to 30.
- **Choose images:** the system photo picker.
- **Choose a PDF:** its text layer, up to 30 pages.
- **Paste text:** the clipboard, shown in an editable box first.

It opens from R1 (*Learn from a document*), D3's *New document*, and
**Android's share sheet**: "Share → Sogda" with text, a PDF or images opens
D1 straight into processing, even mid-session. A running exam is never
interrupted: a toast says «Finish the exam first, then share it again.»
(#1282).

- **Processing** shows "Reading page 2 of 4…", then "Finding your words…",
  with *Cancel*, which saves nothing.
- **Photos** are read on the phone by ML Kit's text recogniser, its model
  bundled. A page read with little confidence (below 0.7 on average, FR-D1-03)
  opens *Check the text*: the
  text, editable, with the doubtful words marked, and *Take again* or
  *Continue*. What the learner leaves is the page's text.
- **A PDF** is read page by page. One with no text layer is a scan, and D1
  offers *Choose images* instead; one with a password asks the learner to
  open it elsewhere and copy its text, since Sogda asks for no password.
- **The limits** are 30 pages or 20,000 characters: the rest is cut at a
  sentence end, and the learner is told on D1 and again on D2 (BR-DOC-02,
  #1320).
- **Not German?** When under half of its words read as German (course
  words, stop words, compounds of course words), it warns "This doesn't look
  like German", with *Continue anyway* (FR-D1-04).
- **The title** is the text's first line with a letter in it, passing over
  a letter's salutation, or "Text of 2 Oct"; D2 can change it.

Spec: [`doc-import.md`](../04-screens/doc-import.md).

### The words in your text · D2

The text as it was read, with every word marked by its class (BR-DOC-03):

- **New in the course:** a soft fill in its level's colour and an ink
  underline, so the level is never shown by colour alone.
- **Probably known:** a word of an earlier step that no plan ever held,
  dimmed while *Show words I probably know* is on.
- **Outside the course:** a dotted underline.
- **Mine:** a small "My word" badge.
- Known words and stop words stay plain. A word with two readings
  («Weg» or «weg») wears a "?" and takes its lowest reading's level.

The header has the title, the counts ("12 new · 4 probably known · 3
outside the course") and the switch. Tapping a word opens its **mini card**
(a sheet, or a side pane on a tablet): the headword with its article and
plural or its verb forms, the level, the meanings in the learner's
languages, and the document's sentence with the word in bold.

- **Add** puts a course word in the document queue with its sentence; the
  toast says when it starts: "Added der Termin: you'll learn it today", or
  "… from Thursday" (FR-D2-02).
- **I know this** is W1's *Mark known* (rated Easy), with its *Undo*;
  **Ignore** takes the mark away for this visit; **Open** is W1.
- **A word outside the course** offers *Add as my word* (R2, pre-filled), a
  compound's parts as a hint ("Nebenkosten + Abrechnung"), and Hy-MT2's
  meaning, labelled machine-translated. With no meaning, a link to M4's
  download shows only while Hy-MT2 isn't on the phone and the phone has the
  memory for it (#1300).
  Hy-MT2's meanings are suggestions to tap, never a pre-filled meaning
  (#1278); they come with #1233.
- **A word already mine** keeps the new sentence with it (*Keep this
  sentence*), never a second word.
- **A long press** on a new word adds it at once, a sighted shortcut; a
  screen reader adds from the card.
- **The bulk bar:** *Add my level*, *Add my level and one above* and *Add
  all new*, each with its count, and the cap's note ("5 a day: the other 7
  start tomorrow or later"). An ambiguous word is in no bulk action. It is
  pinned at the foot; past 130 % text it comes after the text, which keeps
  the screen (#1353).

A document reopened from D3 is matched again, so its marks follow what the
learner has learnt since, and what was added stays added (FR-D2-07). With
nothing new: "You know every word in this text". Spec:
[`doc-words.md`](../04-screens/doc-words.md).

### My documents · D3

The kept documents, newest first: each with its title, a source icon
(photo, PDF, text), the date and "12 words added". A row opens D2; its menu
has *Rename* and *Delete*, which asks first ("Delete 'Letter of 2 Oct'? The
words you added stay.") and removes the document, its photos and what it
found, never the words or their sentences (FR-D3-02). *New document* is at
the top, and a storage line ("4 documents · 18 MB (images)") with *Settings*
at the bottom. D3 sits in the Search tab with D1 and D2, reached from R1 and
from Me's *My documents · N*. Spec:
[`my-documents.md`](../04-screens/my-documents.md).

### Document words in the plan

Words added from documents wait in a queue of their own, in the order added,
and each study day takes up to *Words a day from documents* of them (5 by
default, 0 to 20) after the course's new words, outside *New words a day*
(BR-PLAN-11, the owner, #1220). A word added while today still has room
joins today, as W1's *Add to today* does; the rest start on the next study
days. A queued word is never backlog, a rest day or the backlog pause takes
none, and a cap change applies from the next day
([`plan-engine.md`](../03-domain/plan-engine.md), *The document queue*).

The sentence a word was added with is kept as the learner's own
(`word_contexts`), and outlives its document (BR-DOC-05). Showing it on T2's
back, in its cloze and in W1 is #1232, still in review for v1.2.0.

## Me

### Me · M1

The learner's overview: their name (tap to edit; the greeting on Today
follows), the streak, "Learning since …" and days studied, words Done,
Learning and To do, a 12-week activity heat map, whether the course is on
schedule (with a tap to the backlog when behind), and the 12 steps' mock exam
badges. Below: Settings, Voice & translation, *My documents · N* (a jump to
D3 in the Search tab), About & privacy, and *Rate Sogda on Google Play*
(v1.2.0), which opens the Play listing (FR-M1-05). Spec:
[`me.md`](../04-screens/me.md).

### Progress · M2

Week, month or all time: cards per day (revisions and new words), retention
against the target (shown once there are 30 days of data), progress by step,
and totals: study time, words introduced, reviews, and the current and best
streak. Spec: [`progress.md`](../04-screens/progress.md).

### Settings · M3

Every change saves at once; the plan's own changes apply from tomorrow
(BR-PLAN-08).

| Group | Settings |
|---|---|
| Daily plan | New words a day (1–50), revisions (0–100), practice sentences (0–20), study days and reminder (M5), move to the next step automatically, pause new words when the backlog is large |
| Revision | Target retention (80–97 %, with an estimate of reviews a day), mark Done after N days remembered (3–60), swipe to rate, my words in quizzes |
| Display | Meaning languages (a first and an optional second, from the course's: English, বাংলা, Русский, Polski), app language (English, বাংলা, Polski, Русский), theme (System, Light, Dark, Glass), show the Bangla pronunciation |
| Audio | Voice engine (M4), speech speed (0.5–1.5×), auto-play the headword and the first example, listening questions |
| Exams | Unlock mock exams at (50–100 %), pass mark (50–90 %), timer on by default |
| Translation | On-device translation (Hy-MT2), off by default; turned on with no model, it opens M4 (FR-M3-03) |
| Learn from documents | Words a day from documents (0–20, 5 by default, from tomorrow), save original images (on; turned off while photos are kept, it asks whether to delete them), auto-delete documents (never, or after 30, 90 or 365 days, at launch) |
| Data | Export / import (M6), Reset (M7), Restart setup (S2) |

The Translation group shows in every build since Hy-MT2 (ADR 30); v1.0 and
v1.1 hid it. *Show words I probably know* is D2's own switch.
Spec: [`settings.md`](../04-screens/settings.md).

### Voice & translation · M4

The model manager. A storage card shows the phone's free space and the
models' share. The **Supertonic 3 voice** card downloads the voice (about
400 MB, Wi-Fi only by default) with pause, resume and progress, verifies it
by checksum, lets the learner pick Anna, Jonas or Lena with a sample, checks
for an update, and deletes it, which falls back to the phone's voice. A
download refused for space says how much to free. The **Hy-MT2 translation**
card downloads the same way: 1.1 GB, Apache-2.0, in every build (ADR 30). The
two models can download side by side, under one notification (#1255). Spec:
[`model-manager.md`](../04-screens/model-manager.md); the voice engine:
[`tts.md`](../03-domain/tts.md).

### Study days & reminder · M5

The study days as seven toggles (at least one stays on; the rest are rest
days), and a daily reminder: on or off, its time, and *Only when there is
something to do*. A preview shows tonight's text, built from the real plan
("12 revisions · 7 new · about 9 min · Grammar due: Konjunktiv II"). Spec:
[`reminder-days.md`](../04-screens/reminder-days.md).

### Export / import · M6

One JSON file with word states, the review log, plans, quiz and exam history,
settings, the learner's own words and, since v1.2.0, the documents (their
text, what each found, the sentences and the queue; never their photos,
BR-DOC-06), shared through the system share sheet
(to Files, Drive or email). Importing shows a preview first (word states,
last active, the step, what else the file holds), then either merges (the
most recent of each word wins) or replaces everything, after a confirm.
Speaking recordings are not included. Spec:
[`export-import.md`](../04-screens/export-import.md).

### Reset · M7

*Export first*, *Reset one step* (its words back to To do, with their
reviews, plans, grammar, quizzes and mocks), or *Reset everything*, which
needs RESET typed to confirm and returns to setup; it deletes the documents
and their photos too, and says so. Theme, app language and
downloaded models survive a full reset. Spec: [`reset.md`](../04-screens/reset.md).

### About & privacy · M9 and licences · M8

The version, the course's content version and counts (5,142 words, 182
grammar topics, 10,691 sentences), the privacy statement, a *Contact* link to
the project's GitHub issues, and the licences: the Supertonic model and SDK,
Hy-MT2's (Apache-2.0), the fonts, PdfBox-Android with Bouncy Castle, and
every package, each in full, and the terms of ML Kit and Play's in-app
review library, linked. Spec:
[`about-licences.md`](../04-screens/about-licences.md).

## Voice, everywhere

Every word, example, sentence, grammar example and listening question can be
heard ([`tts.md`](../03-domain/tts.md)):

- **The phone's German voice** speaks until Supertonic is downloaded, and
  is always the fallback.
- **Supertonic 3**, if downloaded, speaks on the device with one of three
  voices. Today's session prepares its clips ahead, so the next card plays
  at once.
- If Supertonic fails, the phone's voice takes over, with a one-time notice.
  If the phone has no German voice either, speakers show a slashed icon and a
  tap explains how to install one.
- Speed is a setting; a long press on the study card's, W1's or T5's speaker
  plays at 0.75×.

## Translation on the phone (v1.2.0)

Hy-MT2-1.8B translates between German and the learner's meaning languages,
on the phone, once the learner downloads it in M4 (1.1 GB) and turns
*On-device translation* on in M3; it is off until then (`mt_enabled`). Every
build offers it (ADR 30). It appears in four places:

- **W1's *Translate*,** for examples with no line in the first meaning
  language (FR-W1-05).
- **T5's word tap,** for a word the course doesn't have (FR-T5-03).
- **R1's *Translate «…»*,** when a search finds nothing.
- **D2's card and R2,** a meaning for a word outside the course, labelled
  machine-translated until the learner edits it (BR-DOC-07, #1233).

It needs a phone with **at least 3.5 GiB of memory** (`HyMtTranslator.memoryFloor`,
#154): below it M4 says *Not available*, M3's switch is disabled and D2
offers no download, since the 1.1 GB model can't stay resident beside
Android in less. The first translation loads the model, which takes a few
seconds; it is released in the background and under memory pressure, as the
voice is. A translation stops after **60 s** (`HyMtTranslator.limit`), and
the screen shows none. An answer is cached, so a second ask doesn't run the
model again. These arrive with #1269, timed on a real phone. Spec:
[`translation.md`](../03-domain/translation.md).

## Reminders and the widget

- **Daily reminder** (M5): off until switched on, and permission is asked
  only then. With *Only when there is something to do* (the default), the
  text is written from the real plan ten minutes before, and a finished day
  or a rest day gets none. A tap opens Today. Reminders survive a restart of
  the phone. Rules: [`notifications-widget.md`](../03-domain/notifications-widget.md).
- **Home-screen widget · X1** (Android): small (2×2: the step, the ring,
  "8 left", the minutes) and medium (4×2: adds the word of the day with its
  meaning and *Pronounce*). Tapping the ring opens Today; the word opens W1;
  *Pronounce* opens it and speaks. When the day is done it shows a check and
  tomorrow's preview. It follows the phone's light or dark mode, and
  refreshes at midnight, after each session and hourly. Spec:
  [`widget.md`](../04-screens/widget.md).

## Content updates

The course ships inside the app, so new content comes with an app update. A
content update never touches progress, which is keyed by each word's stable
id (BR-CONTENT-01). New words join their step's To-do queue in teaching
order, removed words disappear from plans and lists (their history stays),
and a changed Bangla meaning wears an *Updated* chip for 7 days. Today shows
a one-time *Course updated* card with the counts ("n added · n removed · n
changed").
Specs: BR-CONTENT-01…03, [`content-database.md`](../02-data/content-database.md).

## When something goes wrong

- **The app can't open its data** (S1): a full-screen error with *Retry* and
  *Export progress*.
- **An answer can't be saved** (T2): "Couldn't save that answer. Every card
  before it is saved.", with *Retry* and *Export progress*.
- **A model download is interrupted:** it waits for Wi-Fi and resumes, or
  offers *Retry*; a download never fills the phone (a 100 MB margin is
  kept).
- **The date or time zone changes:** days are local calendar days; a day is
  never planned twice or lost.

The full table is in [`accessibility-performance.md`](../01-architecture/accessibility-performance.md),
*Error and edge states*.

## Not in v1.x

| Not included | Why, and where it is tracked |
|---|---|
| **iOS** | Needs a Mac to build and sign. The iOS code paths exist and are tested on Windows; the release pipeline (#171), the WidgetKit widget (#161) and the simulator smoke test (#398) are in "Later · after v1.0" |
| **On-device translation before v1.2.0** | Hy-MT 1.5's licence excludes the EU, UK and South Korea, so v1.0 and v1.1 shipped with it off (ADR 9, #173). Hy-MT2 (Apache-2.0) brings it back in v1.2.0 (ADR 30, #154) |
| **A PDF's password, or a scanned PDF as text** | Sogda asks for no password; a scan has no text layer, so D1 sends it to the photos (`doc-import.md`) |
| **Documents on iOS** | Out of v1.2.0's scope, as iOS is (epic #1219) |
| **Bangla translations of example sentences** | The course has none in Bangla: Bangla learners read examples in English (#598). Russian and Polish have their own since v1.1.0. Bangla's grammar topics come in the first update after v1.2.0 (#1403) |
| **Category names in Bangla before v1.2.0** | Kept in English for Bangla learners in v1.0 and v1.1 (#425). v1.2.0 ships them (#1398, the owner, 2026-10-03), as v1.1.0 did Russian's and Polish's (#1128) |
| **Speech recognition or scoring of speaking** | Speaking and writing are self-assessed with app checks (BR-EXAM-06) |
| **Sync between devices, accounts, cloud backup** | Not a goal: moving progress is an export file (ADR 13) |
| **A German UI (immersion mode)** | "German UI is a possible later immersion mode" ([`accessibility-performance.md`](../01-architecture/accessibility-performance.md), *Localisation*) |
| **FSRS weights tuned to the learner** | Default FSRS-4.5 weights; on-device optimisation once 1,000+ reviews exist is future work (ADR 7) |
| **Landscape on phones** | Phones stay portrait; tablets turn (#577) |
| **Web or desktop** | Android and iOS are the only targets |
