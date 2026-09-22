# content.db — course content (read-only)

Bundled at `assets/db/content.db`, copied to app-support storage on first run or when `meta.content_version` differs, then **attached** to the user database as schema `c`. Opened read-only; the app never writes to it.

## Tables

Column names are backticked; `tools/tests/test_schema.py` reads them out of this table and fails if the schema and this list disagree, so the backticks are load-bearing.

| Table | Key columns | Purpose |
| --- | --- | --- |
| `meta` | `key`, `value` | `content_version`, `built_at`, `sources`, `word_count`, `sublevel_week_boundaries` |
| `levels` | `code` (A1…C2), `ord`, `name`, `exam_target` | CEFR levels |
| `sublevels` | `code` (A1.1…C2.2), `level_code`, `ord` 1–12, `word_count`, `grammar_count` | Steps |
| `categories` | `id`, `name`, `description` | Word categories (from C-… tabs) |
| `words` | `uid` PK, `sublevel_code`, `level_code`, `seq`, `seq_in_sublevel`, `article`, `german`, `forms`, `pos`, `pron_bn`, `english`, `bangla`, `freq`, `category_id`, `source_week`, `collocations`, `synonyms_register`, `search_key`, `search_key_alt` | One row per entry |
| `word_examples` | (`word_uid`, `ord`) PK, `german`, `english` | Example sentences |
| `grammar_topics` | `uid` PK, `sublevel_code`, `level_code`, `seq`, `source_week`, `topic`, `rule`, `example_de`, `example_en`, `watch_out` | Grammar |
| `skill_prompts` | (`level_code`, `ord`), `text` | Weekly skills checklist |
| `interference_tips` | `word_uid`, `tip_en`, `tip_bn` | L1-specific traps (from CSV) |
| `words_fts` | FTS5 unicode61 remove_diacritics 2 over german, english, bangla, search_key | Exact / prefix search |
| `words_trigram` | FTS5 trigram over german, english, search_key | Fuzzy candidates |
| `examples_fts` | FTS5 unicode61 over german, english, with word_uid UNINDEXED | "In sentences" tier |

Indexes: `words(sublevel_code, seq_in_sublevel)`, `words(search_key)`, `words(search_key_alt)`, `words(category_id)`, `grammar_topics(sublevel_code, seq)`.

## Access from Dart

drift does not generate classes for an attached database, so content access is through `ContentDao` with **hand-written SQL in `.drift` files** (`lib/data/db/content.drift`) that drift type-checks against a declared schema (`content_schema.drift` mirrors the DDL). Typical queries:

```sql
wordsForStep: SELECT * FROM c.words WHERE sublevel_code = :code ORDER BY seq_in_sublevel;
exactMatches: SELECT * FROM c.words WHERE search_key = :k OR search_key_alt = :alt OR bangla = :raw;
prefixMatches: SELECT w.*, f.rank FROM c.words w JOIN (SELECT uid, rank FROM c.words_fts WHERE words_fts MATCH :q) f ON f.uid = w.uid ORDER BY f.rank LIMIT :n;
sentenceMatches: SELECT e.*, w.german AS head FROM c.examples_fts e JOIN c.words w ON w.uid = e.word_uid WHERE examples_fts MATCH :q LIMIT :n;
```

FTS `MATCH` refers to the virtual table name without the schema prefix; query strings are quoted (`"…"`) and column-filtered (`english : "haus"`).

## Update flow

1. On launch, read `content_version` from the bundled asset (probe copy) and from the installed file.
2. If different: overwrite the installed file, then compute `added/removed/changed` uids against `content_manifest.json` stored from the previous version (kept in app support).
3. Write the diff to `user.db.content_updates` (version, added, removed, changed_json, seen=0). Today shows the update card while `seen = 0`.
4. Removed uids: `word_state` rows are kept; plan generation and queries join to `c.words`, so they naturally disappear.
