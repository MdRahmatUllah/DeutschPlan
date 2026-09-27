"""#631: the cloze port, the gappable-example gate and the warning for an
example that does not say its word.

`tools/cloze_vectors.json` is the contract with `lib/domain/cloze.dart`;
`app/test/domain/cloze_test.dart` runs the same file.
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cloze import cloze_gap, examples_without_their_word, names_its_word  # noqa: E402
from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import pair_examples  # noqa: E402
from verify_content import check_every_word_can_be_gapped  # noqa: E402

TOOLS = Path(__file__).resolve().parent.parent
VECTORS = json.loads((TOOLS / "cloze_vectors.json").read_text(encoding="utf-8"))["vectors"]
SHIPPED = TOOLS.parent / "app" / "assets" / "db" / "content.db"


def test_631_the_vector_file_is_populated():
    assert len(VECTORS) >= 20


@pytest.mark.parametrize("vector", VECTORS, ids=lambda v: f"{v['german']}: {v['why']}")
def test_631_the_port_blanks_what_the_app_blanks(vector):
    gap = cloze_gap(vector["sentence"], vector["german"], vector["pos"], vector.get("forms"))
    assert (None if gap is None else vector["sentence"][gap[0] : gap[1]]) == vector["gap"]


@pytest.mark.parametrize(
    ("sentence", "german", "forms", "named"),
    [
        ("Er liest die Zeitung.", "lesen", "liest · hat gelesen", True),
        ("Erdäpfelsalat gehört zum Schnitzel.", "Erdapfel", "Erdäpfel", True),
        ("Er darf subjektiv sein, aber nicht beliebig.", "Essay", "Essays", False),
        ("Hast du Zeit?", "haben", "hat · hat gehabt", False),
    ],
)
def test_631_an_example_names_its_word_by_a_gap_a_stem_or_a_form(sentence, german, forms, named):
    assert names_its_word(sentence, german, forms) is named


def word(german: str, examples: str, kind: str = "vocab", pos: str | None = "noun") -> Word:
    w = Word(source_file="t.xlsx", row=7, german=german, pos=pos, kind=kind, examples_de=examples)
    w.examples = pair_examples(examples, None)
    return w


def test_631_the_build_warns_per_example_that_does_not_say_its_word():
    warnings = examples_without_their_word(
        [
            word("Essay", "Der Essay denkt vor dem Leser.\nEr darf subjektiv sein."),
            word("Vorfeldbesetzung", "Morgen komme ich.", kind="note"),
        ]
    )
    assert warnings == [
        "example without its word: t.xlsx row 7 (Essay) example 2: 'Er darf subjektiv sein.'"
    ]


def gate(tmp_path, statements) -> list:
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    db = sqlite3.connect(copy)
    try:
        for statement in statements:
            db.execute(statement)
        return check_every_word_can_be_gapped(db)
    finally:
        db.close()


def test_631_the_shipped_course_gaps_every_word_and_names_it_almost_everywhere(tmp_path):
    assert gate(tmp_path, []) == []
    db = sqlite3.connect(f"file:{SHIPPED}?mode=ro", uri=True)
    try:
        rows = db.execute(
            "SELECT w.german, w.pos, w.forms, e.german FROM word_examples e "
            "JOIN words w ON w.uid = e.word_uid WHERE w.kind = 'vocab'"
        ).fetchall()
    finally:
        db.close()
    without = [
        sentence
        for german, pos, forms, sentence in rows
        if cloze_gap(sentence, german, pos, forms) is None and not names_its_word(sentence, german, forms)
    ]
    assert len(without) < 30, without


def test_870_with_its_forms_the_cloze_gaps_a_strong_verb_and_an_umlaut_plural():
    db = sqlite3.connect(f"file:{SHIPPED}?mode=ro", uri=True)
    try:
        rows = db.execute(
            "SELECT w.german, w.pos, w.forms, e.german FROM word_examples e "
            "JOIN words w ON w.uid = e.word_uid"
        ).fetchall()
    finally:
        db.close()
    verbs = [row for row in rows if row[1] == "verb"]
    # Before: 653 of 11,270 examples, and 14 % of the verbs'.
    assert sum(cloze_gap(s, g, p, f) is None for g, p, f, s in rows) < 0.035 * len(rows)
    assert sum(cloze_gap(s, g, p, f) is None for g, p, f, s in verbs) < 0.03 * len(verbs)


def test_631_a_word_no_example_of_which_the_cloze_can_gap_fails_the_gate(tmp_path):
    failures = gate(
        tmp_path,
        [
            "UPDATE word_examples SET german = 'Das ist gut.' WHERE word_uid = "
            "(SELECT uid FROM words WHERE german = 'Rechnung' AND kind = 'vocab' LIMIT 1)"
        ],
    )
    assert [f.gate for f in failures] == ["examples"]
    assert "Rechnung" in failures[0].message


def test_870_a_word_the_cloze_gaps_only_by_its_forms_passes_the_gate(tmp_path):
    assert (
        gate(
            tmp_path,
            [
                "UPDATE word_examples SET german = 'Er liest die Zeitung.' WHERE word_uid = "
                "(SELECT uid FROM words WHERE german = 'lesen' AND kind = 'vocab' LIMIT 1)"
            ],
        )
        == []
    )


def test_631_a_note_is_not_held_to_it(tmp_path):
    assert (
        gate(
            tmp_path,
            [
                "UPDATE word_examples SET german = 'Das ist gut.' WHERE word_uid = "
                "(SELECT uid FROM words WHERE german = 'Rechnung' AND kind = 'vocab' LIMIT 1)",
                "UPDATE words SET kind = 'note' WHERE german = 'Rechnung'",
            ],
        )
        == []
    )


def test_631_the_build_prints_the_warning(tmp_path, capsys):
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    first = sources[0].words[0]
    first.examples_de, first.examples_en = "Das ist gut.", "That is good."
    derive(sources)
    assert f"example without its word: {first.source_file} row {first.row}" in capsys.readouterr().err


def test_631_verify_runs_the_gate(tmp_path):
    from verify_content import verify

    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    db = sqlite3.connect(copy)
    with db:
        db.execute(
            "UPDATE word_examples SET german = 'Das ist gut.' WHERE word_uid = "
            "(SELECT uid FROM words WHERE german = 'Rechnung' AND kind = 'vocab' LIMIT 1)"
        )
    db.close()
    assert any("no example the cloze can gap" in f.message for f in verify(copy))
