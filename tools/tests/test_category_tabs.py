"""#636: a category tab whose name Excel cut is still its category.

Excel cuts a sheet name at 31 characters and forbids ':' in it, so
"C-Regional variation- AT & CH" is the tab of "Regional variation: AT & CH".
Matched by the tab name, it became an empty category and the words' cells a
second one without a description. The title cell carries the real name.
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
from pathlib import Path

from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import build  # noqa: E402
from excel_to_sqlite import _read_categories, collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from verify_content import check_every_category_has_words, verify  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[2] / "app" / "assets" / "db" / "content.db"


def test_636_the_title_cell_names_a_cut_tab():
    book = Workbook()
    book.create_sheet("C-Regional variation- AT & CH").append(["Category: Regional variation: AT & CH"])
    book.create_sheet("C-Alltag").append(["Words about daily life."])
    book.create_sheet("C-Leer").append(["Category:"])

    assert [(c.name, c.description) for c in _read_categories(book)] == [
        ("Regional variation: AT & CH", "Category: Regional variation: AT & CH"),
        ("Alltag", "Words about daily life."),
        ("Leer", "Category:"),
    ]


def test_636_a_category_with_no_words_fails_the_build(tmp_path):
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources)))
    assert "categories" not in {f.gate for f in verify(path)}

    connection = sqlite3.connect(path)
    with connection:
        connection.execute("INSERT INTO categories (id, name) VALUES (999, 'Regional variation- AT & CH')")
    connection.close()
    failures = [f for f in verify(path) if f.gate == "categories"]
    assert len(failures) == 1 and "Regional variation- AT & CH" in failures[0].message


def test_636_every_shipped_category_has_words_and_a_description(tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    connection = sqlite3.connect(copy)
    try:
        assert check_every_category_has_words(connection) == []
        (undescribed,) = connection.execute(
            "SELECT count(*) FROM categories WHERE description IS NULL"
        ).fetchone()
    finally:
        connection.close()
    assert undescribed == 0
