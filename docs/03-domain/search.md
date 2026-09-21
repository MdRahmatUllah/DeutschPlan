# Search engine

`data/repositories/search_repository.dart` running in drift's background isolate; UI debounce 120 ms.

Tiers, in order (BR-SEARCH-01…03):

1. **Exact** — `search_key = k OR search_key_alt = alt OR bangla = raw`, plus English rows whose synonym list contains the query exactly (via `words_fts` column filter then `checkMeaning == correct`).
2. **Starts with** — `words_fts MATCH '{search_key english bangla} : "k"*'` ordered by rank, freq bonus.
3. **Similar** — trigram candidates (`words_trigram MATCH` OR of query trigrams, limit 400) filtered by OSA edit distance ≤ 2 (≤ 3 if query > 5 chars) and ranked by distance, prefix bonus, freq.
4. **In sentences** — `examples_fts MATCH '"k"*'`, highlight via FTS `highlight()`.

Results are de-duplicated by uid across tiers; each tier is capped so the list stays under 40 rows plus 10 sentences. Recent searches (last 10) are kept in `settings.recent_searches` as JSON.

Web links: `SearchRepository.webLinks(term)` returns Duden, DWDS, Wiktionary, Linguee, Google URLs opened with `flutter_custom_tabs`.
