# Document matcher (v1.2.0, epic #1219)

Turns German text the learner brings into words they can add: course words
with their step and status, and words outside the course with a
machine-translated meaning. Pure Dart in `lib/domain/documents/` (no Flutter,
no drift), fed by the data layer. The owner's decisions are on #1220.

## Pipeline
| # | Step | Where | Issue |
|---|---|---|---|
| 1 | **Text in.** Pasted or shared text as it is. A PDF's text layer page by page. A photo through ML Kit text recognition, with the model bundled (on the device, no download). Up to 30 pages or 20,000 characters, the rest cut with a note | `data/documents/` (platform) | #1227, #1228, #1229 |
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
| **Known** | The word's status is *learning*, *review* or *known* | Plain, and never offered |
| **Probably known** | A course word in a step before the learner's current step that isn't yet studied (placement and *Choose myself* skip steps without marking them) | Dimmed, shown when *Show words I probably know* is on |
| **New in the course** | A course word not yet studied, in the current step or later | Highlighted in its level's colour, to add |
| **Mine** | Already one of *My words* (`custom_words`, by search key) | Marked "My word", to add a sentence |
| **Outside the course** | No lemma in the course | Underlined, to add as a word of my own |
| *Stop word* | Articles, pronouns, the commonest prepositions and conjunctions, *sein*, *haben*, *werden* and the modals, even when they're course words | Plain, never offered |

## Data (`user.db`, schema change in #1226)
- **`documents`** (id, title, source `paste|share|pdf|photo`, created_at, text, image_paths JSON, page_count, word_count). Kept, as the owner decided (#1220):
  - the text always; the images while *Save original images* (`doc_save_images`, default on) is on, in app-private storage (`<appSupport>/documents/<id>/`);
  - **auto-delete** after `doc_autodelete_days` (default 0, never).
- **`document_words`** (document_id, lemma_key, surface, sentence, class, added `0|1`): what D2 showed, so reopening a document needs no new run.
- **`word_contexts`** (id, word_key, sentence, document_id NULL, created_at): the learner's sentences for a word.
  - `word_key` is a course `uid` or `custom:<id>`.
  - A sentence outlives its document: deleting a document sets `document_id` to NULL, and the sentence stays on the card.
- **`custom_words` gains `mt` (0/1):** the meaning is machine-translated, until the learner edits it.
- **The document queue:** words added beyond today's cap, kept in order (`doc_queue`: word_key, added_at). The plan takes up to the cap from it each day (BR-PLAN-11).
- **Export (BR-DOC-06):** `documents` (text, without images), `document_words`, `word_contexts` and `doc_queue` go into the JSON and merge like *My words*. Images never go into the JSON: they'd make it hundreds of MB.
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
- The isolate's budget, in `perf.py`.
- The test names carry BR-DOC and FR-D ids.
