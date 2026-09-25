"""content.db: the schema, and what the pipeline actually writes into it.

`docs/02-data/content-database.md` has a table naming every table and its key
columns. The first group parses that table rather than restating it, because a
schema copied into a test proves only that someone copied it twice — and this
is the schema `content_schema.drift` (#55) has to mirror for drift to
type-check the app's queries against it.
"""

from __future__ import annotations

import json
import re
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import LEVEL_NAMES  # noqa: E402
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from pipeline_steps import LEVELS, SUBLEVELS  # noqa: E402
from content_writer import build  # noqa: E402

DOC = (
    Path(__file__).resolve().parents[2]
    / "docs"
    / "02-data"
    / "content-database.md"
)


@pytest.fixture(scope="module")
def database(tmp_path_factory) -> sqlite3.Connection:
    """One real build, from the fixture workbooks."""
    directory = tmp_path_factory.mktemp("build")
    write_all(directory)

    sources = [read_workbook(directory / name) for name in BOOK_LEVELS]
    splits = derive(sources)
    path = directory / "content.db"
    build(path, collect(sources, splits))

    connection = sqlite3.connect(path)
    yield connection
    connection.close()


#: FTS5 keeps its index in tables beside the virtual one. They are sqlite's,
#: not ours, and no doc should list them.
SHADOW_SUFFIXES = re.compile(r"_(data|idx|docsize|config|content)$")


def real_tables(database: sqlite3.Connection) -> set[str]:
    return {
        row[0]
        for row in database.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'"
        )
        if not SHADOW_SUFFIXES.search(row[0])
    }


def column_names(cell: str) -> set[str]:
    """The backticked names in a key-columns cell, tokenizer note excluded.

    The FTS rows read "`uid` UNINDEXED, `german`, … — FTS5 `trigram`". The
    tokenizer is backticked too, and it is not a column, so everything after
    the em dash is dropped.
    """
    return set(re.findall(r"`([a-z][a-z0-9_]*)`", cell.split("—")[0]))


def documented_tables() -> dict[str, str]:
    """The table names and key-column cells from content-database.md.

    Located by its header row rather than by counting blocks after the
    heading: a sentence added under "## Tables" should not silently empty
    this and make every assertion below pass on nothing.
    """
    body = DOC.read_text(encoding="utf-8").split("| Table | Key columns |", 1)
    assert len(body) == 2, "the table header in content-database.md moved"
    section = body[1].split(chr(10) + chr(10))[0]

    rows: dict[str, str] = {}
    for line in section.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 4 or cells[1].startswith("---") or cells[1] == "Table":
            continue
        rows[cells[1].strip("`")] = cells[2]
    return rows


class TestAgainstTheDoc:
    def test_the_doc_table_was_found(self):
        # Everything below compares against this; an empty parse would make
        # each assertion pass by having nothing to check.
        tables = documented_tables()
        assert len(tables) >= 12
        assert "words" in tables and "meta" in tables

    def test_every_documented_table_exists(self, database):
        expected = set(documented_tables())
        found = real_tables(database)
        assert expected <= found, f"missing: {expected - found}"

    def test_no_table_exists_that_nobody_documented(self, database):
        found = real_tables(database)
        assert found <= set(documented_tables()), (
            f"undocumented: {found - set(documented_tables())}"
        )

    def test_every_key_column_the_doc_names_exists(self, database):
        """The doc's second cell backticks every column name.

        Read out of the backticks rather than guessed at, because a blocklist
        of "prose words" swallowed `key` and `value` — which are the two
        columns of `meta`, so dropping either passed.
        """
        # The FTS tables are included: PRAGMA table_info works on a virtual
        # table, and the doc's own query relies on the uid column it lists.
        for table, cell in documented_tables().items():
            actual = {
                row[1] for row in database.execute(f"PRAGMA table_info({table})")
            }
            named = column_names(cell)
            assert named, f"{table}: the doc backticks no column names"
            assert named <= actual, (
                f"{table}: the doc names {sorted(named - actual)}, the schema "
                f"has {sorted(actual)}"
            )

    def test_the_schema_has_no_column_the_doc_leaves_out(self, database):
        # The other direction. A column nobody documented is one the app will
        # not know to read, and `content_schema.drift` (#55) mirrors this list.
        for table, cell in documented_tables().items():
            actual = {
                row[1] for row in database.execute(f"PRAGMA table_info({table})")
            }
            named = column_names(cell)
            assert actual <= named, (
                f"{table}: the schema has {sorted(actual - named)}, which "
                f"content-database.md does not list"
            )


class TestIndexes:
    def test_the_five_the_issue_names_exist(self, database):
        indexed = {
            row[0]: row[1]
            for row in database.execute(
                "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
                "AND sql IS NOT NULL"
            )
        }
        expected = {
            "idx_words_step": "words (sublevel_code, seq_in_sublevel)",
            "idx_words_search_key": "words (search_key)",
            "idx_words_search_key_alt": "words (search_key_alt)",
            "idx_words_category": "words (category_id)",
            "idx_grammar_step": "grammar_topics (sublevel_code, seq)",
        }
        assert set(indexed) == set(expected)
        for name, columns in expected.items():
            assert columns in indexed[name], indexed[name]

    def test_the_step_index_is_the_one_the_step_screen_uses(self, database):
        # `SELECT * FROM words WHERE sublevel_code = ? ORDER BY
        # seq_in_sublevel` is the first query after launch. An index that
        # cannot serve both halves means a scan and a sort on every open.
        plan = database.execute(
            "EXPLAIN QUERY PLAN SELECT * FROM words WHERE sublevel_code = ? "
            "ORDER BY seq_in_sublevel",
            ("A1.1",),
        ).fetchall()
        detail = " ".join(str(row[-1]) for row in plan)
        assert "idx_words_step" in detail, detail
        assert "TEMP B-TREE" not in detail, f"sorting after all: {detail}"


class TestMeta:
    def test_it_carries_the_five_keys_the_issue_names(self, database):
        keys = {
            row[0] for row in database.execute("SELECT key FROM meta")
        }
        assert keys == {
            "content_version",
            "built_at",
            "sources",
            "word_count",
            "sublevel_week_boundaries",
        }

    def test_content_version_is_a_build_timestamp(self, database):
        version = database.execute(
            "SELECT value FROM meta WHERE key = 'content_version'"
        ).fetchone()[0]
        # PIPE-07: YYYYMMDDHHMM. The app compares it against the installed
        # copy, so anything that does not sort is a silent no-update.
        assert len(version) == 12 and version.isdigit()

    def test_word_count_matches_the_words_table(self, database):
        stated = int(
            database.execute(
                "SELECT value FROM meta WHERE key = 'word_count'"
            ).fetchone()[0]
        )
        actual = database.execute("SELECT COUNT(*) FROM words").fetchone()[0]
        assert stated == actual

    def test_the_boundaries_name_the_step_they_start(self, database):
        boundaries = json.loads(
            database.execute(
                "SELECT value FROM meta WHERE key = 'sublevel_week_boundaries'"
            ).fetchone()[0]
        )
        # "A1.2 starts at week 7" is the sentence this exists for, so the key
        # is the step that starts, not the level.
        assert set(boundaries) == {code for code in SUBLEVELS if code.endswith(".2")}
        assert all(isinstance(week, int) and week > 1 for week in boundaries.values())

    def test_sources_lists_the_workbooks(self, database):
        sources = json.loads(
            database.execute(
                "SELECT value FROM meta WHERE key = 'sources'"
            ).fetchone()[0]
        )
        assert sources == list(BOOK_LEVELS)


class TestContent:
    def test_all_twelve_steps_are_present_and_counted(self, database):
        rows = database.execute(
            "SELECT code, word_count, grammar_count FROM sublevels ORDER BY ord"
        ).fetchall()
        assert [row[0] for row in rows] == list(SUBLEVELS)
        assert all(row[1] > 0 for row in rows), rows

    def test_the_stored_counts_match_the_rows(self, database):
        # They are stored so the step list does not COUNT(*) twelve times on
        # the first screen after launch; a stored count that drifts is worse
        # than no count.
        for code, stated in database.execute(
            "SELECT code, word_count FROM sublevels"
        ):
            actual = database.execute(
                "SELECT COUNT(*) FROM words WHERE sublevel_code = ?", (code,)
            ).fetchone()[0]
            assert stated == actual, code

        for code, stated in database.execute(
            "SELECT code, grammar_count FROM sublevels"
        ):
            actual = database.execute(
                "SELECT COUNT(*) FROM grammar_topics WHERE sublevel_code = ?",
                (code,),
            ).fetchone()[0]
            assert stated == actual, code

    def test_every_level_has_a_name_and_an_exam_target(self, database):
        rows = database.execute(
            "SELECT code, ord, name, exam_target FROM levels ORDER BY ord"
        ).fetchall()
        assert [row[0] for row in rows] == list(LEVELS)
        assert all(row[2] for row in rows)
        assert all(row[3] for row in rows)
        assert set(LEVEL_NAMES) == set(LEVELS)

    def test_examples_keep_their_order_and_their_null_translation(self, database):
        uid, = database.execute("SELECT uid FROM words LIMIT 1").fetchone()
        rows = database.execute(
            "SELECT ord, german, english FROM word_examples "
            "WHERE word_uid = ? ORDER BY ord",
            (uid,),
        ).fetchall()
        assert [row[0] for row in rows] == [1, 2]
        # PIPE-06: the fixture gives two German lines and one English.
        assert rows[1][2] is None

    def test_every_word_has_both_search_keys(self, database):
        missing = database.execute(
            "SELECT COUNT(*) FROM words "
            "WHERE search_key IS NULL OR search_key_alt IS NULL"
        ).fetchone()[0]
        assert missing == 0

    def test_categories_are_deduplicated_across_workbooks(self, database):
        names = [
            row[0] for row in database.execute("SELECT name FROM categories")
        ]
        assert len(names) == len(set(names))
        # The fixtures give every workbook the same three tabs.
        assert sorted(names) == ["Alltag", "Arbeit", "Reisen"]

    def test_a_word_points_at_a_category_that_exists(self, database):
        orphans = database.execute(
            "SELECT COUNT(*) FROM words w LEFT JOIN categories c "
            "ON c.id = w.category_id WHERE w.category_id IS NOT NULL "
            "AND c.id IS NULL"
        ).fetchone()[0]
        assert orphans == 0

    def test_no_skill_prompts_are_scraped_from_a_worksheet(self, database):
        # #294: the workbooks hold no speaking or writing prompts (the Guide's
        # weekly skills are four tick boxes), and reading W01's cells filled
        # the table with sheet headers ("Dates", "Quiz seed") and instructions
        # to the spreadsheet user ("type in the yellow cell"). The table stays
        # in the schema, empty, until a real source exists.
        rows = database.execute("SELECT COUNT(*) FROM skill_prompts").fetchone()
        assert rows == (0,)


class TestItIsReadOnlyByConstruction:
    def test_no_table_has_a_default_or_a_trigger(self, database):
        # The app attaches this read-only, so every value has to be decided by
        # the pipeline where the build can fail on it. A DEFAULT is a decision
        # deferred to a writer that will never run.
        triggers = database.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'"
        ).fetchone()[0]
        assert triggers == 0

        for table in documented_tables():
            if table.endswith("_fts") or table.endswith("_trigram"):
                continue
            for row in database.execute(f"PRAGMA table_info({table})"):
                assert row[4] is None, f"{table}.{row[1]} has a DEFAULT"

    def test_a_rebuild_replaces_the_file_rather_than_appending(
        self, tmp_path
    ):
        # A database half from this run and half from the last would pass
        # every count check and be wrong in ways nobody could see.
        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        path = tmp_path / "content.db"

        for _ in range(2):
            fresh = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
            build(path, collect(fresh, derive(fresh)))

        connection = sqlite3.connect(path)
        try:
            count = connection.execute("SELECT COUNT(*) FROM words").fetchone()[0]
            assert count == len(
                [w for s in sources for w in s.words]
            ), "the second build appended instead of replacing"
        finally:
            connection.close()
