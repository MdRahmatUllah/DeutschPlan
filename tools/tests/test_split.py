"""PIPE-02 and BR-COURSE-02/03: how a level becomes two steps.

These run on hand-built records rather than workbooks, because the rule is
about counts and nothing else — a spreadsheet in the middle would only make the
uneven cases harder to write.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import GrammarRow, Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    LEVELS,
    SUBLEVELS,
    SplitError,
    assign_sublevels,
    check_every_step_has_words,
    resolve_grammar_levels,
    split_grammar,
    split_level,
)


def words(level: str, per_week: dict[int, int]) -> list[Word]:
    """One level's words, `per_week` of them in each week."""
    return [
        Word(
            source_file="test.xlsx",
            row=0,
            german=f"{level}-w{week}-{n}",
            english="x",
            level=level,
            week=week,
        )
        for week, count in per_week.items()
        for n in range(count)
    ]


def test_the_twelve_steps_are_the_ones_BR_COURSE_01_names():
    assert SUBLEVELS == (
        "A1.1",
        "A1.2",
        "A2.1",
        "A2.2",
        "B1.1",
        "B1.2",
        "B2.1",
        "B2.2",
        "C1.1",
        "C1.2",
        "C2.1",
        "C2.2",
    )
    assert len(LEVELS) == 6


class TestBoundary:
    def test_even_weeks_split_down_the_middle(self):
        split = split_level(words("A1", {1: 10, 2: 10, 3: 10, 4: 10}), "A1")
        assert split.boundary_week == 3
        assert (split.words_in_first, split.words_in_second) == (20, 20)

    def test_it_is_the_word_count_that_decides_not_the_week_number(self):
        # Weeks 1–2 are dense, 3–6 are thin. The middle *week* would be 4,
        # which would leave 62 words against 8. The middle by *words* is after
        # week 1.
        split = split_level(
            words("B1", {1: 40, 2: 22, 3: 2, 4: 2, 5: 2, 6: 2}), "B1"
        )
        assert split.boundary_week == 2
        assert (split.words_in_first, split.words_in_second) == (40, 30)

    def test_a_tie_takes_the_earlier_boundary(self):
        # 6 either side at week 2, and again nothing better later. Without a
        # rule the answer would depend on iteration order.
        split = split_level(words("A2", {1: 6, 2: 6}), "A2")
        assert split.boundary_week == 2

    def test_weeks_are_never_divided(self):
        # One fat week in the middle. No boundary makes the halves even, and
        # the rule is not allowed to fix that by cutting week 2 in half — a
        # week is a unit of teaching. Whichever side it lands on, it lands
        # whole, so one step ends up with 105 words and that is correct.
        every = words("C1", {1: 5, 2: 100, 3: 5})
        assign_sublevels(every)

        by_week: dict[int, set[str]] = {}
        for word in every:
            by_week.setdefault(word.week, set()).add(word.sublevel_code)
        assert all(len(steps) == 1 for steps in by_week.values()), by_week

    def test_weeks_out_of_order_in_the_sheet_do_not_matter(self):
        # Counts chosen so one boundary is strictly best, or a tie would hide
        # whether the order mattered.
        counts = {1: 10, 2: 10, 3: 5, 4: 6}
        in_order = split_level(words("C2", counts), "C2")
        scrambled = split_level(
            words("C2", {3: 5, 1: 10, 4: 6, 2: 10}), "C2"
        )
        assert in_order.boundary_week == scrambled.boundary_week == 3

    def test_missing_weeks_in_the_sequence_are_fine(self):
        # Authors skip week numbers. The boundary is a week that exists, not
        # the arithmetic midpoint of the numbering.
        split = split_level(words("A1", {1: 10, 5: 10, 9: 10, 13: 10}), "A1")
        assert split.boundary_week == 9


class TestRefusals:
    def test_a_level_with_no_words_says_which_one(self):
        with pytest.raises(SplitError, match=r"B2 has no words"):
            split_level(words("A1", {1: 4, 2: 4}), "B2")

    def test_a_level_with_one_week_cannot_split(self):
        # There is no boundary that leaves both halves non-empty, and inventing
        # one would mean dividing a week.
        with pytest.raises(SplitError, match=r"only week 1.*Week column"):
            split_level(words("A1", {1: 30}), "A1")

    def test_an_empty_step_fails_the_build(self):
        every = [w for level in LEVELS for w in words(level, {1: 2, 2: 2})]
        assign_sublevels(every)
        check_every_step_has_words(every)  # passes

        # Now take one step away.
        for word in every:
            if word.sublevel_code == "C2.2":
                word.sublevel_code = "C2.1"
        with pytest.raises(SplitError, match=r"C2\.2"):
            check_every_step_has_words(every)


class TestAssignment:
    def test_every_word_lands_in_a_step_of_its_own_level(self):
        every = [w for level in LEVELS for w in words(level, {1: 3, 2: 3, 3: 3})]
        assign_sublevels(every)
        for word in every:
            assert word.sublevel_code.startswith(word.level)

    def test_pipe_01_the_level_cell_decides_the_step(self):
        # Two words in the same week of the same workbook, different levels.
        # The week must not drag one into the other's step.
        mixed = [
            Word(source_file="f", row=1, german="a", english="x", level="A1", week=1),
            Word(source_file="f", row=2, german="b", english="x", level="A1", week=2),
            Word(source_file="f", row=3, german="c", english="x", level="B2", week=1),
            Word(source_file="f", row=4, german="d", english="x", level="B2", week=2),
        ]
        assign_sublevels(mixed)
        assert [w.sublevel_code for w in mixed] == ["A1.1", "A1.2", "B2.1", "B2.2"]

    def test_the_boundary_is_reported_for_meta(self):
        every = words("A1", {1: 10, 2: 10, 3: 10, 4: 10})
        splits = assign_sublevels(every)
        # meta.sublevel_week_boundaries is what lets the app say "A1.2 starts
        # at week 3" without re-deriving the split.
        assert splits["A1"].boundary_week == 3
        assert splits["A1"].weeks_in_first == 2


class TestGrammar:
    def grammar(self, level: str | None, count: int) -> list[GrammarRow]:
        return [
            GrammarRow(source_file="f", row=i, topic=f"t{i}", level=level)
            for i in range(count)
        ]

    def test_split_by_count_keeping_teaching_order(self):
        rows = self.grammar("A1", 7)
        split_grammar(rows, {})
        # BR-COURSE-03: by count, not by the word boundary. The odd topic goes
        # to X.1.
        assert [r.sublevel_code for r in rows] == ["A1.1"] * 4 + ["A1.2"] * 3
        assert [r.seq for r in rows] == [1, 2, 3, 4, 5, 6, 7]

    def test_order_is_the_workbook_order_not_sorted(self):
        rows = self.grammar("B1", 4)
        rows[0].topic = "zzz last alphabetically, first in teaching order"
        split_grammar(rows, {})
        assert rows[0].seq == 1 and rows[0].sublevel_code == "B1.1"

    def test_grammar_does_not_follow_the_word_boundary(self):
        # The two are authored separately: a level can teach most of its
        # grammar early and most of its vocabulary late. Following the word
        # boundary here would leave one step with a single topic.
        rows = self.grammar("C1", 10)
        split_grammar(rows, {})
        assert sum(r.sublevel_code == "C1.1" for r in rows) == 5
        assert sum(r.sublevel_code == "C1.2" for r in rows) == 5

    def test_a_single_topic_goes_to_the_first_step(self):
        rows = self.grammar("C2", 1)
        split_grammar(rows, {})
        assert rows[0].sublevel_code == "C2.1"

    def test_a_row_with_no_level_takes_the_workbook_fallback(self):
        rows = self.grammar(None, 2)
        resolve_grammar_levels(rows, "B2")
        split_grammar(rows, {})
        assert [r.level_code for r in rows] == ["B2", "B2"]

    def test_the_fallback_does_not_overwrite_a_level_that_is_there(self):
        rows = self.grammar("A1", 2)
        resolve_grammar_levels(rows, "C2")
        assert [r.level for r in rows] == ["A1", "A1"]
