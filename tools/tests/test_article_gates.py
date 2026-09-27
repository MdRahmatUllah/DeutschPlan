"""#633: every noun carries its article, and no phrase does.

A noun without one gets no gender colour and no Articles practice (Ende,
Anfang, Mitte); a phrase with one is asked by the Articles quiz
("___ Fehler machen" -> der).
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import build  # noqa: E402
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from verify_content import check_articles, verify  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[2] / "app" / "assets" / "db" / "content.db"


@pytest.fixture(scope="module")
def course(tmp_path_factory) -> Path:
    directory = tmp_path_factory.mktemp("articles")
    write_all(directory)
    sources = [read_workbook(directory / name) for name in BOOK_LEVELS]
    path = directory / "content.db"
    build(path, collect(sources, derive(sources)))
    return path


def gate(path: Path, pos: str, article: str | None, german: str):
    connection = sqlite3.connect(path)
    try:
        connection.execute(
            "UPDATE words SET pos = ?, article = ?, german = ? WHERE seq = 1", (pos, article, german)
        )
        return check_articles(connection)
    finally:
        connection.rollback()
        connection.close()


def test_633_the_fixture_course_passes(course):
    assert gate(course, "noun", "das", "Haus") == []


@pytest.mark.parametrize(
    ("pos", "article", "german"),
    [("noun", None, "Ende"), ("phrase", "der", "Fehler machen")],
)
def test_633_a_bare_noun_or_a_phrase_with_an_article_fails(course, pos, article, german):
    failures = gate(course, pos, article, german)
    assert [f.gate for f in failures] == ["articles"]
    assert german in failures[0].message


@pytest.mark.parametrize(
    "german",
    ["Weihnachten", "Grund / Ursache / Anlass", "Mitleid ↔ Sympathie", "Geld vs. Kohle vs. finanzielle Mittel"],
)
def test_633_a_holiday_or_a_set_of_nouns_needs_no_article(course, german):
    assert gate(course, "noun", None, german) == []


def test_633_verify_runs_it(course, tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(course, copy)
    connection = sqlite3.connect(copy)
    with connection:
        connection.execute("UPDATE words SET pos = 'phrase', article = 'die' WHERE seq = 1")
    connection.close()
    assert "articles" in {failure.gate for failure in verify(copy)}


def test_633_the_shipped_nouns_have_their_articles_and_no_phrase_has_one(tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    connection = sqlite3.connect(copy)
    try:
        assert check_articles(connection) == []
        articles = dict(
            connection.execute(
                "SELECT german, article FROM words WHERE pos = 'noun' AND german IN "
                "('Ende', 'Anfang', 'Mitte', 'Nominalisierung', 'Wirtschaftsflüchtling')"
            ).fetchall()
        )
        (fehler,) = connection.execute(
            "SELECT article FROM words WHERE german = 'Fehler machen'"
        ).fetchone()
    finally:
        connection.close()
    assert articles == {
        "Ende": "das",
        "Anfang": "der",
        "Mitte": "die",
        "Nominalisierung": "die",
        "Wirtschaftsflüchtling": "der",
    }
    assert fehler is None
