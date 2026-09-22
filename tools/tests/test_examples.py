"""PIPE-05 and PIPE-06: examples, and the cells Excel would have eaten."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402,F401

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    FORMULA_PREFIXES,
    TEXT_FIELDS,
    assign_examples,
    check_formula_prefixes,
    pair_examples,
)


def word(**kwargs) -> Word:
    base = {
        "source_file": "test.xlsx",
        "row": 7,
        "german": "Haus",
        "english": "house",
        "level": "A1",
    }
    return Word(**{**base, **kwargs})


class TestPairing:
    def test_lines_pair_by_position(self):
        pairs = pair_examples("Eins.\nZwei.", "One.\nTwo.")
        assert [(e.ord, e.german, e.english) for e in pairs] == [
            (1, "Eins.", "One."),
            (2, "Zwei.", "Two."),
        ]

    def test_an_unmatched_german_line_gets_no_translation(self):
        # PIPE-06 spells this one out: the sentence is still worth showing.
        pairs = pair_examples("Eins.\nZwei.\nDrei.", "One.\nTwo.")
        assert pairs[2].english is None
        assert pairs[2].german == "Drei."

    def test_a_surplus_english_line_is_dropped(self):
        # A translation with no sentence has nowhere to attach.
        pairs = pair_examples("Eins.", "One.\nTwo.")
        assert len(pairs) == 1 and pairs[0].english == "One."

    def test_a_blank_line_does_not_shift_the_pairing(self):
        # The failure this ordering exists to avoid: a stray newline in the
        # German cell would otherwise move every translation down one, and
        # every example after it would be mistranslated rather than missing.
        pairs = pair_examples("Eins.\n\nZwei.", "One.\nTwo.")
        assert [(e.german, e.english) for e in pairs] == [
            ("Eins.", "One."),
            ("Zwei.", "Two."),
        ]

    def test_trailing_newlines_are_not_examples(self):
        assert len(pair_examples("Eins.\n\n\n", "One.\n")) == 1

    def test_whitespace_around_a_line_goes(self):
        assert pair_examples("  Eins.  ", " One. ")[0] == pair_examples(
            "Eins.", "One."
        )[0]

    def test_no_german_means_no_examples(self):
        assert pair_examples(None, "One.") == []
        assert pair_examples("", "One.") == []

    def test_ord_starts_at_one_and_is_contiguous(self):
        # (word_uid, ord) is the primary key of word_examples.
        pairs = pair_examples("A.\nB.\nC.", None)
        assert [e.ord for e in pairs] == [1, 2, 3]

    def test_it_is_wired_into_the_word(self):
        w = word(examples_de="Eins.\nZwei.", examples_en="One.")
        assign_examples([w])
        assert len(w.examples) == 2
        assert w.examples[1].english is None


class TestFormulaPrefixes:
    def test_the_four_prefixes_are_the_ones_the_doc_names(self):
        assert FORMULA_PREFIXES == ("=", "+", "-", "@")

    def test_each_one_is_warned_about(self):
        for prefix in FORMULA_PREFIXES:
            warnings = check_formula_prefixes(
                [word(collocations=f"{prefix}something")]
            )
            assert len(warnings) == 1, prefix
            assert "row 7" in warnings[0] and "collocations" in warnings[0]

    def test_the_value_is_not_changed(self):
        # Storing it as text is the requirement; the warning is about the
        # workbook, which Excel may rewrite the next time it is opened.
        w = word(collocations="=SUM(A1:A2)")
        check_formula_prefixes([w])
        assert w.collocations == "=SUM(A1:A2)"

    def test_the_warning_says_what_to_do(self):
        warnings = check_formula_prefixes([word(forms="-los")])
        assert "apostrophe" in warnings[0]

    def test_an_ordinary_cell_is_silent(self):
        assert check_formula_prefixes([word(collocations="mit + dative")]) == []

    def test_every_free_text_field_is_checked(self):
        # A field left out of TEXT_FIELDS is one nobody is warned about.
        for field in TEXT_FIELDS:
            assert check_formula_prefixes([word(**{field: "=x"})]), field

    def test_the_checked_fields_are_the_free_text_ones(self):
        # Not level, not week, not freq: those are not typed prose and a
        # warning on them would be noise nobody reads.
        assert set(TEXT_FIELDS).isdisjoint({"level", "week", "freq", "category"})


class TestTheBuildOutput:
    """#46: the warnings are summarised, not just dumped."""

    def capture(self, warnings: list[str], capsys) -> str:
        from excel_to_sqlite import _report

        _report(warnings)
        return capsys.readouterr().err

    def test_a_clean_build_says_nothing(self, capsys):
        assert self.capture([], capsys) == ""

    def test_each_warning_is_printed(self, capsys):
        err = self.capture(["formula-looking cell: row 3", "uid collision: row 9"], capsys)
        assert "row 3" in err and "row 9" in err

    def test_many_of_one_kind_are_capped_and_counted(self, capsys):
        from excel_to_sqlite import WARNING_SAMPLE

        many = [f"formula-looking cell: row {i}" for i in range(50)]
        err = self.capture(many, capsys)

        assert err.count("formula-looking cell: row") == WARNING_SAMPLE
        assert f"...and {50 - WARNING_SAMPLE} more" in err

    def test_the_last_line_totals_every_kind(self, capsys):
        # The line someone reads when the build scrolled past.
        err = self.capture(
            ["formula-looking cell: a", "formula-looking cell: b", "uid collision: c"],
            capsys,
        )
        assert err.strip().splitlines()[-1] == (
            "warnings: 2 formula-looking cell, 1 uid collision"
        )


class TestGrammarCells:
    """Grammar is free text an author types, so PIPE-05 applies there too."""

    def row(self, **kwargs):
        from excel_to_sqlite import GrammarRow

        base = {"source_file": "test.xlsx", "row": 4, "topic": "Dative"}
        return GrammarRow(**{**base, **kwargs})

    def test_a_dash_in_a_rule_is_warned_about(self):
        from pipeline_steps import GRAMMAR_TEXT_FIELDS

        warnings = check_formula_prefixes(
            [self.row(rule="-en endings on weak nouns")], GRAMMAR_TEXT_FIELDS
        )
        assert len(warnings) == 1 and "rule" in warnings[0]

    def test_every_grammar_text_field_is_checked(self):
        from pipeline_steps import GRAMMAR_TEXT_FIELDS

        for field in GRAMMAR_TEXT_FIELDS:
            assert check_formula_prefixes(
                [self.row(**{field: "=gleich"})], GRAMMAR_TEXT_FIELDS
            ), field


def test_a_prefix_on_the_second_line_is_found():
    # examples_de holds one sentence per line, which is why the field is in
    # the list at all; checking only the cell would miss every line but one.
    warnings = check_formula_prefixes(
        [word(examples_de="Das ist gut.\n-los bedeutet ohne.")]
    )
    assert len(warnings) == 1 and "-los" in warnings[0]


def test_uid_collisions_are_never_truncated(capsys):
    # Each one names a different word whose primary key changed, and
    # word_state rows key to it. "…and 40 more" would say forty words moved
    # and not which.
    from excel_to_sqlite import UNCAPPED_WARNINGS, WARNING_SAMPLE, _report

    assert "uid collision" in UNCAPPED_WARNINGS

    many = [f"uid collision: row {i}" for i in range(WARNING_SAMPLE + 15)]
    _report(many)
    err = capsys.readouterr().err

    assert err.count("uid collision: row") == len(many)
    assert "more uid collision" not in err


def test_derive_actually_checks_the_grammar_rows(tmp_path, capsys):
    """The wiring, not just the function.

    `check_formula_prefixes` is easy to test on its own and easy to forget to
    call. This goes through `derive`, which is what the build runs.
    """
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    def total(mutate: bool) -> int:
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        if mutate:
            sources[1].grammar[0].rule = "-en endings on weak nouns"
        derive(sources)
        summary = capsys.readouterr().err.strip().splitlines()[-1]
        return int(summary.split()[1])

    write_all(tmp_path)

    # The total, not the printed lines: the fixture workbooks carry two dozen
    # formula-looking word cells on purpose, and the cap means one extra
    # grammar line never reaches the screen. The count still moves.
    assert total(mutate=True) == total(mutate=False) + 1
