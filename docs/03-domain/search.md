# Search engine

`data/repositories/search_repository.dart` running in drift's background isolate; UI debounce 120 ms.

Tiers, in order (BR-SEARCH-01…03):

1. **Exact** — `search_key = k OR search_key_alt = alt OR bangla = raw` (`raw` has Bangla's precomposed nukta letters taken apart, as `bangla` stores them, #716), plus English rows whose synonym list contains the query exactly (via `words_fts` column filter then `checkMeaning == correct`). A word keyed as the query is spelled (`search_key = k`, or its Bangla) comes before one matched only through `search_key_alt`, then higher frequency first (#734): "schön" lists schön before schon, and "Bär" Bär before bar, so Enter (FR-R1-02) and R2's check take the word typed.
2. **Starts with** — `words_fts MATCH '{search_key english bangla} : "k"*'` ordered by rank, freq bonus.
3. **Similar** — trigram candidates (`words_trigram MATCH` OR of query trigrams, limit 400) filtered by OSA edit distance ≤ 2 (≤ 3 if query > 5 chars) and ranked by distance, prefix bonus, freq.
4. **In sentences** — skipped for a one-character key (#736): one letter prefix-matches most of the course's sentences, and ranking them was the slowest search. Otherwise `examples_fts MATCH '"k"* OR german : ("alt"* OR "raw"* OR "resp"*)'`, ordered by rank, highlight via FTS `highlight()`. `examples_fts` folds umlauts but keeps ß, so the key alone missed "Tür" and "Straße" (#137). The German-only forms are the folded key, the query as typed (lower-cased), and the key respelled: ae/oe/ue → a/o/u, ss → ß, so "tuer" and "strasse" find "Tür" and "Straße". They search `german` only, because `"tur"*` in `english` is "Turn on the light". The key alone searches both columns, so "house" still finds the sentences that mean it.

**L2's step.** `search(query, step:)` puts the step into each tier's SQL (`:step IS NULL OR sublevel_code = :step`), before the caps, so a step's rows are not cut by the whole course's first rows.

Results are de-duplicated by uid across tiers; each tier is capped so the list stays under 40 rows plus 10 sentences. Recent searches (last 10) are kept in `settings.recent_searches` as JSON.

Web links: `SearchRepository.webLinks(term)` returns Duden, DWDS, Wiktionary, Linguee, Google URLs opened with `url_launcher`'s in-app browser view (`search.md`, FR-R1-06).
