"""PIPE-08: the gates a content build has to pass before it ships.

Every test breaks a real database and checks the gate catches it. A gate
asserted against a hand-built dict would pass on a file the app cannot open.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import build  # noqa: E402
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from verify_content import EXPECTED_STEPS, SAMPLE, main, verify  # noqa: E402


@pytest.fixture
def database(tmp_path) -> Path:
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources)))
    return path


def break_it(path: Path, *statements: str) -> Path:
    connection = sqlite3.connect(path)
    try:
        for statement in statements:
            connection.execute(statement)
        connection.commit()
    finally:
        connection.close()
    return path


def gates(path: Path) -> set[str]:
    return {failure.gate for failure in verify(path)}


def messages(path: Path) -> str:
    return " ".join(failure.message for failure in verify(path))


def test_a_good_build_passes_every_gate(database):
    assert verify(database) == []


def test_a_missing_file_says_what_to_run(tmp_path):
    failures = verify(tmp_path / "nothing.db")
    assert len(failures) == 1
    assert "make content" in failures[0].message


class TestStepGate:
    def test_a_step_with_no_words_is_caught(self, database):
        break_it(
            database,
            "DELETE FROM words WHERE sublevel_code = 'C2.2'",
            "UPDATE sublevels SET word_count = 0 WHERE code = 'C2.2'",
        )
        assert "steps" in gates(database)
        assert "C2.2" in messages(database)

    def test_a_missing_step_is_caught(self, database):
        break_it(database, "DELETE FROM sublevels WHERE code = 'C2.2'")
        assert "steps" in gates(database)
        assert f"not {EXPECTED_STEPS}" in messages(database)

    def test_the_message_says_where_to_look(self, database):
        break_it(database, "DELETE FROM sublevels WHERE code = 'A1.1'")
        assert "Level column" in messages(database)


class TestExampleGate:
    def test_a_word_with_no_example_is_caught(self, database):
        uid = sqlite3.connect(database).execute(
            "SELECT uid FROM words LIMIT 1"
        ).fetchone()[0]
        break_it(database, f"DELETE FROM word_examples WHERE word_uid = '{uid}'")

        assert "examples" in gates(database)
        assert "Examples (DE)" in messages(database)

    def test_it_names_the_words_and_their_steps(self, database):
        german, uid = sqlite3.connect(database).execute(
            "SELECT german, uid FROM words LIMIT 1"
        ).fetchone()
        break_it(database, f"DELETE FROM word_examples WHERE word_uid = '{uid}'")
        assert german in messages(database)

    def test_a_long_list_is_sampled(self, database):
        break_it(database, "DELETE FROM word_examples")
        text = messages(database)
        assert "and " in text and "more" in text
        assert text.count("(") <= SAMPLE + 2


class TestUidGate:
    def test_two_rows_identical_in_the_uid_fields_are_caught(self, database):
        # The primary key makes a literal duplicate unwritable, so a collision
        # shows up as two rows that are the same in everything the uid is made
        # of — which is what the learner meets twice.
        row = sqlite3.connect(database).execute(
            "SELECT level_code, german, pos, english, sublevel_code, seq, "
            "seq_in_sublevel, search_key, search_key_alt FROM words LIMIT 1"
        ).fetchone()
        break_it(
            database,
            "INSERT INTO words (uid, level_code, german, pos, english, "
            "sublevel_code, seq, seq_in_sublevel, search_key, search_key_alt) "
            "VALUES ('duplicate-uid', '{}', '{}', '{}', '{}', '{}', {}, {}, "
            "'{}', '{}')".format(
                row[0], row[1], row[2], row[3], row[4], 9999, 9999, row[7], row[8]
            ),
        )
        assert "uids" in gates(database)
        assert "meet the same word twice" in messages(database)

    def test_two_words_that_differ_only_in_english_are_fine(self, database):
        # Different meanings of the same German word are two entries on
        # purpose — "der See" and "die See".
        row = sqlite3.connect(database).execute(
            "SELECT level_code, german, pos, sublevel_code, search_key, "
            "search_key_alt FROM words LIMIT 1"
        ).fetchone()
        break_it(
            database,
            "INSERT INTO words (uid, level_code, german, pos, english, "
            "sublevel_code, seq, seq_in_sublevel, search_key, search_key_alt) "
            "VALUES ('second-sense', '{}', '{}', '{}', 'a different sense', "
            "'{}', 9999, 9999, '{}', '{}')".format(
                row[0], row[1], row[2], row[3], row[4], row[5]
            ),
        )
        assert "uids" not in gates(database)


class TestSearchGate:
    def test_an_empty_index_is_caught(self, database):
        break_it(database, "DELETE FROM words_trigram")
        assert "search" in gates(database)
        assert "words_trigram" in messages(database)

    def test_a_partly_filled_index_is_caught_too(self, database):
        # The gate the doc names is "FTS tables are empty". One row is as
        # broken as none and would pass a non-zero check — the learner just
        # cannot find some words.
        uid = sqlite3.connect(database).execute(
            "SELECT uid FROM words LIMIT 1"
        ).fetchone()[0]
        break_it(database, f"DELETE FROM words_fts WHERE uid = '{uid}'")
        assert "search" in gates(database)
        assert "rows for" in messages(database)

    def test_a_missing_index_is_caught(self, database):
        break_it(database, "DROP TABLE examples_fts")
        assert "search" in gates(database)


class TestEveryGateRuns:
    def test_one_run_reports_all_of_them(self, database):
        # An author should not have to build five times to find five problems.
        break_it(
            database,
            "DELETE FROM words WHERE sublevel_code = 'C2.2'",
            "UPDATE sublevels SET word_count = 0 WHERE code = 'C2.2'",
            "DELETE FROM word_examples",
            "DELETE FROM words_trigram",
        )
        assert {"steps", "examples", "search"} <= gates(database)

    def test_verify_does_not_modify_the_file(self, database):
        before = database.read_bytes()
        verify(database)
        assert database.read_bytes() == before, (
            "verify opens read-write so FTS5 integrity-check can run; it must "
            "not leave anything behind"
        )


class TestTheCli:
    def test_a_good_build_exits_zero(self, database, capsys):
        assert main(["--db", str(database)]) == 0
        assert "passed every gate" in capsys.readouterr().out

    def test_a_failure_exits_non_zero_and_says_it_is_not_shippable(
        self, database, capsys
    ):
        break_it(database, "DELETE FROM word_examples")
        assert main(["--db", str(database)]) == 1
        assert "not shippable" in capsys.readouterr().err

    def test_every_failure_is_printed(self, database, capsys):
        break_it(database, "DELETE FROM word_examples", "DELETE FROM words_fts")
        main(["--db", str(database)])
        err = capsys.readouterr().err
        assert "examples:" in err and "search:" in err


def test_a_noun_rule_on_a_verb_fails_the_tips_gate(database):
    """#321: the build keeps "gender" tips to nouns; the gate catches a
    build that doesn't."""
    from pipeline_steps import read_tips, tip_pos
    from verify_content import DEFAULT_TIPS

    rule = next(t for t in read_tips(DEFAULT_TIPS) if tip_pos(t.tags) == "noun")
    break_it(
        database,
        "INSERT INTO interference_tips (word_uid, tip_en, tip_bn) "
        "SELECT uid, '" + rule.tip_en.replace("'", "''") + "', NULL "
        "FROM words WHERE pos = 'verb' LIMIT 1",
    )
    assert "tips" in gates(database)
    assert f"line {rule.row}" in messages(database)


def test_a_malformed_tips_file_is_a_failure_not_a_crash(database, tmp_path):
    """#384: the gate reports it, as every other gate does."""
    import sqlite3

    from verify_content import check_tips_fit_their_word_class

    bad = tmp_path / "tips.csv"
    bad.write_text(
        "match_type,match,tip_en,tip_bn,tags\ncolour,red,a tip,,\n",
        encoding="utf-8",
    )
    db = sqlite3.connect(database)
    try:
        failures = check_tips_fit_their_word_class(db, bad)
    finally:
        db.close()
    assert [f.gate for f in failures] == ["tips"]
    assert "line 2" in failures[0].message

