# Document matcher (v1.2.0, epic #1219)

Turns German text the learner brings into words they can add: course words
with their step and status, and words outside the course with a
machine-translated meaning. Pure Dart in `lib/domain/documents/` (no Flutter,
no drift), fed by the data layer. The owner's decisions are on #1220.

## Pipeline
| # | Step | Where | Issue |
|---|---|---|---|
| 1 | **Text in.** Pasted or shared text as it is. A PDF's text layer page by page. A photo through ML Kit text recognition, with the model bundled (on the device, no download). Up to 30 pages or 20,000 characters, whichever comes first. The rest is cut at the last sentence end before the limit (the last word end, if the text has no sentence end there), with a note | `data/documents/` (platform) | #1227, #1228, #1229 |
| 2 | **Clean-up.** Join words hyphenated across a line end («Ver-↵waltung» → Verwaltung), but keep a real hyphen («E-Mail»). Drop page numbers, and headers and footers that repeat on every page. Normalise quotes, dashes and spaces | `domain/documents/clean.dart` | #1224 |
| 3 | **Sentences and tokens.** Split into sentences, minding the abbreviations «z. B.», «Nr.», «Str.», «bzw.», «ca.» and «Dr.», and into words with their sentence and offset | `domain/documents/tokens.dart` | #1224 |
| 4 | **Skip.** Numbers, dates, amounts, IBANs, postcodes, e-mail addresses and URLs. A capitalised word in the middle of a sentence that neither the course nor step 5 knows as a noun is a name | `tokens.dart` | #1224 |
| 5 | **Lemmatise.** Each token gets its candidate course lemmas (below) | `domain/documents/lemmatiser.dart` | #1223 |
| 6 | **Classify.** Each lemma gets one class, and a document lists a lemma once, with all its sentences (below) | `domain/documents/matcher.dart` | #1225 |
| 7 | **Rank.** The learner's level first, then one above, then the rest by the course's `freq`. Words outside the course last, in order of appearance | `matcher.dart` | #1225 |

**Budget:** a 2-page letter (about 600 words) goes through steps 2–7 in under 500 ms on the perf device (`perf.py`), run in an isolate.

## The lemmatiser
It maps a written form to the course's lemmas without any dictionary from
outside: the course's own data, plus rules, plus one small table we write.
- **From `words.forms`** (`content.db`):
  - a noun's plural, plus the dative plural's ‑n and the genitive's ‑s/‑es;
  - a verb's 3rd-person present and participle, separable verbs included ("räumt auf · hat aufgeräumt");
  - an adjective's comparative and superlative, where `forms` gives them.
- **Rules:**
  - regular present and past endings (‑e, ‑st, ‑t, ‑en, ‑te, ‑test, ‑ten, ‑tet);
  - adjective endings (‑e, ‑en, ‑em, ‑er, ‑es), and on comparatives;
  - the participle's ge‑ prefix and its separable variant (an**ge**rufen);
  - zu‑infinitives (an**zu**rufen).
- **A strong-verb table** (`assets/documents/strong_verbs.json`, written by the team, no licence): about 200 irregular verbs' Präteritum and Konjunktiv II stems (ging, gingen; käme; wüsste…) mapped to the infinitive.
- **Separable verbs in a sentence:** when a finite verb has a known separable particle at the end of its clause («Ich **rufe** Sie morgen **an**.»), the pair maps to the particle verb (anrufen). The verb alone maps there only if the base verb isn't a course word on its own.
- **Folding:** case, ß/ss and umlauts, the way search's key does. A form that matches two lemmas («Weg» and «weg», «sein» the verb and the pronoun) is resolved by capitalisation and the neighbouring words. If it's still open, the word is *ambiguous*, and D2 lets the learner choose.
- **Compounds:** a noun with no lemma is split at the longest known course nouns («Nebenkostenabrechnung» → Nebenkosten + Abrechnung), allowing the linking ‑s‑ or ‑n‑. The parts are only a hint in D2. The word itself is outside the course.

**Accuracy, measured on the test corpus (#1223):** precision of at least 95 % and recall of at least 90 % on course words.
- **The corpus:** three official letters (a landlord's, a Jobcenter's, a health insurer's) and three articles, written by the team for the test, with every course word labelled. **No real person's document is used.**

## The classes (BR-DOC-03)
| Class | Rule | D2 shows it |
|---|---|---|
| **Known** | The word's status is `learning`, `done` or `suspended` (BR-STATUS-01). A suspended word stays out of plans (BR-STATUS-03), so it's never offered | Plain, and never offered |
| **Probably known** | A `todo` course word in a step before the active step that no day's plan has ever held: placement and *Choose myself* skipped it. A word that was planned and not learned is backlog (BR-PLAN-05/06), so it's **new**, not probably known | Dimmed, shown when *Show words I probably know* is on |
| **New in the course** | A course word not yet studied, in the current step or later | Highlighted in its level's colour, to add |
| **Mine** | Already one of *My words* (`custom_words`, by search key), and not a course word | Marked "My word", to add a sentence |
| **Outside the course** | No lemma in the course | Underlined, to add as a word of my own |
| *Stop word* | A lemma in `assets/documents/stop_words.txt` (written by the team: articles, pronouns, the commonest prepositions and conjunctions, *sein*, *haben*, *werden* and the modals), even when it's a course word | Plain, never offered |

**One class per lemma, in this order:** stop word, known, probably known, new in the course, mine, outside the course. A course word wins over *Mine*: a word of my own that the course also has (`custom_words.matched_uid`) is offered as the course word, and D2 shows its "My word" mark too.

**Not German (FR-D1-04):** fewer than 50 % of the word tokens (after step 4) lemmatise to a course word or a stop word. The corpus test pins it: every German text is above, an English and a Bangla text are below.

## Data (`user.db`, schema change in #1226)
- **`documents`** (id, title, source `paste|share|pdf|photo`, created_at, text, image_paths JSON, page_count, word_count). Kept, as the owner decided (#1220):
  - the text always; the images while *Save original images* (`doc_save_images`, default on) is on, in app-private storage (`<appSupport>/documents/<id>/`);
  - **auto-delete** after `doc_autodelete_days` (default 0, never).
- **`document_words`** (document_id, lemma_key, surface, sentence, class, added `0|1`): what D2 showed, so reopening a document needs no new run.
- **`word_contexts`** (id, word_key, sentence, document_id NULL, created_at): the learner's sentences for a word.
  - `word_key` is a course `uid` or `custom:<id>`.
  - A sentence outlives its document: deleting a document sets `document_id` to NULL, and the sentence stays on the card.
- **`custom_words` gains `mt` (0/1):** the meaning is machine-translated, until the learner edits it.
- **The document queue** (`doc_queue`: word_key, added_at, planned_on NULL): course words added from documents, in order. BR-PLAN-11 says how they're planned; `planned_on` is the day a word went into a plan, so today's used slots are the rows planned today.
  - **A word leaves the queue** when any route plans it (the course's own *New today*, W1's *Add to today*), or when it stops being `todo` (*Mark known*, a quiz).
  - **Reset one step** (FR-M7-01) drops that step's queue rows. Its words' sentences stay: they're the learner's, not progress. **Reset everything** empties these tables like every exported one, and deletes the saved images (best effort, after the data, as the recordings).
  - **A content update** (BR-CONTENT): queue rows and sentences follow a merged word as `word_state` does (PIPE-12, #922). A removed word's queue row drops, and its sentences stay hidden with its history (BR-CONTENT-02).
- **Export (BR-DOC-06):** `documents` (text, without images), `document_words`, `word_contexts` and `doc_queue` go into the JSON and merge like *My words*. Images never go into the JSON: they'd make it hundreds of MB.
  - **The merge identity:** a document is its `created_at` and title; a sentence is its `word_key` and text; a queue row is its `word_key` (the earlier `added_at` wins).
  - Import refuses a file whose new settings are out of range (#820): `doc_daily_cap` 0–20, `doc_autodelete_days` one of 0, 30, 90, 365, and the two switches 0 or 1.
- **Saved images** lose their metadata on save (EXIF, GPS included): they're re-encoded, never copied (BR-DOC-05).
- **New settings:**
  - `doc_daily_cap`: 5, from 0 to 20;
  - `doc_save_images`: 1;
  - `doc_autodelete_days`: 0;
  - `doc_show_probably_known`: 0.

  **These rows go into `user-database.md`'s settings table with the code** (#1226, #1231). That table is parsed by a test, so the spec doesn't list them there first.

## Meanings for words outside the course (#1233)
With Hy-MT2 downloaded (#154):
- the word is translated **in its sentence**, into the first meaning language and the second if one is set, and the word's equivalent is taken from that translation;
- if that fails, the bare word is translated.

The result is labelled *machine-translated* (`custom_words.mt = 1`) and can be edited before saving. Without the model, the meaning is empty, and D2 links to M4's download. Results are cached in `translation_cache`, keyed by the model id.

## Tests
- The lemmatiser on the corpus, with precision and recall as asserted numbers.
- The separable-verb, compound and ambiguity cases each named in a test.
- The classes, BR-DOC-03 case by case.
- The isolate's budget, in `perf.py`, and D2's first frame with a 20,000-character text, next to it.
- The test names carry BR-DOC and FR-D ids.

**The shared fixtures,** in `app/test/fixtures/documents/`, written or photographed by the team (no real person's document). The unit tests and SQA's device pass (#1234) use the same files:
- `corpus/`: the six texts, each with a `.labels.json` of its course words, plus `english.txt` and `bangla.txt` (the not-German check);
- `text_layer.pdf` and `scanned.pdf` (the same letter, with and without a text layer);
- `photo_1.jpg`, `photo_2.jpg` and `photo_blurred.jpg`: a printed team letter, the last one deliberately blurred (FR-D1-03).
