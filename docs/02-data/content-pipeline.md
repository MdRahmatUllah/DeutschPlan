# Content pipeline: Excel → content.db

Excel is the authoring tool; the app never opens a workbook. `tools/excel_to_sqlite.py` compiles every workbook listed in `content/manifest.yaml` into one read-only SQLite file that ships as an asset.

## Inputs

```
content/manifest.yaml
  workbooks:
    - file: data/German_A1_Tracker.xlsx
    - file: data/German_A2_Tracker.xlsx
    - file: data/German_B1_Tracker.xlsx
    - file: data/German_B2_Tracker.xlsx
    - file: data/German_C1_Tracker.xlsx
    - file: data/German_C2_Tracker.xlsx
    # add more here; order = fallback level order for grammar without a level
  tips: content/interference_tips.csv
  corrections: content/corrections.yaml   # reviewed fixes to the workbooks, below
```

Each workbook MUST contain the sheets **All Words**, **Grammar** and the **C-…** category tabs. A category's name is its tab's title cell after `Category:` ("Category: Regional variation: AT & CH"), or else the tab name after `C-`: Excel cuts a sheet name at 31 characters and forbids `:` and `/`, so a long name only survives in the title cell, and that is the name the words' Category cells use (#636). The week sheets (**W01**…) are the learner's own tracker and are not read: the only skills content is the same fixed four-line "Weekly skills — put an x when done" block at the foot of every week (listen, read, write, speak), which nothing shows, so `skill_prompts` is written empty (#294). Reading W01's cells had filled it with sheet headers and spreadsheet instructions. Columns are read **by header name**, so column order may change; renaming a header requires updating `HEADER_MAP` in the tool.

A renamed header is a column the build no longer reads, so the build refuses one (#714):

- A workbook whose *All Words* or *Grammar* lacks a column the maps read stops the build, naming the file, the columns and the headers in that row it did not know. Every column of the maps, not only those another workbook has: a header renamed in every workbook at once (a find-and-replace across the trackers) leaves none carrying it (#837). A column a workbook never had is listed under its entry's `without:` in `content/manifest.yaml` (none does today: since the A1+A2+B1 book was split into three, every tracker carries Collocations and Synonyms / register), by field name: a list, or one field as a string (`without: collocations`). A column no workbook has is listed under every entry's. `--allow-missing-columns` builds past it once, and each workbook without the column ships its words without it.
- The German, English, Level and POS headers are required in every workbook, whatever the others carry: POS is part of the uid (PIPE-03), and a renamed POS header would give every word of the workbook a new one. The POS *cell* may be blank.
- Every header no map reads is reported (`warning: unknown header: …`), except the tracker's own `ID`, `Status`, `Times logged`, `#` and `Notes`.

One header per column, one row each — `HEADER_MAP` is checked against this table by `tools/tests/test_reader.py`, so a column added here and not there fails the build rather than being read as blank.

| Header in All Words | Field | Required | Notes |
| --- | --- | --- | --- |
| Article | `article` | no | |
| German | `german` | yes | |
| Plural / Forms | `forms` | no | |
| POS | `pos` | yes | the header; the cell may be blank (#714) |
| Pronunciation (Bangla) | `pron_bn` | no | |
| English | `english` | yes | or `Meaning (English)` |
| Bangla meaning | `bangla` | no | or `Meaning (Bangla)` |
| Freq | `freq` | no | 1–5 |
| Level | `level` | yes | A1…C2 |
| Category | `category` | no | |
| Week | `week` | no | used for the step split |
| Examples (DE) | `examples_de` | no | one sentence per line |
| Examples (EN) | `examples_en` | no | one sentence per line, paired by position; or `Examples (English)` |
| Collocations | `collocations` | no | |
| Synonyms / register | `synonyms_register` | no | |

Grammar sheet, same contract:

| Header in Grammar | Field | Required |
| --- | --- | --- |
| Week | `week` | no |
| Level | `level` | no |
| Topic | `topic` | yes |
| Rule | `rule` | no |
| Example (DE) | `example_de` | no |
| Example (EN) | `example_en` | no |
| Watch out | `watch_out` | no |

`Topic`, `Rule`, `Example (EN)` and `Watch out` are English's, and may be spelt `Topic (English)`, `Rule (English)`, `Example (English)` and `Watch out (English)`. Every other meaning language's columns are read by pattern, below.

## Meaning languages

German is the language learnt; a meaning language is one its words are explained in (#1080, epic #1085). Each language X has columns of its own, named by its English name, which the pipeline finds by their headers, beside the tables above:

| Sheet | Columns | Filled |
| --- | --- | --- |
| All Words | `Meaning (X)`, `Pronunciation (X)` | every row |
| All Words | `Examples (X)` | the example lines' translations, one line per German line (PIPE-06); when the column is there, every German line |
| Grammar | `Topic (X)`, `Rule (X)`, `Example (X)`, `Watch out (X)` | when the columns are there, every row where English's `Topic`, `Rule` or `Watch out` (the German `Example (DE)`, for `Example (X)`) has text |

- Today's headers are English's and Bangla's: `English` is `Meaning (English)`, `Examples (EN)` is `Examples (English)`, `Bangla meaning` is `Meaning (Bangla)`, and `Pronunciation (Bangla)` is already in the new form. English has no `Pronunciation (English)` yet (#1082), and Bangla no examples or grammar columns: a part a language has no columns for falls back to English's in the app, and its tables have no rows for it (#598).
- A language's code, own name and script come from `LANGUAGES` in `tools/pipeline_steps.py`, keyed by the English name in the header: `Russian` is `ru`, "Русский", `Cyrl`. The table carries the common languages; a name it does not know stops the build and lists the ones it does.
- A language has the same columns in every workbook, or the build stops, naming the workbook and the headers it lacks, as for a renamed header (#714). None has a `without:`.
- **The gate (PIPE-08).** A language ships only when it is 100 % complete in every part it has, meaning and pronunciation always among them. One that is not is **held back**: none of its text is written, and the build says what is missing, in total and per workbook: `language Russian (ru): meanings 5,236/5,236, pronunciations 5,236/5,236, examples 9,870/10,545, held back (German_B2_Tracker.xlsx: examples 8,670/9,045; …). --allow-partial ru builds it, for testing only`. `--allow-partial <code>` builds it as it is, for testing; a partial language never ships. English always ships: it is the course's own text. The build prints a line for every language, shipped or not.
- What ships is in `content.db`'s `course_languages`, `word_meanings`, `word_example_translations`, `grammar_translations` and `word_tips`, and `meanings_fts` searches every shipped language's meanings (`content-database.md`). English's and Bangla's texts are also in the old columns (`words.english`, `bangla`, `pron_bn`, …) until the app reads the new tables (#1081).
- A correction (`content/corrections.yaml`) sets English's and Bangla's texts by their fields (`english`, `bangla`, `pron_bn`, `example_en_N`); another language's are fixed in the workbook.
- Uids are made of the German, part of speech, English and level (PIPE-03), and the manifest's digests of English and Bangla: adding a language changes neither, so a content update that adds one keeps every learner's progress and marks no word *Updated*.

### Adding a meaning language

1. Add `Meaning (X)` and `Pronunciation (X)` to *All Words* in every workbook, and `Examples (X)` and the four Grammar columns if the language is to have its own examples and grammar. X is the language's English name; if the build says it does not know it, add it to `LANGUAGES` in `tools/pipeline_steps.py` (code, own name, script).
2. Fill them. `python tools/excel_to_sqlite.py` prints the language's counts on every build, and holds it back until every one is complete; `--allow-partial <code>` builds a partial one to look at in the app.
3. Add its interference tips as a `tip_<code>` column of `content/interference_tips.csv`.
4. Build, verify and commit the asset as for any content change (`adding-content.md`). No code changes: the app offers the languages `course_languages` lists (#1081).

## Corrections

The workbooks are the owner's, and no tool writes them: openpyxl drops their charts (#545). A fix to a row goes into `content/corrections.yaml` instead, a reviewed file in the repo, and the pipeline applies it after reading the workbooks and before anything else looks at the words (the duplicate drop, the step split, the uids).

```yaml
words:
  "5429a4b3f170a42e":            # the row's uid as the workbook has it, quoted
    why: "#628: personal details replaced with generic ones"
    example_de_1: "Die Postleitzahl von Berlin-Mitte ist 10115."
    example_en_1: "The postcode of Berlin-Mitte is 10115."
```

- The key is the uid the row gets from its cells as read (PIPE-03, without a collision suffix), in quotes: an unquoted all-digit uid is a YAML number.
- Every entry has a `why`: what the workbook got wrong, and the issue.
- An entry sets any column in `HEADER_MAP` by its field name (`german`, `article`, `forms`, `english`, …); `example_de_N` / `example_en_N` replace line N of the example cells (as PIPE-06 pairs them), and N one past the last line adds one; `kind: note|compare|vocab` overrides PIPE-10's heuristic (the reviewed override list); `delete: true` drops the row; `merge_into: "<uid>"` drops it as a duplicate of the row with that key (PIPE-12), which takes its learners' progress (PIPE-09) and fills its own blank article, forms, pronunciation, Bangla, collocations and synonyms from it (the B1 workbook has no collocations; its words' twins in B2 and C1 do), never its examples.
- A correction that changes the German, part of speech, English or level changes the uid; PIPE-09 links the old one to the new one exactly, so learners keep their progress.
- A key that matches no row or more than one, a field the pipeline does not read, or an example line past the end fails the build: the workbook changed under the correction, and it has to be looked at again.
- A grammar topic's text is corrected under `grammar:`, keyed by the topic's uid as built (`grammar_topics.uid`), after the grammar uids are made: `rule`, `example_de`, `example_en` and `watch_out`, never its level or title, which make the uid (#637): those change in the workbook, and PIPE-09 links the topic's old uid to its new one (#808). A key that matches no topic, or another field, fails the build. The workbooks' grammar text was written for the author's tracker ("revise weeks 12–16", "topics marked 'In progress'"), which the app does not have: such text is rewritten here to stand on its own.
- A link PIPE-09 made that is wrong is refused, and one it cannot make is pinned, under `links:`, keyed by the committed course's uid (a word's or a grammar topic's), with a `why` (#807). `refuse: true` links the uid to nothing: it is removed, and the build stops unless `--allow-removed`. `to: "<uid>"` links it to that uid of this build, a word's to a word and a topic's to a topic; a uid this build does not have fails the build. An entry carries one of the two and nothing else but `why`. An entry for a uid the committed course still has, or never had, does nothing, and the build says so (`stale link: …`): it is deleted once the course it was written for is committed.

```yaml
links:
  "0123456789abcdef":            # the committed course's uid, quoted
    why: "#807: Leiter (leader) dropped on purpose; the ladder added is another word"
    refuse: true
  "fedcba9876543210":
    why: "#808: the topic's title rewritten"
    to: "0f1e2d3c4b5a6978"
```

- The repository is public: an entry holds the new text only, never the text it replaces.

## Rules the pipeline enforces

- **PIPE-01** Level comes from the word's own `Level` cell, never from the week's phase label.
- **PIPE-02** Each level is split into `X.1`/`X.2` at the week boundary nearest the middle by word count; grammar is split by count in teaching order. Once a course has shipped, a level keeps its boundary (#923): the build takes each level's boundary week from the committed course's manifest (`boundaries`; `--previous DIR`'s), so a row added or dropped never moves the level's other words between steps under learners. When the middle has moved away from it the build says so, one line per level (`boundary kept: B2.2 starts at week 21, as shipped; split anew it would start at week 20 (--move-boundaries)`), and `--move-boundaries` splits every level anew. A kept boundary that would leave a step with no words stops the build. With no committed course, a level splits at its middle. A level keeps its grammar split too (#970): X.2 starts at the level's first topic, in teaching order, that the committed course has in X.2 (its `content.db`'s `grammar_topics.sublevel_code`, by uid), so a topic added or dropped moves no other topic between steps, the first X.2 topic dropped included (the next one that shipped there takes over). A new topic takes the step of its place. The split is read from the committed course's rows rather than kept as one uid in the manifest, so that a dropped first X.2 topic doesn't lose it. When the kept split is not the one by count the build says so (`grammar boundary kept: B1.2 starts at topic 5 of 8, '…', as shipped; split anew it would start at topic 4 (--move-boundaries)`); `--move-boundaries` splits grammar anew as well. A level with none of its X.2 topics left splits by count. A split that would still move a shipped topic stops the build, one line per topic (`grammar topic moved: 'Relativsätze' B1.1 -> B1.2`), and so does a split that would leave X.1 with no topics. The first happens when a level is reordered, with a shipped X.2 topic put before X.1 ones; the second when all of a level's shipped X.1 topics are dropped. Keep the shipped topics in their order, or rerun with `--move-boundaries`.
- **PIPE-03** `uid = sha1(level|german|pos|english)[:16]`. A collision inside one build hashes again with its occurrence number appended (the second word to hash to a uid gets 2, the third 3; not the reading-order `seq`, which an unrelated insertion would shift) and is reported. Each part is NFC-normalised with its runs of whitespace collapsed to one space first, so an NFD paste or a double space is the same word (#648; no uid changed when this came in).
  - An article typed into a noun's German cell with the Article cell empty ("das Gegenargument") moves into `article` (#287). It moves after the uid is made, so the uid stays that of the cell as authored. A pair ("die Rente ↔ die Miete", "die Kohle / die Kohlen") keeps its articles.
  - A row that the move would make the same as another row in every field the uid is made of ("der Satzakzent" beside "Satzakzent", same level, part of speech and English) is a duplicate: the build drops it before the step split, keeps the clean row, and warns `dropped duplicate: <workbook> All Words row <n> (…): dropped a duplicate of '<word>' (…, kept). Delete row <n> in the workbook.` The dropped row's uid leaves the course, and a learner's progress on it with it (#407).
- **PIPE-04** `search_key` = lower-case, article stripped, punctuation dropped, umlauts → ae/oe/ue/ss, Latin diacritics removed; `search_key_alt` folds umlauts to a/o/u. The Dart `text_norm.dart` MUST produce identical output (shared test vectors in `tools/test_vectors.json`; its `latin_ranges` holds the two to every letter of U+00C0–U+024F and U+1E00–U+1EFF, and whitespace is Python's `str.isspace` on both sides, #716).
  - The article is dropped only as a whole leading word, so `Diebstahl` keeps its `die`, and `der` on its own stays — a learner can look that up.
  - Punctuation is an **explicit list** of the marks that appear in German and English, not a Unicode category test. The categories `Pc Pd Pe Pf Pi Po Ps` include the Bangla danda, and `search.md` matches `bangla = raw`, so Bangla has to come back byte for byte. `text_norm.dart` carries the same characters as a regex class and a test compares the two lists character by character.
  - Diacritics are stripped from Latin letters only, for the same reason: Bangla vowel signs are combining marks too.
- **PIPE-05** Cells beginning with `=`, `-`, `+` or `@` are stored as text (Excel would treat them as formulas); the tool warns.
- **PIPE-06** Example lines pair DE[i] with EN[i]; an unmatched DE line gets a null translation.
- **PIPE-07** `content_version` = build timestamp `YYYYMMDDHHMMSS`, UTC (to the second since #722; a 14-digit stamp sorts after every 12-digit one before it, so an installed minute-precision course still updates). The build reads the clock once: `meta.built_at`, the manifest's `built_at` and `content_version` are the same instant (#718); also written to `content_manifest.json` with per-step counts and the uid list — each uid with a digest of what the learner sees (`words`) and one of its meanings (`meanings`, for BR-CONTENT-02's *Updated* chip) — and the `aliases` of PIPE-09; `sources` names each workbook with its SHA-256, as `meta.sources` does, so an asset says which bytes it was built from (#634). The app diffs it against the manifest it kept from the previous version to produce the update summary shown on Today (BR-CONTENT-03), and the build prints the same diff against the committed asset.
- **PIPE-09** A word whose uid changed keeps the learner's progress (#648). Before writing, the build compares its words with the committed course (`app/assets/db/content.db`, or `--previous DIR`) and links each uid that is gone to the added uid that is the same word. A row `content/corrections.yaml` changed is linked exactly, from the uid it had as read to the one it has now, whatever the correction changed (#629). Otherwise, first the same level, German and part of speech, the nearest English winning (a gloss fix); then the same German, part of speech and English (a re-levelled word). German, part of speech and English are compared NFC, whitespace-collapsed and case-folded, so a part of speech typed `Noun` or an article moved into its column is the same word too. Each added uid takes one old uid at most, best match first across every pair, so two senses of a word re-glossed in one build each get their own nearest English, whichever uid sorts first (#807). A link that is wrong (a homonym dropped on purpose and another sense added at its level: *Leiter*, leader, and *Leiter*, ladder) is refused, and one the rules cannot make is pinned, under `links:` in `content/corrections.yaml` ("Corrections"). A grammar topic whose uid (`sha1(level|topic)`) changed is linked the same way (#808): its title changed only in case or spacing, or it moved level under the same title. A renamed topic is not guessed at, as the nearest title in a level is another topic: it is pinned under `links:`. The links go into the manifest's `aliases` (old uid → uid now), with every earlier build's links followed through this build's, so a learner who skipped a version still lands on the word as it is now; `ContentUpdater` moves their rows along them on install (`content-database.md`, update flow), a topic's as a word's. Every link is printed (`warning: uid link: …`, `uid link: grammar …` for a topic). A uid that is gone with nothing to link it to stops the build (`warning: removed: …`, one line each): restore the word or topic, link it under `links:`, or rerun with `--allow-removed` if dropping learners' progress on it is intended.
- **PIPE-12** A word is taught once (#635). The same German, part of speech and English (case-folded) in two levels is listed in the build report, one line per word: `cross-level duplicate: '<word>' (<pos>, '<english>') in <level> (<workbook> row <n>), …`; the later rows are merged into the first with `merge_into` in `content/corrections.yaml`, or kept on purpose. The same German and part of speech twice in one level ("Kunde: customer" and "Kunde: client / customer") fails PIPE-08, unless the two are different words, listed in `HOMONYMS` in `verify_content.py` (ihr, einfach, Sendung, Gericht, Anlage, Belastungsgrenze). The same German and part of speech in two levels, whatever the English, fails PIPE-08 too (#921), unless each level teaches a sense of its own: those are listed in `SENSES` in `verify_content.py`, and each one's English names its sense (*billig*: cheap, and shoddy or facile; *Stück*: a piece, and a play; *Viertel*: a quarter, and a neighbourhood; eighteen words). German is compared as written: *Sie* and *sie* are two words. The review's decisions (#635, #921): a word in two levels stays in the first and the rest merge into it, whether or not their English is worded alike; one level's twin glossed another way merges into the one met first; a second sense that is its own word stays (the six homonyms and the eighteen `SENSES`; *Widerspruch* is the objection in B1, where C1's formal objection merged, and the contradiction in B2). A row that stays takes into its English a sense that its merged twin glossed and it lacked, and its Bangla with it (#924: A1's *Kunde* is "customer / client"); a synonym or a register note is not a sense.
- **PIPE-11** An example of a word to learn that does not say it (no gap, and no word sharing the first three letters of the headword's words or its forms') is a warning, one line each: `example without its word: <workbook> row <n> (<word>) example <k>: '<sentence>'` (#631). A strong verb's own forms ("Ich bin", "wies … ab") and an example showing a rule are left on purpose; anything else is rewritten in `content/corrections.yaml`.
- **PIPE-10** Each word gets a `kind` (BR-CONTENT-04, #630), from its headword's shape unless a correction sets it: `note` for word formation (an affix, "-ung" or "be-", but not "Hals- und Beinbruch"; *Präfix*, *Suffix*, *Wortbildung*, *Wortfamilie*), a construction ("seit + Präsens", "Adjektiv → Nomen") or an exam module ("Hören (C2)"); `compare` for "machen ↔ tun" and "sagen vs. behaupten"; else `vocab`. A grammar rule's name has no shape ("Vorfeldbesetzung", "Artikelpflicht"): `content/corrections.yaml` marks it `kind: note`, and a comparison whose words are separated by " / ", which reads as a set of synonyms ("sparsam / geizig", thrifty vs. stingy), `kind: compare` (#974). The build prints the counts (`kinds: 5433 vocab, 99 note, 61 compare`). `meta.word_count`, `sublevels.word_count` and the manifest's `counts.words` and per-step `words` count vocab only; the uid list has every row.
- **PIPE-08** A meaning language less than 100 % complete is held back, not written ("Meaning languages", #1080). `verify_content.py` fails the build if: a required sheet/column is missing, a step has 0 words, a word has no example, a uid collision remains, FTS tables are empty or not an index of their table as it is (FTS5's integrity check: a row changed or renumbered after the build, #712), a `gender`/`separable` tip is on a word of another class (#321), a single noun still has its article in the German cell (#287), a category has no words (#636: a tab whose name the Category column does not use), a noun has no article (#633; except the holidays in `NO_ARTICLE` and a set of nouns, "Grund / Ursache", "Mitleid ↔ Sympathie", "Geld vs. Kohle"), a phrase has one (the Articles quiz would ask "___ Fehler machen"; a noun phrase such as "die Auseinandersetzung mit" is a `noun`), a two-part verb or phrase `forms` cell is not `3rd person · hat|ist Perfekt`, one auxiliary and no brackets (#632: the Forms quiz expects part two verbatim), a headword is two words, "X — Y" (#629: every other column of such a row was about Y; only the word-formation notes, "X — Präfix …", "X — Wortbildung …" and "X — Negation …", keep that shape), an example sentence is starred as ungrammatical ("nicht: *Ich bin arbeitend", #630: TTS reads it out as a model), a word to learn has no example the cloze can gap (#631: no cloze card, practice sentence or gap fill would ever show it; `tools/cloze.py` is the app's `clozeGap`, held to it by `tools/cloze_vectors.json`, which both test suites run), a level teaches the same German and part of speech twice (PIPE-12, #635), or two levels do and it is not one of the `SENSES` (#921), or a term of the denylist is anywhere in the course's text (#628). The denylist is `data/denylist.txt`, one term per line, `#` for comments, matched case-insensitively in every `TEXT` column of every table; it lives outside git (`data/` is ignored) and outside the database, so it does not publish what it guards against. A failure names the term by its line number, never by the term, and the rows by uid. Without the file the gate says it did not run. `tools/tests/test_shipped_content.py` runs every gate on the committed asset, and plants a defect in a copy of it for each of several gates, so a course that fails verify cannot be committed unnoticed (#634).

## Outputs

- `content/build/content.db` — copied to `app/assets/db/content.db` by hand after the build (step 2 below).
- `content/build/content_manifest.json` — counts, boundaries (kept by the next build, PIPE-02), uid list with its `words` and `meanings` digests, the `aliases` of PIPE-09, build time.

## Adding a workbook

1. Put the `.xlsx` in `data/` and add it to `content/manifest.yaml` (and to the workbook list in `tools/tests/test_shipped_content.py`). A column the maps read that the workbook doesn't have goes under its entry's `without:`, by field name (`without: [collocations, synonyms_register]`), or the build stops on it as a renamed header (#714).
2. Build, verify, copy: `python tools/excel_to_sqlite.py`, `python tools/verify_content.py`, then copy `content/build/content.db` and `content/build/content_manifest.json` to `app/assets/db/`.
3. Run `python -m pytest tools/tests -q` and, from `app/`, `flutter test test/db/` (schema and count assertions read the manifest).
4. Commit `content/manifest.yaml` and the regenerated asset together, not the workbook. The workbooks stay out of git until the owner makes the repository private (#634): until then they live in `data/`, which is git-ignored, and what the repository records is each one's SHA-256, in `meta.sources` and the manifest's `sources`.

## Interference tips

`content/interference_tips.csv` columns: `match_type (uid|german|pattern), match, tip_<code>…, tags` (today `tip_en` and `tip_bn`), in UTF-8 with or without Excel's BOM (#697). Each `tip_<code>` column is the tip for that meaning language's speakers (#1080): a row may fill one language only, as a Russian false friend is not a Bangla one, but at least one; a code `LANGUAGES` does not know stops the build. Patterns are regexes over `german` (e.g. `^bekommen$`, `^seit\b`). The pipeline resolves them at build time into `word_tips(word_uid, lang, tip)`, for the languages that ship, and the rows with English into `interference_tips(word_uid, tip_en, tip_bn)` until the app reads `word_tips` (#1081), so the app never runs regexes. A tip that matches no word stops the build (`unmatched tip: …`, #634): it is authored text that would never ship; fix the match, or delete the row until the course has the word. A tip tagged `gender` attaches to nouns only and one tagged `separable` to verbs only (#321): a pattern matches the spelling, and "Every -chen noun is das" is false on *versuchen*. The stress tips ("stress decides whether this verb separates") are one per verb they are true of, each giving that verb's two readings (#933), for the verbs with both (*übersetzen*, *überholen*, *umgehen*, *umfahren*, *unterstellen*, *unterschlagen*, *durchbrechen*), never a prefix: most *über-*, *um-*, *unter-* and *durch-* verbs have one reading only, *überzeugen* never separating and *umsteigen* always (#637).
