"""#287: an article typed into the German cell moves into `article`."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    assign_uids,
    drop_article_duplicates,
    split_articles,
)

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

    assert split_articles([word]) == 1
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
    assert split_articles(words) == 0
    assert [w.german for w in words] == pairs


def test_an_article_column_already_set_is_left_alone():
    word = noun("Haus", article="das")
    assert split_articles([word]) == 0


def test_a_row_its_article_would_make_a_duplicate_is_dropped():
    """#407: the clean row stays; the one with the article in German goes."""
    clean = noun("Satzakzent", article="der")
    duplicate = noun("der Satzakzent")
    duplicate.source_file, duplicate.row = "German_C2_Tracker.xlsx", 812

    kept, warnings = drop_article_duplicates([clean, duplicate])

    assert len(kept) == 1 and kept[0] is clean
    assert len(warnings) == 1
    assert "dropped a duplicate of 'Satzakzent'" in warnings[0]
    assert "German_C2_Tracker.xlsx All Words row 812" in warnings[0]


def test_a_row_that_is_no_duplicate_is_kept_and_its_article_moves():
    """Every uid field has to match: another English is another word."""
    words = [
        noun("Satzakzent", article="der"),
        noun("der Satzakzent", english="sentence stress"),
        noun("das Gegenargument"),
    ]
    kept, warnings = drop_article_duplicates(words)

    assert kept == words and warnings == []
    assert split_articles(kept) == 2
    assert [(w.article, w.german) for w in kept[1:]] == [
        ("der", "Satzakzent"),
        ("das", "Gegenargument"),
    ]


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


def test_the_build_drops_the_duplicate(tmp_path, capsys):
    """#407's wiring: gone from what `collect` ships, with one warning."""
    import dataclasses

    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    source = sources[-1]
    clean = next(w for w in source.words if w.pos == "noun" and w.article)
    duplicate = dataclasses.replace(
        clean, row=999, german=f"{clean.article} {clean.german}", article=None
    )
    source.words.append(duplicate)
    total = sum(len(s.words) for s in sources)

    derive(sources)

    assert sum(len(s.words) for s in sources) == total - 1
    assert all(w is not duplicate for w in source.words)
    assert any(w is clean for w in source.words)
    assert capsys.readouterr().err.count("dropped a duplicate of") == 1


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
