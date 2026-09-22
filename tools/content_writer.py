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
from dataclasses import dataclass
from pathlib import Path

from pipeline_steps import LEVELS, SUBLEVELS, LevelSplit, PipelineError

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
    skill_prompts: dict[str, list[str]]
    splits: dict[str, LevelSplit]
    sources: list[str]
    content_version: str


def create_schema(connection: sqlite3.Connection) -> None:
    """Runs `content_schema.sql`.

    The DDL is a file rather than a string in here so that the schema can be
    read, diffed and mirrored by `content_schema.drift` (#55) without anyone
    having to extract it from Python.
    """
    connection.executescript(SCHEMA.read_text(encoding="utf-8"))


def create_fts(connection: sqlite3.Connection) -> None:
    """Creates the three search tables.

    Separate from `create_schema` so a reader looking for the course does not
    have to scroll past the index, and so #52 can assert they are populated
    without guessing which tables are which.
    """
    connection.executescript(FTS_SCHEMA.read_text(encoding="utf-8"))


def fill_fts(connection: sqlite3.Connection) -> None:
    """Copies `words` and `word_examples` into the search tables.

    A copy rather than FTS5 external content: external content needs triggers
    on the source table to stay in step, and content.db is read-only on the
    device, so there is nothing for a trigger to react to. This runs once, at
    build time, and cannot drift afterwards.
    """
    connection.execute(
        "INSERT INTO words_fts (uid, german, english, bangla, search_key) "
        "SELECT uid, german, english, bangla, search_key FROM words"
    )
    connection.execute(
        "INSERT INTO words_trigram (uid, german, english, search_key) "
        "SELECT uid, german, english, search_key FROM words"
    )
    connection.execute(
        "INSERT INTO examples_fts (word_uid, german, english) "
        "SELECT word_uid, german, english FROM word_examples"
    )

    # FTS5 keeps its index in several small b-trees as rows arrive. One merge
    # after a bulk load turns them into one, which is what makes the first
    # search on a cold app fast rather than the tenth.
    for table in ("words_fts", "words_trigram", "examples_fts"):
        connection.execute(
            f"INSERT INTO {table}({table}) VALUES ('optimize')"
        )


def write(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    """Fills an empty database. One transaction: a half-written course is
    worse than none, because the app would attach it and show gaps."""
    with connection:
        _write_levels(connection, inputs)
        category_ids = _write_categories(connection, inputs)
        _write_sublevels(connection, inputs)
        _write_words(connection, inputs, category_ids)
        _write_grammar(connection, inputs)
        _write_skill_prompts(connection, inputs)
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
    word_counts = _counted(inputs.words)
    grammar_counts = _counted(inputs.grammar)

    rows = []
    for index, code in enumerate(SUBLEVELS):
        if code not in word_counts:
            continue
        rows.append(
            (
                code,
                code.split(".")[0],
                index + 1,
                word_counts[code],
                grammar_counts.get(code, 0),
            )
        )

    connection.executemany(
        "INSERT INTO sublevels "
        "(code, level_code, ord, word_count, grammar_count) "
        "VALUES (?, ?, ?, ?, ?)",
        rows,
    )


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
        "synonyms_register, search_key, search_key_alt) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
        "source_week, topic, rule, example_de, example_en, watch_out) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
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
            )
            for row in inputs.grammar
        ],
    )


def _write_skill_prompts(
    connection: sqlite3.Connection, inputs: BuildInputs
) -> None:
    connection.executemany(
        "INSERT INTO skill_prompts (level_code, ord, text) VALUES (?, ?, ?)",
        [
            (level, index + 1, prompt)
            for level, prompts in inputs.skill_prompts.items()
            for index, prompt in enumerate(prompts)
        ],
    )


def _write_meta(connection: sqlite3.Connection, inputs: BuildInputs) -> None:
    """The five keys `content-database.md` names.

    `sublevel_week_boundaries` is stored so the app can say "A1.2 starts at
    week 7" without re-deriving the split — the only place that number exists
    after the build is here.
    """
    import json
    from datetime import datetime, timezone

    boundaries = {
        split.second: split.boundary_week for split in inputs.splits.values()
    }

    connection.executemany(
        "INSERT INTO meta (key, value) VALUES (?, ?)",
        [
            ("content_version", inputs.content_version),
            ("built_at", datetime.now(timezone.utc).isoformat(timespec="seconds")),
            ("sources", json.dumps(inputs.sources)),
            ("word_count", str(len(inputs.words))),
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
