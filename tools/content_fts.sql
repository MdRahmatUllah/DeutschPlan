-- The full-text tables: one per tier of `docs/03-domain/search.md`, and the
-- meaning languages' (#1080).
--
-- Separate from content_schema.sql because they are derived: each indexes the
-- rows of `words`, `word_examples` or `word_meanings`, and is rebuilt from them rather than
-- written alongside them.
--
-- All are external-content FTS5 tables (#712): the index only, the text
-- read from `words` and `word_examples` by rowid when a query needs it (the
-- `uid` a MATCH joins back on, `highlight()`). A copy of the text in each was
-- 1.9 MB of a 7.5 MB file. External content needs triggers to stay in step
-- with a table that changes, and content.db is read-only on the device, so
-- the build fills them once, last, with FTS5's `rebuild` (`content_writer`),
-- and PIPE-08 runs FTS5's integrity check of each index against its table:
-- anything that renumbered the rows after (a VACUUM) fails the build.

-- Tier 1 and 2: exact and starts-with.
--
-- `remove_diacritics 2` is the one that also folds combining marks on
-- precomposed letters, so "Tür" is findable as "Tur" here as well as through
-- search_key_alt.
--
-- `categories` adds the marks (Mn, Mc) to what a token is made of. By
-- default unicode61 splits at them, and Bangla writes its vowel signs,
-- hasanta and nukta as marks: মেয়ে was indexed as ম + য, so "মে"* matched
-- about 950 meanings and R1's Bangla "starts with" was mostly noise (#713).
-- A Latin mark is still folded away by remove_diacritics.
--
-- `uid` is UNINDEXED — it is carried so a MATCH can join back to `words`, not
-- so anyone can search for a hash.
CREATE VIRTUAL TABLE words_fts USING fts5(
  uid UNINDEXED,
  german,
  english,
  bangla,
  search_key,
  content = 'words',
  tokenize = 'unicode61 remove_diacritics 2 categories ''L* N* Co Mn Mc'''
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
  content = 'words',
  tokenize = 'trigram'
);

-- Every shipped meaning language's meanings (#1080), `lang` carried so a
-- query can keep to the learner's. Tier 1 and 2's tokenizer, which keeps a
-- Bangla or Devanagari word's marks.
CREATE VIRTUAL TABLE meanings_fts USING fts5(
  word_uid UNINDEXED,
  lang UNINDEXED,
  meaning,
  content = 'word_meanings',
  tokenize = 'unicode61 remove_diacritics 2 categories ''L* N* Co Mn Mc'''
);

-- Tier 4: "in sentences".
--
-- `word_uid` UNINDEXED so a hit joins back to the headword it belongs to,
-- which is what the result row shows above the sentence.
CREATE VIRTUAL TABLE examples_fts USING fts5(
  word_uid UNINDEXED,
  german,
  english,
  content = 'word_examples',
  tokenize = 'unicode61 remove_diacritics 2'
);
