# Business rules (canonical)

Every rule has an ID. Engines in `03-domain/` implement them; screens in `04-screens/` reference them; tests assert them.

## Course structure

- **BR-COURSE-01** The course has 6 CEFR levels and 12 steps: `A1.1, A1.2, A2.1, A2.2, B1.1, B1.2, B2.1, B2.2, C1.1, C1.2, C2.1, C2.2`, in that fixed order.
- **BR-COURSE-02** A word belongs to exactly one step. Its level comes from the workbook's `Level` column; its step is assigned by the content pipeline at the week boundary nearest the middle of the level, and once the course has shipped that boundary stays, so a content update never moves a word between steps unless the build is told to (#923; see `02-data/content-pipeline.md`).
- **BR-COURSE-03** Grammar topics are split between X.1 and X.2 by count, keeping teaching order, and once the course has shipped each topic stays in its step, so a content update never moves a topic between steps unless the build is told to (#970; see `02-data/content-pipeline.md`).
- **BR-COURSE-04** A learner can browse any step at any time. Studying (new words) happens only in the *active* step. Exactly one step is active at a time.
- **BR-COURSE-05** Auto-advance (default on): when every word of the active step has been planned, the next step becomes active at once, and the day the step ran out on is filled from it at the same pace (#687). With auto-advance off, Today shows "Step complete" and offers *Start next step*.

## Word status

- **BR-STATUS-01** Statuses: `todo` (never introduced), `learning` (introduced, still being reviewed), `done` (FSRS stability ≥ `done_stability_days`, default 7), `suspended` (paused by the learner).
- **BR-STATUS-02** `done` is derived, never set by hand. A lapse (rating Again) can move a word from `done` back to `learning`.
- **BR-STATUS-03** `suspended` words are excluded from plans, revision, quizzes, exams and practice sentences until resumed. Suspension keeps FSRS state. Suspending a word drops its open revision for today and skips its open `new` row for today, which is backlog from tomorrow. Its backlog rows stay, and T4 lists it without studying it. Its backlog rows count toward neither the backlog pause (BR-PLAN-07) nor Today's backlog (#368). A rating never changes a suspended word's status (#351): the schedule still moves, and *Resume* derives the status from it.
- **BR-STATUS-04** "I know it" on a new word = first review rated Easy.

## Daily plan

- **BR-PLAN-01** A study day is any weekday enabled in `study_days_mask` (default all seven). Non-study days are *rest days*: no new words, no backlog growth, streak preserved; revisions are optional. The setup day is a study day whatever the mask: day 1 is planned with `daily_new`, and the mask applies from the next day (the owner's call, #606).
- **BR-PLAN-02** On a study day the plan is: Revise (`revise_count`, default 10) → New today (`daily_new`, default 7, from the active step in teaching order) → Grammar due (topics whose FSRS due ≤ today) → Practice sentences (`sentence_count`, default 3).
- **BR-PLAN-03** Revise picks FSRS-due words first (earliest due), then fills with the lowest-retrievability learned words, excluding today's new words. It never exceeds `revise_count`; excess due cards wait.
- **BR-PLAN-04** Plans are generated when a day is first opened and persisted. Reopening the same day shows the same plan.
- **BR-PLAN-05** Missed days are generated retroactively (up to `backlog_catchup_days`, default 30). Any new word planned for a past date and not completed is the **Backlog**.
- **BR-PLAN-06** *Skip* leaves a new word uncompleted; it appears in the backlog from the next day. Backlog has no deadline and is never shown as overdue.
- **BR-PLAN-07** Backlog pause: when on, no new words are planned until the backlog is empty; revisions continue. Today offers this when backlog > 3 × `daily_new`.
- **BR-PLAN-08** Changes to `daily_new`, `revise_count`, `study_days_mask` take effect from the next day; today's plan is fixed.
- **BR-PLAN-09** Time estimate = 25 s per revision + 45 s per new word + 60 s per grammar topic + 40 s per sentence, replaced by the learner's own median timings once ≥ 7 sessions exist before today; measured over the last 30 study days before today, so the estimate is fixed for the day (#708).
- **BR-PLAN-10** Day complete = every plan item of today is completed or skipped, and no grammar/sentence item is open. Rest days count as complete for streak purposes.
- **BR-PLAN-11** Words added from a document (BR-DOC-04) are introduced up to `doc_daily_cap` a day (default 5, from 0 to 20; the owner's call, #1220), after the course's new words and outside `daily_new`. The rest wait in the document queue, in the order added, and are never backlog. The cap applies on study days only, and the time estimate counts them as new words (BR-PLAN-09). A cap of 0 holds them all in the queue. They're planned for today only: a missed day the catch-up walks takes none of them (#1231).
  - **Today:** a word added on a study day while today's slots aren't used up joins today's plan, as W1's *Add to today* does (FR-W1-01): today's plan is fixed (BR-PLAN-04, BR-PLAN-08) except for words the learner adds. The rest start on the next study days.
  - **A cap change** takes effect from the next day, as `daily_new` does (BR-PLAN-08).
  - **The backlog pause** (BR-PLAN-07) holds the queue too: no new words of any kind. A finished step with *Auto-advance* off doesn't: document words aren't the step's.
  - A queued word isn't backlog. A document word in a day's plan that's skipped is backlog, like any planned word (BR-PLAN-06).

## Scheduling (FSRS)

- **BR-FSRS-01** Scheduler is FSRS-4.5 with the published default weights; `desired_retention` default 0.90 (settable 0.80–0.97).
- **BR-FSRS-02** Ratings: 1 Again · 2 Hard · 3 Good · 4 Easy. Every rating is logged in `review_log` with source (`daily`, `quiz`, `exam`, `search`, `known`, `sentence`).
- **BR-FSRS-03** Quiz/exam results feed FSRS: correct → Good, almost → Hard, wrong → Again. "Add missed to revision" = rate Again.
- **BR-FSRS-04** Practice sentence "Not yet" rates the headword Hard.
- **BR-FSRS-05** Grammar topics use the same scheduler in `grammar_state`; a practice set is rated as a whole (all correct → Good, one wrong → Hard, more → Again).
- **BR-FSRS-06** A word switches to the **cloze card** format after two consecutive Good/Easy ratings, and back to plain on a rating below Good. The learner can choose either card from Word detail, and the rule then keeps their choice (`word_state.card_mode_manual`) whatever they rate, a lapse too, until they choose again or reset the word.

## Answers

- **BR-ANS-01** DE→EN: any synonym in the ` / `-separated list counts ("house / home"; a comma never separates synonyms, in any language: it belongs to the phrase, "the bill, please", «тем, что», so "please" or «что» alone is not an answer, #775), and so does the whole cell as shown, or several of its synonyms typed as a list in any order, with ` / `, a comma or `;` ("hi / hello", "hello, hi"; one that isn't a synonym makes the list wrong, so "tip, please" is wrong for "the bill, please"); a separator inside brackets belongs to a note, not the list, and a synonym counts with or without its bracketed note ("to save (a file)" takes "to save", never "a file"); case and a leading "to " are ignored, and so is a hyphen ("email" for "e-mail", in a meaning only: German's "Email" is not "E-Mail", #699); one-character typos on words ≥ 6 letters are *almost*, ß counting as one letter ("Größe" has five, so "Grüße" is wrong; "Straße" has six, #699).
- **BR-ANS-02** EN→DE: the word with or without its article, while a phrase with no article of its own is typed whole, its leading "Das" or "den" included (#687), and an article typed before it is wrong, before any phrase ("das Guten Morgen"), not only one that starts with an article word; any one of the German's ` / ` alternatives, each side of an in-word slash ("hat/ist aufgebrochen"), with or without a bracketed note; umlauts as ä or ae, ü or ue, ö or oe, and ß as ss; a bare vowel for an umlaut (a for ä) is *almost*, because it can be another word or form ("hatte" for "hätte", "Mutter" for "Mütter") (#675); a wrong article on a correct noun is *wrong article* (counts as wrong for scoring, but the feedback names the article); a wrong article on a misspelt noun is just *wrong*, so a typo never scores more than the spelling it got wrong (#614). Where the prompt's meaning cell belongs to several words of the course, any of them is right ("you": du, dich or Sie; #832).
- **BR-ANS-03** Articles quiz: exact match of der/die/das.
- **BR-ANS-04** *Almost* scores 0.5 in quizzes and exams.

## Search

- **BR-SEARCH-01** Result order: Exact match → Starts with → Similar words → In sentences. Within a tier, higher frequency first; in Exact match, after the words keyed as the query is spelled ("schön" before schon, #734).
- **BR-SEARCH-02** Exact match ignores article, case and umlaut spelling; matches English synonyms exactly and Bangla exactly.
- **BR-SEARCH-03** Similar = trigram candidates within edit distance ≤ 2 (≤ 3 for queries > 5 chars).
- **BR-SEARCH-04** Web search opens Duden, DWDS, Wiktionary, Linguee or Google in an in-app browser. Nothing is sent by the app itself.

## Quizzes and exams

- **BR-QUIZ-01** Quiz sources: this step's learned words (default), all learned, a category, a compare set (W2's *Quiz these*), and L9's *Retry mistakes* (that result's wrong words only). Lengths 10/20/30. Wrong answers are re-asked once at the end.
- **BR-EXAM-01** Mock exams unlock when ≥ `exam_unlock_percent` (default 90) of the step's words are introduced.
- **BR-EXAM-02** Three mocks per step, generated by one algorithm with seeds 1–3; items never repeat across a step's three mocks. *Try another mock* opens the step's exam hub, where a mock not yet sat reads *Not attempted*.
- **BR-EXAM-03** Sections and counts: Vocabulary 10 · Reverse 8 · Articles 6 · Word forms 4 · Gap fill 6 · Grammar 4 · Listening 2 · Writing 1 · Speaking 1. Points: 1 per item, Writing 4, Speaking 4 → 48 points.
- **BR-EXAM-04** Pass mark `exam_pass_percent` (default 60). Passing any mock marks the step *Passed*.
- **BR-EXAM-05** No feedback during the exam. Leaving saves an unfinished attempt; the timer stops.
- **BR-EXAM-06** Writing and Speaking are self-assessed with app-side checks (words used, length, connectors) plus a rubric (two items for Writing, four for Speaking, a point each); recordings stay on device.

## Content updates

- **BR-CONTENT-01** Word identity is the uid hash of `level | german | pos | english`. Progress is keyed by uid and survives content updates.
- **BR-CONTENT-02** New words join their step's To-do queue in teaching order; removed words are hidden but their history stays; changed meanings show an *updated* chip for 7 days.
- **BR-CONTENT-03** Today shows a one-time update card with counts. A duplicate merged into a word the course kept (PIPE-12) is not counted as removed: its progress moved to that word (#922).
- **BR-CONTENT-04** A row of the course is a word to learn (`vocab`), a lesson note (`note`: word formation, "beantworten — Präfix be-"; a grammar rule's name, "Vorfeldbesetzung") or a comparison (`compare`: "machen ↔ tun"). Notes and comparisons are listed, searched and opened (L2, L6, R1, W1) like any word, with no status; they are never planned, revised, quizzed, examined, placed, practised in sentences or counted in a step's or the course's words (#630). The pipeline assigns the kind (PIPE-10).

## Documents (v1.2.0, epic #1219)

*Planned:* these ids aren't bold yet. Each one becomes bold, and so enforced by `architecture_test.dart` (every bold id must name a test), in the PR that implements and tests it.

- BR-DOC-01 Everything a document goes through happens on the phone: text extraction, OCR (ML Kit text recognition with the model bundled), lemmatising and translation (Hy-MT2, once downloaded). No document, image or word is sent anywhere (BR-PRIV-01).
- BR-DOC-02 A document comes from pasted text, Android's share sheet (text, a PDF or an image), a PDF chosen in the file picker (its text layer), or photos (the camera or the gallery). It has at most 30 pages or 20,000 characters, whichever comes first; the rest is cut at a sentence end, and the learner is told.
- BR-DOC-03 Each lemma found is classed as **known**, **probably known**, **new in the course**, **mine** or **outside the course**, as `03-domain/document-matcher.md` defines. Stop words are never offered. A lemma is listed once per document, with all its sentences.
- BR-DOC-04 *Add* puts a course word in the document queue (BR-PLAN-11), with its sentence kept as a context. A word outside the course becomes one of *My words*: the sentence is its example, the document's title is its *where I saw it*, and its meaning is Hy-MT2's (labelled) or typed in. A word added again gets the new sentence, never a second card. *I know this* is W1's *Mark known* (FR-W1-02).
- BR-DOC-05 Documents are kept, as the owner decided (#1220): the text always, and the images while *Save original images* is on (the default). *Auto-delete after N days* is off by default. Deleting a document never deletes the words added from it, and their sentences stay on the cards. A saved image loses its metadata (EXIF, GPS included).
- **BR-DOC-06** Export carries the documents' text, what each one found, the sentences and the queue. It never carries images. Import merges them like *My words* (the identities are in `03-domain/document-matcher.md`).
- BR-DOC-07 A machine-translated meaning is labelled as such until the learner edits it.
- BR-DOC-08 The feature is free, with no limits (#1220).

## Ratings (v1.2.0, #1237)

- **BR-RATE-01** Google Play's in-app review card is asked for **once**, after the learner's first passed mock exam (BR-EXAM-04), when L13 shows the pass. The owner chose this milestone on 2026-10-03.
  - **Google's rules:** no question before the card, no incentive, and no button that triggers it. A button may only open the listing, which is Me's *Rate Sogda on Google Play* (FR-M1-05).
  - **What the app keeps:** only that it has asked (`play_review_asked`). It never asks again, even when Play didn't show the card: whether it shows is Play's call, under a quota Play doesn't publish.
  - **Privacy:** the card is the Play Store app's own UI, reached on the phone through Play's In-App Review library. Sogda sends nothing about the learner, and asks only after a pass the learner just made (BR-PRIV-01).
  - **Android only:** the app is on Play alone (v1 scope).

## Privacy

- **BR-PRIV-01** No network call is made without a user action (web link, model download, export share). A library's own reporting counts: ML Kit's usage metrics, which its text recognition queues for Google even with the model bundled, are cut off in the manifest (DataTransport's backend and schedulers removed, #1229). After a dependency update, the release APK's merged manifest is checked for `datatransport`, `firebase`, `clearcut` and `measurement` (`aapt2 dump xmltree --file AndroidManifest.xml`).
- **BR-PRIV-02** All learner data lives in `user.db` and app-private files. Export is a JSON file the learner shares themselves. Android backup and device-to-device transfer are off for the app (`allowBackup=false` and data-extraction rules that exclude everything, #607), so nothing leaves the phone any other way.
