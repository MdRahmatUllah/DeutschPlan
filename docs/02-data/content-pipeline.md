# Content pipeline: Excel → content.db

Excel is the authoring tool; the app never opens a workbook. `tools/excel_to_sqlite.py` compiles every workbook listed in `content/manifest.yaml` into one read-only SQLite file that ships as an asset.

## Inputs

```
content/manifest.yaml
  workbooks:
    - file: German_B1_Tracker.xlsx     # contains A1, A2, B1 (level per word row)
    - file: German_B2_Tracker.xlsx
    - file: German_C1_Tracker.xlsx
    - file: German_C2_Tracker.xlsx
    # add more here; order = fallback level order for grammar without a level
  tips: content/interference_tips.csv
  corrections: content/corrections.yaml   # reviewed fixes to the workbooks, below
```

Each workbook MUST contain the sheets **All Words**, **Grammar** and the **C-…** category tabs. The week sheets (**W01**…) are the learner's own tracker and are not read: the only skills content is the same fixed four-line "Weekly skills — put an x when done" block at the foot of every week (listen, read, write, speak), which nothing shows, so `skill_prompts` is written empty (#294). Reading W01's cells had filled it with sheet headers and spreadsheet instructions. Columns are read **by header name**, so column order may change; renaming a header requires updating `HEADER_MAP` in the tool.

A renamed header is a column the build no longer reads, so the build refuses one (#714):

- A workbook whose *All Words* or *Grammar* lacks a column that another workbook's has stops the build, naming the file, the column and the headers in that row it did not know. A column a workbook never had is listed under its entry's `without:` in `content/manifest.yaml` (B1 has no Collocations or Synonyms / register), by field name; `--allow-missing-columns` builds past it once, and each workbook without the column ships its words without it.
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
| English | `english` | yes | |
| Bangla meaning | `bangla` | no | |
| Freq | `freq` | no | 1–5 |
| Level | `level` | yes | A1…C2 |
| Category | `category` | no | |
| Week | `week` | no | used for the step split |
| Examples (DE) | `examples_de` | no | one sentence per line |
| Examples (EN) | `examples_en` | no | one sentence per line, paired by position |
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
- An entry sets any column in `HEADER_MAP` by its field name (`german`, `article`, `forms`, `english`, …); `example_de_N` / `example_en_N` replace line N of the example cells (as PIPE-06 pairs them), and N one past the last line adds one; `delete: true` drops the row.
- A correction that changes the German, part of speech, English or level changes the uid; PIPE-09 links the old one to the new one exactly, so learners keep their progress.
- A key that matches no row or more than one, a field the pipeline does not read, or an example line past the end fails the build: the workbook changed under the correction, and it has to be looked at again.
- The repository is public: an entry holds the new text only, never the text it replaces.

## Rules the pipeline enforces

- **PIPE-01** Level comes from the word's own `Level` cell, never from the week's phase label.
- **PIPE-02** Each level is split into `X.1`/`X.2` at the week boundary nearest the middle by word count; grammar is split by count in teaching order.
- **PIPE-03** `uid = sha1(level|german|pos|english)[:16]`. A collision inside one build appends the sequence number and is reported. Each part is NFC-normalised with its runs of whitespace collapsed to one space first, so an NFD paste or a double space is the same word (#648; no uid changed when this came in).
  - An article typed into a noun's German cell with the Article cell empty ("das Gegenargument") moves into `article` (#287). It moves after the uid is made, so the uid stays that of the cell as authored. A pair ("die Rente ↔ die Miete", "die Kohle / die Kohlen") keeps its articles.
  - A row that the move would make the same as another row in every field the uid is made of ("der Satzakzent" beside "Satzakzent", same level, part of speech and English) is a duplicate: the build drops it before the step split, keeps the clean row, and warns `dropped duplicate: <workbook> All Words row <n> (…): dropped a duplicate of '<word>' (…, kept). Delete row <n> in the workbook.` The dropped row's uid leaves the course, and a learner's progress on it with it (#407).
- **PIPE-04** `search_key` = lower-case, article stripped, punctuation dropped, umlauts → ae/oe/ue/ss, Latin diacritics removed; `search_key_alt` folds umlauts to a/o/u. The Dart `text_norm.dart` MUST produce identical output (shared test vectors in `tools/test_vectors.json`).
  - The article is dropped only as a whole leading word, so `Diebstahl` keeps its `die`, and `der` on its own stays — a learner can look that up.
  - Punctuation is an **explicit list** of the marks that appear in German and English, not a Unicode category test. The categories `Pc Pd Pe Pf Pi Po Ps` include the Bangla danda, and `search.md` matches `bangla = raw`, so Bangla has to come back byte for byte. `text_norm.dart` carries the same characters as a regex class and a test compares the two lists character by character.
  - Diacritics are stripped from Latin letters only, for the same reason: Bangla vowel signs are combining marks too.
- **PIPE-05** Cells beginning with `=`, `-`, `+` or `@` are stored as text (Excel would treat them as formulas); the tool warns.
- **PIPE-06** Example lines pair DE[i] with EN[i]; an unmatched DE line gets a null translation.
- **PIPE-07** `content_version` = build timestamp `YYYYMMDDHHMMSS`, UTC (to the second since #722; a 14-digit stamp sorts after every 12-digit one before it, so an installed minute-precision course still updates). The build reads the clock once: `meta.built_at`, the manifest's `built_at` and `content_version` are the same instant (#718); also written to `content_manifest.json` with per-step counts and the uid list — each uid with a digest of what the learner sees (`words`) and one of its meanings (`meanings`, for BR-CONTENT-02's *Updated* chip) — and the `aliases` of PIPE-09. The app diffs it against the manifest it kept from the previous version to produce the update summary shown on Today (BR-CONTENT-03), and the build prints the same diff against the committed asset.
- **PIPE-09** A word whose uid changed keeps the learner's progress (#648). Before writing, the build compares its words with the committed course (`app/assets/db/content.db`, or `--previous DIR`) and links each uid that is gone to the added uid that is the same word. A row `content/corrections.yaml` changed is linked exactly, from the uid it had as read to the one it has now, whatever the correction changed (#629). Otherwise, first the same level, German and part of speech, the nearest English winning (a gloss fix); then the same German, part of speech and English (a re-levelled word). German, part of speech and English are compared NFC, whitespace-collapsed and case-folded, so a part of speech typed `Noun` or an article moved into its column is the same word too. Each added uid takes one old uid at most. The links go into the manifest's `aliases` (old uid → uid now), with every earlier build's links followed through this build's, so a learner who skipped a version still lands on the word as it is now; `ContentUpdater` moves their rows along them on install (`content-database.md`, update flow). Every link is printed (`warning: uid link: …`). A uid that is gone with nothing to link it to stops the build (`warning: removed: …`, one line each): restore the word, or rerun with `--allow-removed` if dropping learners' progress on it is intended.
- **PIPE-08** `verify_content.py` fails the build if: a required sheet/column is missing, a step has 0 words, a word has no example, a uid collision remains, FTS tables are empty, a `gender`/`separable` tip is on a word of another class (#321), a single noun still has its article in the German cell (#287), a two-part verb or phrase `forms` cell is not `3rd person · hat|ist Perfekt`, one auxiliary and no brackets (#632: the Forms quiz expects part two verbatim), a headword is two words, "X — Y" (#629: every other column of such a row was about Y; only the word-formation notes, "X — Präfix …", "X — Wortbildung …" and "X — Negation …", keep that shape), or a term of the denylist is anywhere in the course's text (#628). The denylist is `data/denylist.txt`, one term per line, `#` for comments, matched case-insensitively in every `TEXT` column of every table; it lives outside git (`data/` is ignored) and outside the database, so it does not publish what it guards against. A failure names the term by its line number, never by the term, and the rows by uid. Without the file the gate says it did not run.

## Outputs

- `content/build/content.db` — copied to `app/assets/db/content.db` by `make content`.
- `content/build/content_manifest.json` — counts, boundaries, uid list with its `words` and `meanings` digests, the `aliases` of PIPE-09, build time.

## Adding a fifth workbook

1. Drop the `.xlsx` at the repository root and add it to `manifest.yaml`.
2. `make content` → runs the tool, verification, and copies the asset.
3. Run `flutter test test/db/` (schema and count assertions read the manifest).
4. Commit the workbook, the manifest and the regenerated asset together.

## Interference tips

`content/interference_tips.csv` columns: `match_type (uid|german|pattern), match, tip_en, tip_bn, tags`. Patterns are regexes over `german` (e.g. `^bekommen$`, `^seit\b`). The pipeline resolves them at build time into `interference_tips(word_uid, tip_en, tip_bn)` so the app never runs regexes. A tip tagged `gender` attaches to nouns only and one tagged `separable` to verbs only (#321): a pattern matches the spelling, and "Every -chen noun is das" is false on *versuchen*.
