"""The three search tables, one per tier of `docs/03-domain/search.md`.

Every test here runs the query shape the doc gives, against a real build. A
test that only counted rows would pass on an index nothing can search.
"""

from __future__ import annotations

import sqlite3
import sys
from contextlib import contextmanager
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import build  # noqa: E402
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402

FTS_TABLES = ("words_fts", "words_trigram", "examples_fts")


@contextmanager
def probe_words(database: sqlite3.Connection, *words: tuple):
    """Adds words, `(uid, german, english, bangla, search_key)`, for the
    duration of one assertion, indexed, then undoes it.

    Into `words`, and indexed by FTS5's `rebuild` as the build does: the
    search tables are external content, an index of `words`' rows (#712).

    A savepoint rather than a matching DELETE: these run on a module-scoped
    connection, so a probe that outlives its test — because the test failed,
    or because the classes were reordered — would make the row-count tests
    see 181 words against 180.
    """
    database.execute("SAVEPOINT probe")
    try:
        database.executemany(
            "INSERT INTO words (uid, sublevel_code, level_code, seq, "
            "seq_in_sublevel, german, english, bangla, search_key, "
            "search_key_alt, kind) "
            "VALUES (?, 'A1.1', 'A1', 0, 0, ?, ?, ?, ?, ?, 'vocab')",
            [(*word, word[-1]) for word in words],
        )
        for table in ("words_fts", "words_trigram"):
            database.execute(f"INSERT INTO {table} ({table}) VALUES ('rebuild')")
        yield
    finally:
        database.execute("ROLLBACK TO probe")
        database.execute("RELEASE probe")


@pytest.fixture(scope="module")
def database(tmp_path_factory) -> sqlite3.Connection:
    directory = tmp_path_factory.mktemp("fts")
    write_all(directory)
    sources = [read_workbook(directory / name) for name in BOOK_LEVELS]
    path = directory / "content.db"
    build(path, collect(sources, derive(sources)))

    connection = sqlite3.connect(path)
    yield connection
    connection.close()


def test_the_runtime_has_fts5_and_trigram():
    # ADR 14 notes this has to be asserted on the device too. Here it guards
    # the build: a Python without the trigram tokenizer would write an empty
    # words_trigram and nothing else would notice.
    probe = sqlite3.connect(":memory:")
    try:
        probe.execute("CREATE VIRTUAL TABLE t USING fts5(a, tokenize='trigram')")
    finally:
        probe.close()


class TestTheyExistAndAreFull:
    def test_all_three_are_built(self, database):
        found = {
            row[0]
            for row in database.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        assert set(FTS_TABLES) <= found

    # What each has indexed is its `_docsize` rows, one a row: a count of an
    # external-content table counts its source (#712).

    def test_none_is_empty(self, database):
        # PIPE-08 fails the build on this; here it catches a tokenizer that
        # silently accepted nothing.
        for table in FTS_TABLES:
            count = database.execute(
                f"SELECT COUNT(*) FROM {table}_docsize"
            ).fetchone()[0]
            assert count > 0, table

    def test_the_word_tables_cover_every_word(self, database):
        words = database.execute("SELECT COUNT(*) FROM words").fetchone()[0]
        for table in ("words_fts", "words_trigram"):
            assert (
                database.execute(
                    f"SELECT COUNT(*) FROM {table}_docsize"
                ).fetchone()[0]
                == words
            ), table

    def test_examples_fts_covers_every_example(self, database):
        assert (
            database.execute(
                "SELECT COUNT(*) FROM examples_fts_docsize"
            ).fetchone()[0]
            == database.execute("SELECT COUNT(*) FROM word_examples").fetchone()[0]
        )

    def test_712_they_hold_no_copy_of_the_text(self, database):
        # External content: the index alone, the text read from `words` and
        # `word_examples`. A `_content` table was a copy, 1.9 MB of 7.5.
        tables = {
            name
            for (name,) in database.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }
        for table in FTS_TABLES:
            assert f"{table}_content" not in tables, table


class TestTheSearchTiers:
    """The query shapes `search.md` gives, run against real rows."""

    def a_word(self, database):
        return database.execute(
            "SELECT uid, german FROM words ORDER BY seq LIMIT 1"
        ).fetchone()

    def test_tier_1_exact_match_joins_back_to_the_word(self, database):
        uid, german = self.a_word(database)
        rows = database.execute(
            "SELECT w.uid FROM words w JOIN "
            "(SELECT uid FROM words_fts WHERE words_fts MATCH ?) f "
            "ON f.uid = w.uid",
            ['german : "' + german + '"'],
        ).fetchall()
        assert (uid,) in rows

    def test_tier_2_prefix_match_ranks(self, database):
        _, german = self.a_word(database)
        prefix = german[:4]
        rows = database.execute(
            "SELECT uid, rank FROM words_fts WHERE words_fts MATCH ? "
            "ORDER BY rank LIMIT 5",
            ['"' + prefix + '"*'],
        ).fetchall()
        assert rows, "no prefix hit for " + repr(prefix)

    def test_tier_3_trigram_finds_a_misspelling(self, database):
        # The tier's whole reason: "Strase" for "Straße". Trigram matches any
        # three-character run, so a dropped or wrong letter still hits.
        with probe_words(
            database, ("probe", "Strasse", "street", None, "strasse")
        ):
            rows = database.execute(
                "SELECT uid FROM words_trigram WHERE words_trigram MATCH ?",
                ['"stras"'],
            ).fetchall()
        assert ("probe",) in rows

    def test_tier_3_returns_nothing_below_three_characters(self, database):
        # Trigram indexes three-character runs, so a shorter query matches
        # nothing at all — silently, with no error. The search screen has to
        # fall back to the tiers above rather than show the learner an empty
        # result, and this is the behaviour it falls back from.
        with probe_words(
            database, ("probe", "Strasse", "street", None, "strasse")
        ):
            assert ("probe",) in database.execute(
                "SELECT uid FROM words_trigram WHERE words_trigram MATCH ?",
                ['"str"'],
            ).fetchall()
            assert database.execute(
                "SELECT uid FROM words_trigram WHERE words_trigram MATCH ?",
                ['"st"'],
            ).fetchall() == []

    def test_tier_4_a_sentence_hit_names_its_headword(self, database):
        row = database.execute(
            "SELECT e.word_uid, w.german FROM examples_fts e "
            "JOIN words w ON w.uid = e.word_uid "
            "WHERE examples_fts MATCH ? LIMIT 1",
            ['"sehe"'],
        ).fetchone()
        # The fixture writes "Ich sehe <word> dort." as the second example.
        assert row is not None and row[1]


class TestTokenizers:
    def test_words_fts_folds_diacritics(self, database):
        # remove_diacritics 2 is why "Tur" finds "Tür" here, on top of
        # search_key_alt. Inserted directly so the assertion is about the
        # tokenizer rather than about the fixture's vocabulary.
        with probe_words(database, ("probe", "Tür", "door", None, "tuer")):
            rows = database.execute(
                "SELECT uid FROM words_fts WHERE words_fts MATCH ?", ['"Tur"']
            ).fetchall()
        assert ("probe",) in rows

    def test_bangla_survives_the_tokenizer(self, database):
        # A Bangla meaning is findable as itself — tier 1's `bangla = raw`
        # match.
        with probe_words(
            database, ("probe", "Mädchen", "girl", "মেয়ে", "maedchen")
        ):
            rows = database.execute(
                "SELECT uid FROM words_fts WHERE words_fts MATCH ?",
                ['bangla : "মেয়ে"'],
            ).fetchall()
        assert ("probe",) in rows

    def test_713_a_bangla_word_is_one_token_vowel_signs_and_all(self, database):
        # unicode61 split at Bangla's vowel signs, hasanta and nukta (Mn, Mc):
        # মেয়ে was ম + য, and মতামত began with ম too, so "মে"* matched both
        # and R1's Bangla "starts with" was mostly noise (#713).
        with probe_words(
            database,
            ("girl", "Mädchen", "girl", "মেয়ে", "maedchen"),
            ("opinion", "Meinung", "opinion", "মতামত", "meinung"),
            ("friction", "Reibung", "friction", "ঘর্ষণ", "reibung"),
        ):
            def found(query: str) -> set[str]:
                return {
                    uid
                    for (uid,) in database.execute(
                        "SELECT uid FROM words_fts WHERE words_fts MATCH ?",
                        ["bangla : " + query],
                    )
                }

            assert found('"মে"*') == {"girl"}
            assert found('"মেয়ে"*') == {"girl"}
            assert found('"ঘর"*') == {"friction"}, "a prefix still finds"
            assert found('"ঘর"') == set(), "but ঘর্ষণ is no word ঘর"

    def test_713_the_shipped_course_starts_bangla_words_whole(self):
        # Over the committed asset: every meaning "মেয়ে"* finds has a word
        # that starts with মেয়ে, which only a rebuild with the tokenizer
        # above gives.
        asset = Path(__file__).resolve().parents[2] / "app/assets/db/content.db"
        shipped = sqlite3.connect(f"file:{asset}?mode=ro", uri=True)
        try:
            meanings = [
                bangla
                for (bangla,) in shipped.execute(
                    "SELECT w.bangla FROM words_fts f JOIN words w "
                    "ON w.uid = f.uid WHERE words_fts MATCH ?",
                    ['bangla : "মেয়ে"*'],
                )
            ]
        finally:
            shipped.close()
        assert meanings, "the course has মেয়ে"
        for bangla in meanings:
            assert any(
                word.startswith("মেয়ে")
                for word in bangla.replace("(", " ").replace("/", " ").split()
            ), bangla

    def test_the_uid_column_is_not_searchable(self, database):
        # UNINDEXED: it is carried so a MATCH can join back, not so anyone can
        # search for a hash. A searchable uid would also let a stray hex query
        # return an unrelated word.
        uid = database.execute("SELECT uid FROM words LIMIT 1").fetchone()[0]
        rows = database.execute(
            "SELECT uid FROM words_fts WHERE words_fts MATCH ?", ['"' + uid + '"']
        ).fetchall()
        assert rows == []


def test_the_index_survives_its_own_integrity_check(database):
    """FTS5's own verdict on the index it built, against the rows it indexes
    (`rank` 1: an external-content table is checked against its source).

    There is no `optimize` in the writer: the three rebuilds run in one
    transaction, so FTS5 flushes once and there is nothing to merge. Measured
    — segment count and file size are identical either way.
    """
    for table in FTS_TABLES:
        database.execute(
            "INSERT INTO " + table + "(" + table + ", rank) "
            "VALUES ('integrity-check', 1)"
        )

