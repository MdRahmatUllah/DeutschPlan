# Document matcher (v1.2.0, epic #1219)

Turns German text the learner brings into words they can add: course words
with their step and status, and words outside the course with a
machine-translated meaning. Pure Dart in `lib/domain/documents/` (no Flutter,
no drift), fed by the data layer. The owner's decisions are on #1220.

## Pipeline
| # | Step | Where | Issue |
|---|---|---|---|
| 1 | **Text in.** Pasted or shared text as it is. A PDF's text layer page by page. A photo through ML Kit text recognition, with the model bundled (on the device, no download). Up to 30 pages or 20,000 characters, whichever comes first. The rest is cut at the last sentence end before the limit (the last word end, if the text has no sentence end there), with a note | `data/documents/` (platform) | #1227, #1228, #1229 |
| 2 | **Clean-up.** Join words hyphenated across a line end («Ver-↵waltung» → Verwaltung), but keep a real hyphen («E-Mail») and a suspended one («Haus-↵und Gartenpflege»). Drop page numbers, and headers and footers that repeat on every page. Normalise quotes, dashes and spaces | `domain/documents/clean.dart` | #1224 |
| 3 | **Sentences and tokens.** Split into sentences at «.», «!» or «?» (a closing quote may follow: «…ab.“ Danach»), at a blank line, and at a greeting line's comma before a capital («…Okafor,↵Vielen Dank»). Not after an abbreviation («z. B.», «Nr.», «e. V.», «z. Hd.», «MwSt.», «i. A.», «Jan.»…) or a day or month as digits («am 14. Oktober»), unless a pronoun or an article follows («Raum 2. Wir»); the stop after an IBAN ends one. Then into words with their sentence and offset | `domain/documents/tokens.dart` | #1224 |
| 4 | **Skip.** Numbers, dates, amounts, IBANs, postcodes, e-mail addresses and URLs, and lone letters («z. B.», the B of «B1»). A capitalised word in the middle of a sentence that the course doesn't know is a name (`likelyName`), unless it's a compound of course words, ends like a noun (-ung, -heit, -schaft, -tion…) or follows an article or a determiner («die Handwerker»). After a title (Frau, Herr, Familie, Dr, Prof) it always is. A country in -ien («Syrien») ends like a plural (Familien), so it reads as a noun | `tokens.dart` | #1224 |
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
  - regular present and past endings (‑e, ‑st, ‑t, ‑en, ‑te, ‑test, ‑ten, ‑tet), and ‑eln's «ich sammle»;
  - a noun's old dative ‑e («nach Hause», «im Jahre»);
  - a verb headword that is a form itself («ward», «mag», «dürfte») matches only itself, so «war» is sein's. It ranks as a rule's form, so a verb whose form it is reads first: «mag» is mögen's, not C1's concessive «mag» (#1274);
  - adjective endings (‑e, ‑en, ‑em, ‑er, ‑es), and on comparatives;
  - the participle's ge‑ prefix and its separable variant (an**ge**rufen);
  - zu‑infinitives (an**zu**rufen).
- **A strong-verb table** (`domain/documents/strong_verbs.dart`, a constant written by the team, no licence): about 145 strong, mixed and irregular verbs' Präteritum and Konjunktiv II (ging, käme, wüsste…). A prefixed or separable verb takes its base's row: verstehen is ver + stand, ankommen is an + kam. Beside it, the forms no rule makes (`irregularForms`, #1274): sein's «bin», «bist», «sind», «seid», and werden's «wirst» and passive «worden», so the stop list drops them by their lemma.
- **Separable verbs in a sentence:** when a finite verb has a known separable particle at the end of its clause («Ich **rufe** Sie morgen **an**.»), the pair maps to the particle verb (anrufen), and the particle has no lemma of its own.
  - **No verb in that clause:** the sentence before it is searched, since a comma also sets off a list or an apposition («Bitte **bringen** Sie den Ausweis, den Lebenslauf und das Zeugnis **mit**.»).
  - **A particle verb the course doesn't have** («findet … statt», «Geben Sie … mit»): both words have no lemma, since the verb is no form of finden and the particle is no preposition. A particle that only adds a direction (hin, her, los) leaves the verb as it is: «Wo gehst du hin?» is gehen.
  - **Joined forms** (wenn er ankommt, anzurufen, angerufen) are forms of the particle verb.
  - **A verb alone,** with no particle, is its base verb.
- **Folding:** case, ß/ss and umlauts, the way search's key does (ä as ae, so «Mutter» isn't «Mütter»).
- **Choosing among readings,** in this order:
  1. **Case,** in the middle of a sentence: a capitalised token matches only capitalised headwords («Morgen» the noun), and a lower-case one only the others («morgen»). With none, it has no lemma (a name), except a nominalised infinitive after an article, which is its verb («beim Lesen», «das Leben»).
  2. **The best-founded reading:** the headword itself, then `words.forms`, then a rule. So «gefallen» is gefallen before it is fallen's participle.
  3. A word over a phrase, and the bare word over a headword with more to it (warten before «warten auf»).
  4. The headword nearest the token: «nächsten» is nächste before it is nah's superlative.
  - **Still open** (at the start of a sentence, where case says nothing: «Morgen»): the word is *ambiguous*, and D2 lets the learner choose. So are homonyms («schon», «schon (Partikel)»), and a verb's form that is an unrelated word's headword, which keeps both readings: «weiß» is wissen or the colour (`_verbToo`, #1274). The participles that are adjectives too («erlaubt», «reserviert») read as the adjective, which is their verb's anyway.
- **A letter's salutation** («Liebe Eltern», «Lieber Herr Becker») is the adjective lieb, neither the noun Liebe nor gern's lieber, so it has no lemma.
- **Compounds** (`Lemmatiser.compoundParts`): a word with no lemma is split into course words, the last a noun (the compound's head), with a linking ‑s‑, ‑es‑, ‑n‑, ‑en‑ or ‑e‑ between («Nebenkostenabrechnung» → Nebenkosten + Abrechnung, «Integrationskurs» → Integration + Kurs). The longest head wins, and the first part may itself be a compound. A part is never a stop word («Wasserzähler» is no «Was» + «Erzähler»), and the parts are shown as their headwords («Mietvertrags» → … + Vertrag). The parts are only a hint in D2. The word itself is outside the course.

**Accuracy, measured on the test corpus (#1223):** precision of at least 95 % and recall of at least 90 % on course words, stop words left out.
- **The corpus:** three official letters (a landlord's, a Jobcenter's, a health insurer's) and three articles, written by the team for the test, with every course word labelled. **No real person's document is used.**
- **A seventh text, a bank's letter, is held out:** it was written and labelled after the rules were tuned on the six, and is never tuned on. A new rule has to keep it passing, and new cases go into a new held-out text.
- **Three more are held out, by SQA (#1267):** a school letter, a doctor's letter and a news item (`heldout_*.txt`). They're in the corpus figure, and each text's misses are pinned in their own test. Two misses are known: an imperative after «oder» («oder geben Sie … mit»), and «Bänken», whose bench plural the course's *Bank* doesn't have. So any change in what these texts find is a regression or a fix to name.
- **Labels are a reader's, not the lemmatiser's:** each text's `.labels.json` lists (`read`) the lemma of every word a reader sees in it, stop words aside. The test keeps those that are course headwords today, so a content update never leaves the labels stale. Homonyms all count, and a verb with a preposition («abhängen von») counts where the course has no bare verb.

## The classes (BR-DOC-03)
| Class | Rule | D2 shows it |
|---|---|---|
| **Known** | The word's status is `learning`, `done` or `suspended` (BR-STATUS-01). A suspended word stays out of plans (BR-STATUS-03), so it's never offered | Plain, and never offered |
| **Probably known** | A `todo` course word in a step before the active step that no day's plan has ever held: placement and *Choose myself* skipped it. A word that was planned and not learned is backlog (BR-PLAN-05/06), so it's **new**, not probably known | Dimmed, shown when *Show words I probably know* is on |
| **New in the course** | A course word not yet studied, in the current step or later | Highlighted in its level's colour, to add |
| **Mine** | Already one of *My words* (`custom_words`, by search key), and not a course word | Marked "My word", to add a sentence |
| **Outside the course** | No lemma in the course | Underlined, to add as a word of my own |
| *Stop word* | In `domain/documents/stop_words.dart` (written by the team), even when it's a course word: articles, pronouns and determiners with their endings, the commonest prepositions and conjunctions, all checked on the token; *sein*, *haben*, *werden* and the modals, checked on the lemma | Plain, never offered |

**One class per lemma, in this order:** stop word, known, probably known, new in the course, mine, outside the course. A course word wins over *Mine*: a word of my own that the course also has (`custom_words.matched_uid`) is offered as the course word, and D2 shows its "My word" mark too.

**Not German (FR-D1-04, `germanShare` in `tokens.dart`):** fewer than 50 % of the word tokens (after step 4) lemmatise to a course word or a stop word, or are a compound of course words. Names and all-capital words (REWE, SEPA) count neither way, so a bank statement full of them is still German. The corpus test pins it: every German text is above, an English and a Bangla text are below.

## Data (`user.db`, schema change in #1226)
- **`documents`** (id, title, source `paste|share|pdf|photo`, created_at, body, image_paths JSON, page_count, word_count). `body` is the text: drift's tables have a `text()` of their own (#1226). Kept, as the owner decided (#1220):
  - the text always; the images while *Save original images* (`doc_save_images`, default on) is on, in app-private storage (`<appSupport>/documents/<id>/`);
  - **auto-delete** after `doc_autodelete_days` (default 0, never).
- **`document_words`** (document_id, lemma_key, surface, sentence, class, added `0|1`), one row per lemma and sentence (PK(document_id, lemma_key, sentence)): what D2 showed, so reopening a document needs no new run.
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
- `corpus/`: the six texts, the held-out seventh and SQA's three held-out ones (#1267), each with a `.labels.json` of its course words, plus `english.txt` and `bangla.txt` (the not-German check, #1225);
- `text_layer.pdf` and `scanned.pdf` (the same letter, with and without a text layer);
- `photo_1.jpg`, `photo_2.jpg` and `photo_blurred.jpg`: a printed team letter, the last one deliberately blurred (FR-D1-03).
