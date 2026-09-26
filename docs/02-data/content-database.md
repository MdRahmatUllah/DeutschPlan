# content.db — course content (read-only)

Bundled at `assets/db/content.db`, copied to app-support storage on first run or when `meta.content_version` differs, then **attached** to the user database as schema `c`. Opened read-only; the app never writes to it.

## Tables

Column names are backticked; `tools/tests/test_schema.py` reads them out of this table and fails if the schema and this list disagree, so the backticks are load-bearing.

| Table | Key columns | Purpose |
| --- | --- | --- |
| `meta` | `key`, `value` | `content_version`, `built_at`, `sources`, `word_count`, `sublevel_week_boundaries` |
| `levels` | `code` (A1…C2), `ord`, `name`, `exam_target` | CEFR levels |
| `sublevels` | `code` (A1.1…C2.2), `level_code`, `ord` 1–12, `word_count`, `grammar_count` | Steps |
| `categories` | `id`, `name`, `description` | Word categories (from C-… tabs). `name` and `description` are course content, in English in both UI languages, as the words' English meanings are: the Bangla UI shows "Home & furniture" (owner, #425). A `name_bn` would come with its translations, through the workbooks and the pipeline. |
| `words` | `uid` PK, `sublevel_code`, `level_code`, `seq`, `seq_in_sublevel`, `article`, `german`, `forms`, `pos`, `pron_bn`, `english`, `bangla`, `freq`, `category_id`, `source_week`, `collocations`, `synonyms_register`, `search_key`, `search_key_alt` | One row per entry |
| `word_examples` | (`word_uid`, `ord`) PK, `german`, `english` | Example sentences |
| `grammar_topics` | `uid` PK, `sublevel_code`, `level_code`, `seq`, `source_week`, `topic`, `rule`, `example_de`, `example_en`, `watch_out`, `tags` | Grammar |
| `skill_prompts` | (`level_code`, `ord`), `prompt` | Empty (#294): the workbooks' only skills content is a fixed four-line weekly checklist, the same every week, not imported because nothing shows it. Kept in the schema; nothing reads it |
| `interference_tips` | `word_uid`, `tip_en`, `tip_bn` | L1-specific traps (from CSV) |
| `words_fts` | `uid` UNINDEXED, `german`, `english`, `bangla`, `search_key` — FTS5 `unicode61 remove_diacritics 2` | Exact / prefix search |
| `words_trigram` | `uid` UNINDEXED, `german`, `english`, `search_key` — FTS5 `trigram` | Fuzzy candidates |
| `examples_fts` | `word_uid` UNINDEXED, `german`, `english` — FTS5 `unicode61 remove_diacritics 2` | "In sentences" tier |

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
2. If different: overwrite the installed file, then compute `added/removed/changed` uids against `content_manifest.json` stored from the previous version (kept in app support). `changed` is a uid whose `words` digest (everything the learner sees) differs; `meaning` is a uid whose `meanings` digest (its English and Bangla meanings) differs. `english` is part of the uid (PIPE-03), so a new English meaning is a removed word and an added one, and only a new Bangla meaning reaches `meaning`. A kept manifest from before `meanings` gives no `meaning` uids.
3. Write the diff to `user.db.content_updates` (version, added, removed, changed_json = the `added`, `removed`, `changed` and `meaning` lists, seen=0). Today shows the update card while `seen = 0`; its counts are `added`, `removed` and `changed`. It is one card, for the newest unseen update: dismissing it marks that update and every older one seen (#477). Its counts are that update's alone, against the build before it, not against what the learner last saw: an older unseen update's changes aren't counted. Two updates between launches, the first adding a word and the second removing it and another, read "0 added · 2 removed" though the learner lost one word. Net counts across the unseen updates are the owner's call.
4. Removed uids: `word_state` rows are kept; plan generation and queries join to `c.words`, so they naturally disappear.
5. The `meaning` uids wear the *Updated* chip for 7 days (BR-CONTENT-02): from `recorded_at` (when this device saw the update, not the build's `version`) up to and including 168 h later, in UTC. A freq re-rank, a category move or a new example is in `changed`, not `meaning`, so it gets no chip. `ContentUpdater.recentlyUpdated(now)` gives the set, and `recentlyUpdated` (autoDispose Future) serves it to W1's header and T2's back (#451).
