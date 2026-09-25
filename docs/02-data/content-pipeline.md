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
```

Each workbook MUST contain the sheets **All Words**, **Grammar**, **W01** (for the skills checklist) and the **C-…** category tabs. Columns are read **by header name**, so column order may change; renaming a header requires updating `HEADER_MAP` in the tool.

One header per column, one row each — `HEADER_MAP` is checked against this table by `tools/tests/test_reader.py`, so a column added here and not there fails the build rather than being read as blank.

| Header in All Words | Field | Required | Notes |
| --- | --- | --- | --- |
| Article | `article` | no | |
| German | `german` | yes | |
| Plural / Forms | `forms` | no | |
| POS | `pos` | no | |
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

## Rules the pipeline enforces

- **PIPE-01** Level comes from the word's own `Level` cell, never from the week's phase label.
- **PIPE-02** Each level is split into `X.1`/`X.2` at the week boundary nearest the middle by word count; grammar is split by count in teaching order.
- **PIPE-03** `uid = sha1(level|german|pos|english)[:16]`. A collision inside one build appends the sequence number and is reported.
- **PIPE-04** `search_key` = lower-case, article stripped, punctuation dropped, umlauts → ae/oe/ue/ss, Latin diacritics removed; `search_key_alt` folds umlauts to a/o/u. The Dart `text_norm.dart` MUST produce identical output (shared test vectors in `tools/test_vectors.json`).
  - The article is dropped only as a whole leading word, so `Diebstahl` keeps its `die`, and `der` on its own stays — a learner can look that up.
  - Punctuation is an **explicit list** of the marks that appear in German and English, not a Unicode category test. The categories `Pc Pd Pe Pf Pi Po Ps` include the Bangla danda, and `search.md` matches `bangla = raw`, so Bangla has to come back byte for byte. `text_norm.dart` carries the same characters as a regex class and a test compares the two lists character by character.
  - Diacritics are stripped from Latin letters only, for the same reason: Bangla vowel signs are combining marks too.
- **PIPE-05** Cells beginning with `=`, `-`, `+` or `@` are stored as text (Excel would treat them as formulas); the tool warns.
- **PIPE-06** Example lines pair DE[i] with EN[i]; an unmatched DE line gets a null translation.
- **PIPE-07** `content_version` = build timestamp `YYYYMMDDHHMM`; also written to `content_manifest.json` with per-step counts and the uid list, which CI diffs against the previous build to produce the update summary shown on Today (BR-CONTENT-03).
- **PIPE-08** `verify_content.py` fails the build if: a required sheet/column is missing, a step has 0 words, a word has no example, a uid collision remains, FTS tables are empty, or a `gender`/`separable` tip is on a word of another class (#321).

## Outputs

- `content/build/content.db` — copied to `app/assets/db/content.db` by `make content`.
- `content/build/content_manifest.json` — counts, boundaries, uid list, build time.

## Adding a fifth workbook

1. Drop the `.xlsx` at the repository root and add it to `manifest.yaml`.
2. `make content` → runs the tool, verification, and copies the asset.
3. Run `flutter test test/db/` (schema and count assertions read the manifest).
4. Commit the workbook, the manifest and the regenerated asset together.

## Interference tips

`content/interference_tips.csv` columns: `match_type (uid|german|pattern), match, tip_en, tip_bn, tags`. Patterns are regexes over `german` (e.g. `^bekommen$`, `^seit\b`). The pipeline resolves them at build time into `interference_tips(word_uid, tip_en, tip_bn)` so the app never runs regexes. A tip tagged `gender` attaches to nouns only and one tagged `separable` to verbs only (#321): a pattern matches the spelling, and "Every -chen noun is das" is false on *versuchen*.
