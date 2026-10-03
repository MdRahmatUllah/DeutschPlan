"""#1128: the course's category names in the meaning languages.

`content/category_names.csv` is read, gated like any part of a language
(PIPE-08, #1080), written into `category_translations`, and verified all or
none per language.
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
from pipeline_steps import (  # noqa: E402
    PipelineError,
    gate_category_names,
    read_category_names,
)
from verify_content import verify  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


def csv_file(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "category_names.csv"
    path.write_text(text, encoding="utf-8")
    return path


class TestReading:
    def test_1128_names_by_category_blank_cells_being_no_name(self, tmp_path):
        table = read_category_names(
            csv_file(tmp_path, "name,ru,pl\nFood & drink,Еда и напитки,\n")
        )
        assert table == {"food & drink": {"ru": "Еда и напитки"}}

    @pytest.mark.parametrize(
        "text, says",
        [
            ("english,ru\nFood,Еда\n", "first column must be `name`"),
            ("name,xx\nFood,Еда\n", "xx is no meaning language's code"),
            ("name,ru\nFood,Еда\nfood,Еда\n", "listed twice"),
            ("name,ru\n,Еда\n", "the name is empty"),
        ],
    )
    def test_1128_a_malformed_file_fails_naming_the_fix(self, tmp_path, text, says):
        with pytest.raises(PipelineError, match=says):
            read_category_names(csv_file(tmp_path, text))

    def test_1128_1398_the_committed_file_names_every_shipped_category_in_ru_pl_and_bn(self):
        table = read_category_names(REPO / "content" / "category_names.csv")
        db = sqlite3.connect(REPO / "app" / "assets" / "db" / "content.db")
        try:
            course = [name.lower() for (name,) in db.execute("SELECT name FROM categories")]
            # And the bundled course ships them all (#1398: Bangla too).
            shipped = dict(db.execute(
                "SELECT lang, COUNT(*) FROM category_translations GROUP BY lang"
            ).fetchall())
        finally:
            db.close()
        assert set(table) == set(course)
        assert all({"ru", "pl", "bn"} <= set(texts) for texts in table.values())
        assert shipped == {"bn": len(course), "pl": len(course), "ru": len(course)}


class TestGate:
    COURSE = ["Food & drink", "Home & furniture"]
    FULL = {
        "food & drink": {"ru": "Еда и напитки", "pl": "Jedzenie i picie"},
        "home & furniture": {"ru": "Дом и мебель"},
    }

    def test_1128_a_shipped_language_with_every_name_ships_them(self):
        names, report = gate_category_names(self.FULL, self.COURSE, ["en", "ru", "pl"])
        assert names == {
            "food & drink": {"ru": "Еда и напитки"},
            "home & furniture": {"ru": "Дом и мебель"},
        }
        assert "category names ru: 2/2, ship" in report
        assert any(line.startswith("category names pl: 1/2, held back") for line in report)

    def test_1128_a_partial_one_ships_only_with_allow_partial(self):
        names, report = gate_category_names(self.FULL, self.COURSE, ["en", "pl"], ("pl",))
        assert names == {"food & drink": {"pl": "Jedzenie i picie"}}
        assert "category names pl: 1/2, ship" in report

    def test_1128_a_language_not_shipped_or_without_a_column_writes_nothing(self):
        names, report = gate_category_names(self.FULL, self.COURSE, ["en", "bn"])
        assert (names, report) == ({}, [])

    def test_1128_a_name_the_course_has_no_category_for_fails(self):
        table = {**self.FULL, "cooking": {"ru": "Готовка"}}
        with pytest.raises(PipelineError, match="match no category"):
            gate_category_names(table, self.COURSE, ["en", "ru"])


@pytest.fixture
def sources(tmp_path):
    write_all(tmp_path)
    found = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    derive(found)
    return found


def course_categories(sources) -> list[str]:
    names = [c.name for s in sources for c in s.categories]
    names += [w.category for s in sources for w in s.words if w.category]
    return list(dict.fromkeys(name.strip() for name in names))


def test_1128_the_build_writes_a_shipped_languages_names_and_verify_holds_it(sources, tmp_path):
    categories = course_categories(sources)
    table = {name.lower(): {"bn": f"{name} (bn)"} for name in categories}
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources), category_names=table))

    db = sqlite3.connect(path)
    try:
        rows = db.execute(
            "SELECT c.name, t.name FROM category_translations t "
            "JOIN categories c ON c.id = t.category_id WHERE t.lang = 'bn'"
        ).fetchall()
    finally:
        db.close()
    assert sorted(rows) == sorted((name, f"{name} (bn)") for name in categories)
    assert "category names" not in {failure.gate for failure in verify(path)}

    db = sqlite3.connect(path)
    try:
        db.execute("DELETE FROM category_translations WHERE rowid = (SELECT min(rowid) FROM category_translations)")
        db.commit()
    finally:
        db.close()
    failures = [f for f in verify(path) if f.gate == "category names"]
    assert failures and f"bn names {len(categories) - 1:,} of the" in failures[0].message
