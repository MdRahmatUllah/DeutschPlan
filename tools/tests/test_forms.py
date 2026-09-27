"""#632: a two-part verb or phrase `forms` cell is "3rd person · Perfekt".

`parseForms` takes part two as the Perfekt and the Forms quiz and the exams
expect it verbatim, so "darf · hat gedurft (durfte)" marked "hat gedurft"
wrong on the most common verbs of the first step.
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
from verify_content import check_verb_forms, verify  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[2] / "app" / "assets" / "db" / "content.db"


@pytest.fixture(scope="module")
def course(tmp_path_factory) -> Path:
    directory = tmp_path_factory.mktemp("forms")
    write_all(directory)
    sources = [read_workbook(directory / name) for name in BOOK_LEVELS]
    path = directory / "content.db"
    build(path, collect(sources, derive(sources)))
    return path


def gate(path: Path, pos: str, forms: str):
    connection = sqlite3.connect(path)
    try:
        connection.execute("UPDATE words SET pos = ?, forms = ? WHERE seq = 1", (pos, forms))
        return check_verb_forms(connection)
    finally:
        connection.rollback()
        connection.close()


@pytest.mark.parametrize(
    "forms",
    ["darf · hat gedurft (durfte)", "möchte · (wollte)", "bricht auf · hat/ist aufgebrochen", "ist dabei · war dabei"],
)
def test_632_a_verb_cell_that_is_not_3rd_person_perfekt_fails(course, forms):
    failures = gate(course, "verb", forms)
    assert [f.gate for f in failures] == ["forms"]
    assert forms in failures[0].message


@pytest.mark.parametrize(
    ("pos", "forms"),
    [
        ("verb", "darf · hat gedurft"),
        ("phrase", "ist dabei · ist dabei gewesen"),
        ("verb", "möchte"),  # one part: not asked
        ("verb", "erklärt · erläutert · legt dar"),  # a synonym set: not asked
        ("adj", "älter · am ältesten"),
    ],
)
def test_632_the_shapes_the_quiz_reads_or_skips_pass(course, pos, forms):
    assert gate(course, pos, forms) == []


def test_632_verify_runs_it(course, tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(course, copy)
    connection = sqlite3.connect(copy)
    with connection:
        connection.execute("UPDATE words SET pos = 'verb', forms = 'kann · hat gekonnt (konnte)' WHERE seq = 1")
    connection.close()
    assert "forms" in {failure.gate for failure in verify(copy)}


def test_632_the_shipped_modals_ask_their_perfekt_and_moechten_none(tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    connection = sqlite3.connect(copy)
    try:
        assert check_verb_forms(connection) == []
        forms = dict(
            connection.execute(
                "SELECT german, forms FROM words WHERE level_code = 'A1' "
                "AND german IN ('dürfen', 'möchten')"
            ).fetchall()
        )
    finally:
        connection.close()
    assert forms["dürfen"].split(" · ")[1] == "hat gedurft"
    assert "·" not in forms["möchten"]
