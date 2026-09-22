-- The three full-text tables, one per tier of `docs/03-domain/search.md`.
--
-- Separate from content_schema.sql because they are derived: every row here is
-- a copy of a row in `words` or `word_examples`, and they are rebuilt from
-- those rather than written alongside them.
--
-- All three are ordinary (not external-content) FTS5 tables. External content
-- would halve the file, but it needs triggers on the source table to stay in
-- step — and content.db is read-only on the device, so there is nothing for a
-- trigger to react to. A plain copy cannot drift.

-- Tier 1 and 2: exact and starts-with.
--
-- `remove_diacritics 2` is the one that also folds combining marks on
-- precomposed letters, so "Tür" is findable as "Tur" here as well as through
-- search_key_alt. Bangla is unaffected: unicode61 does not decompose it.
--
-- `uid` is UNINDEXED — it is carried so a MATCH can join back to `words`, not
-- so anyone can search for a hash.
CREATE VIRTUAL TABLE words_fts USING fts5(
  uid UNINDEXED,
  german,
  english,
  bangla,
  search_key,
  tokenize = 'unicode61 remove_diacritics 2'
);

-- Tier 3: fuzzy candidates for a misspelling.
--
-- Trigram matches any three-character run, which is what finds "Strase" for
-- "Straße". It needs at least three characters in the query, so the search
-- screen falls back to the tiers above for shorter ones.
--
-- No bangla column: a trigram over Bangla conjuncts produces candidates that
-- look random to a reader, and tier 1 already matches Bangla exactly.
CREATE VIRTUAL TABLE words_trigram USING fts5(
  uid UNINDEXED,
  german,
  english,
  search_key,
  tokenize = 'trigram'
);

-- Tier 4: "in sentences".
--
-- `word_uid` UNINDEXED so a hit joins back to the headword it belongs to,
-- which is what the result row shows above the sentence.
CREATE VIRTUAL TABLE examples_fts USING fts5(
  word_uid UNINDEXED,
  german,
  english,
  tokenize = 'unicode61 remove_diacritics 2'
);
