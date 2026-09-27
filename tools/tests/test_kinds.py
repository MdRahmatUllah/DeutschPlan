"""#630: PIPE-10's `kind`, and the starred-example gate.

A lesson note ("beantworten — Präfix be-") and a comparison ("machen ↔ tun")
sit in All Words beside the words; BR-CONTENT-04 keeps them out of every pool
that studies a word. The pipeline gives each row its kind from the headword's
shape, and `content/corrections.yaml` overrides it where the shape says
nothing ("Vorfeldbesetzung").
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_manifest import build_manifest  # noqa: E402
from content_writer import build  # noqa: E402
from excel_to_sqlite import Word, collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from pipeline_steps import PipelineError, assign_kinds  # noqa: E402
from verify_content import check_no_starred_example, verify  # noqa: E402

SHIPPED = Path(__file__).resolve().parents[2] / "app" / "assets" / "db" / "content.db"


def kind_of(german: str, kind: str | None = None) -> str:
    word = Word(source_file="t.xlsx", row=1, german=german, kind=kind)
    assign_kinds([word])
    return word.kind


@pytest.mark.parametrize(
    ("german", "kind"),
    [
        ("beantworten — Präfix be-", "note"),
        ("Bearbeitung — Wortbildung -ung", "note"),
        ("Suffix -ismus", "note"),
        ("Wortfamilie: führen", "note"),
        ("zu + Partizip I (Gerundivum)", "note"),
        ("Adjektiv → Nomen: der/die Angestellte", "note"),
        ("Hören (C2)", "note"),
        ("machen ↔ tun", "compare"),
        ("sagen vs. behaupten vs. betonen", "compare"),
        ("Haus", "vocab"),
        ("Hals- und Beinbruch", "vocab"),
        ("E-Mail", "vocab"),
        ("Ich-Laut", "vocab"),
        ("circa / etwa / rund", "vocab"),
        ("ob (+ Genitiv)", "vocab"),
    ],
)
def test_630_the_headword_shape_gives_the_kind(german, kind):
    assert kind_of(german) == kind


def test_630_a_correction_s_kind_wins_and_an_unknown_one_fails():
    assert kind_of("Vorfeldbesetzung", "note") == "note"
    assert kind_of("machen ↔ tun", "vocab") == "vocab"
    with pytest.raises(PipelineError, match="lesson"):
        kind_of("Haus", "lesson")


def test_630_a_step_and_the_course_count_their_words_not_their_notes(tmp_path):
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    splits = derive(sources)
    inputs = collect(sources, splits)
    note = inputs.words[0]
    note.kind = "note"
    path = tmp_path / "content.db"
    build(path, inputs)

    db = sqlite3.connect(path)
    try:
        (meta,) = db.execute("SELECT value FROM meta WHERE key = 'word_count'").fetchone()
        (step,) = db.execute(
            "SELECT word_count FROM sublevels WHERE code = ?", (note.sublevel_code,)
        ).fetchone()
        (rows,) = db.execute(
            "SELECT COUNT(*) FROM words WHERE sublevel_code = ?", (note.sublevel_code,)
        ).fetchone()
        (kind,) = db.execute("SELECT kind FROM words WHERE uid = ?", (note.uid,)).fetchone()
    finally:
        db.close()
    assert int(meta) == len(inputs.words) - 1
    assert step == rows - 1
    assert kind == "note"

    manifest = build_manifest(inputs, splits)
    assert manifest["counts"]["words"] == len(inputs.words) - 1
    assert manifest["steps"][note.sublevel_code]["words"] == rows - 1
    assert note.uid in manifest["words"], "the uid list has every row"


def test_630_a_starred_example_fails_the_examples_gate(tmp_path):
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources)))
    assert verify(path) == []

    db = sqlite3.connect(path)
    with db:
        db.execute(
            "UPDATE word_examples SET german = 'Ich arbeite, nicht: *Ich bin arbeitend.' "
            "WHERE rowid = 1"
        )
    db.close()
    failures = [f for f in verify(path) if f.gate == "examples"]
    assert failures and "starred" in failures[0].message


def test_630_the_shipped_course_has_its_notes_and_its_named_rows_fixed(tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    db = sqlite3.connect(copy)
    try:
        assert check_no_starred_example(db) == []
        kinds = dict(
            db.execute(
                "SELECT german, kind FROM words WHERE german IN ("
                "'beantworten — Präfix be-', 'machen ↔ tun', 'Vorfeldbesetzung', "
                "'keine Verlaufsform', 'Lehrer — Wortbildung -er', 'Hören (C2)', "
                "'Konjunktiv der Distanz', 'die Konferenz ↔ die Vorlesung', "
                "'je ↔ pro ↔ à')"
            ).fetchall()
        )
        suffixes = db.execute(
            "SELECT DISTINCT article FROM words WHERE german LIKE 'Suffix -%'"
        ).fetchall()
        gone = db.execute(
            "SELECT german FROM words WHERE german IN ("
            "'kein Verlaufsform', 'je ↔ pro ↔ á', 'die Bekanntschaft ↔ die Konferenz') "
            "OR (german = 'Lehrer' AND level_code = 'B2')"
        ).fetchall()
    finally:
        db.close()
    assert kinds == {
        "beantworten — Präfix be-": "note",
        "machen ↔ tun": "compare",
        "Vorfeldbesetzung": "note",
        "keine Verlaufsform": "note",
        "Lehrer — Wortbildung -er": "note",
        "Hören (C2)": "note",
        "Konjunktiv der Distanz": "note",
        "die Konferenz ↔ die Vorlesung": "compare",
        "je ↔ pro ↔ à": "compare",
    }
    assert suffixes == [(None,)]
    assert gone == []
