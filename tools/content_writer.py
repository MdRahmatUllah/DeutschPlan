"""Writes the compiled course into content.db.

Everything here runs after `pipeline_steps` has derived uids, steps, keys and
examples. This module only writes — if it has to decide something, the decision
belongs upstream where it can be tested without a database.

The file is read-only on the device: the app attaches it as schema `c` and
never writes to it, which is why the schema carries no defaults and no
triggers. Every value is settled here, where the build can fail.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from pipeline_steps import (
    LEVELS,
    SUBLEVELS,
    LevelSplit,
    PipelineError,
    text_of,
    translation_lines,
)

SCHEMA = Path(__file__).resolve().parent / "content_schema.sql"
FTS_SCHEMA = Path(__file__).resolve().parent / "content_fts.sql"

#: The public exam each level aims at. Not in any workbook, and not derivable:
#: it is what the step detail screen shows under the level name.
#:
#: `overview.md`: "Goethe and telc are named only to describe the target
#: level" — the app's own exams are generated and say so.
LEVEL_NAMES: dict[str, tuple[str, str | None]] = {
    "A1": ("Beginner", "Goethe-Zertifikat A1 · Start Deutsch 1"),
    "A2": ("Elementary", "Goethe-Zertifikat A2"),
    "B1": ("Intermediate", "Goethe-Zertifikat B1 · telc Deutsch B1"),
    "B2": ("Upper intermediate", "Goethe-Zertifikat B2 · telc Deutsch B2"),
    "C1": ("Advanced", "Goethe-Zertifikat C1 · telc Deutsch C1"),
    "C2": ("Proficient", "Goethe-Zertifikat C2 · Großes Deutsches Sprachdiplom"),
}


@dataclass
class BuildInputs:
    """Everything the writer needs, already derived."""

    words: list
    grammar: list
    categories: list
    splits: dict[str, LevelSplit]
    tips: list
    #: Each workbook: `{"file": name, "sha256": hex}` (#634).
    sources: list[dict]
    content_version: str
    #: ISO-8601 UTC, to the second. Stamped once, in `collect`, and written
    #: into meta and the manifest alike (#718).
    built_at: str
    #: The meaning languages that ship (#1080): PIPE-08's gate passed them.
    languages: list
    #: #1128: category name (lower case) -> {code: name}, for the shipped
    #: languages whose names are all there (`gate_category_names`).
    category_names: dict = field(default_factory=dict)


def create_schema(connection: sqlite3.Connection) -> None:
    """Runs `content_schema.sql`.

    The DDL is a file rather than a string in here so that the schema can be
    read, diffed and mirrored by `content_schema.drift` (#55) without anyone
    having to extract it from Python.
    """
    connection.executescript(SCHEMA.read_text(encoding="utf-8"))


def create_fts(connection: sqlite3.Connection) -> None:
    """Creates the search tables.

    Separate from `create_schema` so a reader looking for the course does not
    have to scroll past the index, and so #52 can assert they are populated
    without guessing which tables are which.
    """
    connection.executescript(FTS_SCHEMA.read_text(encoding="utf-8"))


def fill_fts(connection: sqlite3.Connection) -> None:
    """Indexes `words`, `word_examples` and `word_meanings` into the search
    tables.

    FTS5's `rebuild`: the tables are external content (#712), an index of the
    rows as they are now. Last, after every row is written, so nothing is
    left out of it; content.db is read-only on the device, so it cannot drift
    afterwards, and PIPE-08's integrity check says if anything moved it.
    """
    for table in ("words_fts", "words_trigram", "examples_fts", "meanings_fts"):
        connection.execute(f"INSERT INTO {table} ({table}) VALUES ('rebuild')")

    # No `optimize` here. It merges the index's b-tree segments, and there is
    # nothing to merge: the three rebuilds above run in one transaction, so
    # FTS5 flushes once. Measured on a real build — segment count and file
    # size are identical with and without it.
    #
    # If this ever loads in batches, it belongs back.


def write(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    """Fills an empty database. One transaction: a half-written course is
    worse than none, because the app would attach it and show gaps."""
    with connection:
        _write_levels(connection, inputs)
        category_ids = _write_categories(connection, inputs)
        _write_sublevels(connection, inputs)
        _write_words(connection, inputs, category_ids)
        _write_grammar(connection, inputs)
        _write_tips(connection, inputs)
        _write_languages(connection, inputs)
        _write_category_names(connection, inputs, category_ids)
        _write_meta(connection, inputs)
        fill_fts(connection)


def _write_levels(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    present = [
        level
        for level in LEVELS
        if any(word.level == level for word in inputs.words)
    ]
    connection.executemany(
        "INSERT INTO levels (code, ord, name, exam_target) VALUES (?, ?, ?, ?)",
        [
            (code, index + 1, *LEVEL_NAMES[code])
            for index, code in enumerate(present)
        ],
    )


def _write_categories(
    connection: sqlite3.Connection, inputs: BuildInputs
) -> dict[str, int]:
    """Assigns ids in first-seen order and returns the name -> id map.

    Names are matched case-insensitively and trimmed, because the same category
    appears as a tab name in one workbook and as a cell value in another.
    """
    ids: dict[str, int] = {}
    rows: list[tuple[int, str, str | None]] = []

    for category in inputs.categories:
        key = category.name.strip().lower()
        if key in ids:
            continue
        ids[key] = len(ids) + 1
        rows.append((ids[key], category.name.strip(), category.description))

    # A word may name a category that has no tab of its own.
    for word in inputs.words:
        if not word.category:
            continue
        key = word.category.strip().lower()
        if key not in ids:
            ids[key] = len(ids) + 1
            rows.append((ids[key], word.category.strip(), None))

    connection.executemany(
        "INSERT INTO categories (id, name, description) VALUES (?, ?, ?)", rows
    )
    return ids


def _write_sublevels(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    present = _counted(inputs.words)
    # BR-CONTENT-04 (#630): a step's words are what it teaches, not its notes.
    word_counts = _counted(_vocab(inputs.words))
    grammar_counts = _counted(inputs.grammar)

    rows = []
    for index, code in enumerate(SUBLEVELS):
        if code not in present:
            continue
        rows.append(
            (
                code,
                code.split(".")[0],
                index + 1,
                word_counts.get(code, 0),
                grammar_counts.get(code, 0),
            )
        )

    connection.executemany(
        "INSERT INTO sublevels "
        "(code, level_code, ord, word_count, grammar_count) "
        "VALUES (?, ?, ?, ?, ?)",
        rows,
    )


def _vocab(words) -> list:
    return [word for word in words if word.kind == "vocab"]


def _counted(rows) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        code = getattr(row, "sublevel_code", None)
        if code:
            counts[code] = counts.get(code, 0) + 1
    return counts


def _write_words(
    connection: sqlite3.Connection,
    inputs: BuildInputs,
    category_ids: dict[str, int],
) -> None:
    connection.executemany(
        "INSERT INTO words (uid, sublevel_code, level_code, seq, "
        "seq_in_sublevel, article, german, forms, pos, pron_bn, english, "
        "bangla, freq, category_id, source_week, collocations, "
        "synonyms_register, search_key, search_key_alt, kind) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                word.uid,
                word.sublevel_code,
                word.level,
                word.seq,
                word.seq_in_sublevel,
                word.article,
                word.german,
                word.forms,
                word.pos,
                word.pron_bn,
                word.english,
                word.bangla,
                word.freq,
                category_ids.get((word.category or "").strip().lower()),
                word.week,
                word.collocations,
                word.synonyms_register,
                word.search_key,
                word.search_key_alt,
                word.kind,
            )
            for word in inputs.words
        ],
    )

    connection.executemany(
        "INSERT INTO word_examples (word_uid, ord, german, english) "
        "VALUES (?, ?, ?, ?)",
        [
            (word.uid, example.ord, example.german, example.english)
            for word in inputs.words
            for example in word.examples
        ],
    )


def _write_grammar(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    connection.executemany(
        "INSERT INTO grammar_topics (uid, sublevel_code, level_code, seq, "
        "source_week, topic, rule, example_de, example_en, watch_out, tags) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                row.uid,
                row.sublevel_code,
                row.level_code,
                row.seq,
                row.week,
                row.topic,
                row.rule,
                row.example_de,
                row.example_en,
                row.watch_out,
                row.tags,
            )
            for row in inputs.grammar
        ],
    )


def _write_tips(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    # ponytail: the old table, English-keyed, until the app reads word_tips
    # (#1081); OR IGNORE keeps the first of two tips with one English text.
    connection.executemany(
        "INSERT OR IGNORE INTO interference_tips (word_uid, tip_en, tip_bn) "
        "VALUES (?, ?, ?)",
        [(tip.word_uid, tip.tip_en, tip.tip_bn) for tip in inputs.tips if tip.tip_en],
    )


def _write_category_names(
    connection: sqlite3.Connection, inputs: BuildInputs, category_ids: dict[str, int]
) -> None:
    """#1128: each category's name in the shipped languages the gate passed."""
    connection.executemany(
        "INSERT INTO category_translations (category_id, lang, name) VALUES (?, ?, ?)",
        [
            (category_ids[key], code, name)
            for key, texts in inputs.category_names.items()
            if key in category_ids
            for code, name in texts.items()
        ],
    )


def _write_languages(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    """#1080: each meaning language that ships, and its texts.

    A part a language has no text for (Bangla's examples, its grammar) has
    no rows: the app falls back to English's. English's and Bangla's are the
    same texts as the old columns (`words.english`, `bangla`, `pron_bn`,
    `word_examples.english`, `grammar_topics`, `interference_tips`), which
    stay until the app reads these (#1081).
    """
    codes = [language.code for language in inputs.languages]
    connection.executemany(
        "INSERT INTO course_languages (code, name, own_name, script, ord) "
        "VALUES (?, ?, ?, ?, ?)",
        [
            (l.code, l.name, l.own_name, l.script, index + 1)
            for index, l in enumerate(inputs.languages)
        ],
    )
    connection.executemany(
        "INSERT INTO word_meanings (word_uid, lang, meaning, pronunciation) "
        "VALUES (?, ?, ?, ?)",
        [
            (word.uid, code, meaning, text_of(word, "pronunciation", code))
            for word in inputs.words
            for code in codes
            if (meaning := text_of(word, "meaning", code))
        ],
    )
    connection.executemany(
        "INSERT INTO word_example_translations (word_uid, ord, lang, translation) "
        "VALUES (?, ?, ?, ?)",
        [
            (word.uid, ord, code, line)
            for word in inputs.words
            for code in codes
            for ord, line in enumerate(translation_lines(word, code), start=1)
        ],
    )
    connection.executemany(
        "INSERT INTO grammar_translations "
        "(grammar_uid, lang, topic, rule, example, watch_out) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        [
            (row.uid, code, topic)
            + tuple(text_of(row, part, code) for part in ("rule", "example", "watch_out"))
            for row in inputs.grammar
            for code in codes
            if (topic := text_of(row, "topic", code))
        ],
    )
    connection.executemany(
        "INSERT INTO word_tips (word_uid, lang, tip) VALUES (?, ?, ?)",
        # Unique, in order: two CSV rows may give one word one text.
        dict.fromkeys(
            (tip.word_uid, code, tip.texts[code])
            for tip in inputs.tips
            for code in codes
            if code in tip.texts
        ),
    )


def _write_meta(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    """The five keys `content-database.md` names.

    `sublevel_week_boundaries` is stored so the app can say "A1.2 starts at
    week 7" without re-deriving the split — the only place that number exists
    after the build is here.
    """
    import json

    boundaries = {
        split.second: split.boundary_week for split in inputs.splits.values()
    }

    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [
            ("content_version", inputs.content_version),
            ("built_at", inputs.built_at),
            ("sources", json.dumps(inputs.sources)),
            ("word_count", str(len(_vocab(inputs.words)))),
            (
                "sublevel_week_boundaries",
                json.dumps(boundaries, sort_keys=True),
            ),
        ],
    )


def open_database(path: Path) -> sqlite3.Connection:
    """Creates a fresh file. An existing one is replaced.

    A build appends to nothing: a database half from this run and half from the
    last would pass every count check and be wrong in ways nobody could see.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()

    connection = sqlite3.connect(path)
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def build(path: Path, inputs: BuildInputs) -> None:
    connection = open_database(path)
    try:
        create_schema(connection)
        create_fts(connection)
        write(connection, inputs)
    except sqlite3.Error as error:
        raise PipelineError(f"writing {path.name}: {error}") from error
    finally:
        connection.close()
