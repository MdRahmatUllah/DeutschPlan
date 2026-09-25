"""#287: an article typed into the German cell moves into `article`."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import assign_uids, split_articles  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


def noun(german: str, article: str | None = None, english: str = "x") -> Word:
    return Word(
        source_file="f",
        row=1,
        german=german,
        english=english,
        level="C2",
        pos="noun",
        article=article,
    )


def test_a_typed_in_article_moves_and_the_uid_stays():
    word = noun("das Gegenargument")
    assign_uids([word])
    uid = word.uid

    assert split_articles([word]) == (1, [])
    assert (word.article, word.german) == ("das", "Gegenargument")
    assert word.uid == uid, "the uid is the cell as authored: no progress reset"


def test_a_name_of_more_words_moves_too():
    words = [noun("die Benrather Linie"), noun("das Jugendwort des Jahres")]
    split_articles(words)
    assert [(w.article, w.german) for w in words] == [
        ("die", "Benrather Linie"),
        ("das", "Jugendwort des Jahres"),
    ]


def test_a_pair_keeps_its_articles():
    pairs = [
        "die Rente ↔ die Miete",
        "die Kohle / die Kohlen",
        "die Zuspitzung — die Pointe",
    ]
    words = [noun(german) for german in pairs]
    assert split_articles(words) == (0, [])
    assert [w.german for w in words] == pairs


def test_an_article_column_already_set_is_left_alone():
    word = noun("Haus", article="das")
    assert split_articles([word]) == (0, [])


def test_a_move_that_would_duplicate_a_row_is_left_and_reported():
    words = [noun("Satzakzent", article="der"), noun("der Satzakzent")]
    moved, warnings = split_articles(words)
    assert moved == 0
    assert words[1].german == "der Satzakzent"
    assert len(warnings) == 1 and "delete one" in warnings[0]


def test_the_build_moves_it(tmp_path):
    """The wiring: `derive` runs the step, after the uids."""
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    target = next(
        w for s in sources for w in s.words if w.pos == "noun" and w.article
    )
    target.german, target.article = f"{target.article} {target.german}", None
    authored = target.german

    derive(sources)

    assert target.article and " " not in target.german
    assert f"{target.article} {target.german}" == authored


def test_the_shipped_course_has_no_single_noun_with_its_article_inside():
    from verify_content import check_no_article_in_german

    db = sqlite3.connect(REPO / "app" / "assets" / "db" / "content.db")
    try:
        assert check_no_article_in_german(db) == []
        assert db.execute(
            "SELECT article FROM words WHERE german = 'Gegenargument'"
        ).fetchone() == ("das",)
    finally:
        db.close()
