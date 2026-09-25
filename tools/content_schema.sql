-- content.db — the course, compiled from the authoring workbooks.
--
-- `docs/02-data/content-database.md` is the specification, and
-- `tools/tests/test_schema.py` parses that file to check this one against it.
--
-- Read-only on the device: the app attaches it as schema `c` and never writes.
-- That is why there is not a single DEFAULT or trigger here — every value is
-- decided by the pipeline, where it can be checked before it ships.
--
-- The FTS tables live in fts.sql (#48), because they are rebuilt from these
-- and a reader looking for the course should not have to scroll past them.

-- Build metadata. `content_version` is the build timestamp the app compares
-- against the installed copy to decide whether to replace it.
CREATE TABLE meta (
  -- Quoted: KEY is a reserved word to drift's SQL parser, which reads the
  -- mirror of this file in lib/data/db/content_schema.drift.
  "key" TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);

-- The six CEFR levels. `exam_target` names the public exam the level aims at,
-- for the step detail screen — the app's own exams are generated and say so.
CREATE TABLE levels (
  code        TEXT PRIMARY KEY NOT NULL,
  ord         INTEGER NOT NULL,
  name        TEXT NOT NULL,
  exam_target TEXT
);

-- The twelve steps. `word_count` and `grammar_count` are stored rather than
-- counted at run time: the step list is the first screen after launch, and a
-- COUNT(*) per row there is twelve table scans before anything is drawn.
CREATE TABLE sublevels (
  code          TEXT PRIMARY KEY NOT NULL,
  level_code    TEXT NOT NULL REFERENCES levels (code),
  ord           INTEGER NOT NULL,
  word_count    INTEGER NOT NULL,
  grammar_count INTEGER NOT NULL
);

-- From the C-… tabs. The id is assigned by the pipeline in tab order.
CREATE TABLE categories (
  id          INTEGER PRIMARY KEY NOT NULL,
  name        TEXT NOT NULL,
  description TEXT
);

-- One row per entry in All Words.
--
-- `seq` is reading order across every workbook; `seq_in_sublevel` is what the
-- step screen lists by. Both are stored because neither can be derived from
-- the other once words are filtered.
CREATE TABLE words (
  uid               TEXT PRIMARY KEY NOT NULL,
  sublevel_code     TEXT NOT NULL REFERENCES sublevels (code),
  level_code        TEXT NOT NULL REFERENCES levels (code),
  seq               INTEGER NOT NULL,
  seq_in_sublevel   INTEGER NOT NULL,
  article           TEXT,
  german            TEXT NOT NULL,
  forms             TEXT,
  pos               TEXT,
  pron_bn           TEXT,
  english           TEXT NOT NULL,
  bangla            TEXT,
  freq              INTEGER,
  category_id       INTEGER REFERENCES categories (id),
  source_week       INTEGER,
  collocations      TEXT,
  synonyms_register TEXT,
  search_key        TEXT NOT NULL,
  search_key_alt    TEXT NOT NULL
);

CREATE INDEX idx_words_step ON words (sublevel_code, seq_in_sublevel);
CREATE INDEX idx_words_search_key ON words (search_key);
CREATE INDEX idx_words_search_key_alt ON words (search_key_alt);
CREATE INDEX idx_words_category ON words (category_id);

-- Example sentences. `english` is null for a German line the author left
-- untranslated (PIPE-06) — the sentence is still worth showing.
CREATE TABLE word_examples (
  word_uid TEXT NOT NULL REFERENCES words (uid) ON DELETE CASCADE,
  ord      INTEGER NOT NULL,
  german   TEXT NOT NULL,
  english  TEXT,
  PRIMARY KEY (word_uid, ord)
);

-- Grammar, split between the two steps of its level by count in teaching
-- order (BR-COURSE-03).
CREATE TABLE grammar_topics (
  uid           TEXT PRIMARY KEY NOT NULL,
  sublevel_code TEXT NOT NULL REFERENCES sublevels (code),
  level_code    TEXT NOT NULL REFERENCES levels (code),
  seq           INTEGER NOT NULL,
  source_week   INTEGER,
  topic         TEXT NOT NULL,
  rule          TEXT,
  example_de    TEXT,
  example_en    TEXT,
  watch_out     TEXT,

  -- Comma list, derived from the topic title by the pipeline. It decides
  -- which practice item types apply (grammar-practice.md); every topic
  -- carries at least gap-fill and pick-the-form.
  tags          TEXT NOT NULL
);

CREATE INDEX idx_grammar_step ON grammar_topics (sublevel_code, seq);

-- Speaking and writing prompts per level. Empty: the workbooks hold none
-- (#294); kept for when a real source exists.
CREATE TABLE skill_prompts (
  level_code TEXT NOT NULL REFERENCES levels (code),
  ord        INTEGER NOT NULL,
  -- Named `prompt`, not `text`: drift generates a column getter from the
  -- name, and `text` collides with the `Table.text()` builder every drift
  -- table inherits. ADR 25.
  prompt     TEXT NOT NULL,
  PRIMARY KEY (level_code, ord)
);

-- L1-specific traps, resolved from interference_tips.csv at build time so the
-- app never runs a regex over the word list.
CREATE TABLE interference_tips (
  word_uid TEXT NOT NULL REFERENCES words (uid) ON DELETE CASCADE,
  tip_en   TEXT NOT NULL,
  tip_bn   TEXT,
  PRIMARY KEY (word_uid, tip_en)
);
