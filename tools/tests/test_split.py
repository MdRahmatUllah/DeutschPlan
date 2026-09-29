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
    def test_BR_COURSE_02_even_weeks_split_down_the_middle(self):
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
        # the arithmetic midpoint of the numbering — and the week *counts* are
        # weeks that exist too, not a subtraction of week numbers. This level
        # has four weeks, two each side; `boundary_week - 1` would say eight.
        split = split_level(words("A1", {1: 10, 5: 10, 9: 10, 13: 10}), "A1")
        assert split.boundary_week == 9
        assert split.weeks == (1, 5, 9, 13)
        assert (split.weeks_in_first, split.weeks_in_second) == (2, 2)


class TestShippedBoundary:
    """#923: once a course has shipped, its boundary weeks are kept."""

    def test_923_dropping_rows_leaves_every_other_words_step(self):
        every = words("B2", {1: 10, 2: 10, 3: 10, 4: 10})
        shipped = assign_sublevels(every)["B2"].boundary_week
        steps = {id(word): word.sublevel_code for word in every}

        # Week 4's rows go: split anew, the middle moves and week 2 with it,
        # into B2.2, under learners who finished B2.1.
        rest = every[:30]
        assert assign_sublevels(rest)["B2"].boundary_week != shipped
        split = assign_sublevels(rest, {"B2": shipped})["B2"]
        assert split.boundary_week == shipped
        assert all(word.sublevel_code == steps[id(word)] for word in rest)

    def test_923_a_kept_boundary_that_empties_a_step_says_how_to_move_it(self):
        with pytest.raises(SplitError, match=r"B2\.2 with no words.*--move-boundaries"):
            split_level(words("B2", {1: 4, 2: 4}), "B2", 3)
        with pytest.raises(SplitError, match=r"B2\.1 with no words"):
            split_level(words("B2", {2: 4, 3: 4}), "B2", 2)


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
        assert (splits["A1"].weeks_in_first, splits["A1"].weeks_in_second) == (2, 2)


class TestGrammar:
    def grammar(self, level: str | None, count: int) -> list[GrammarRow]:
        return [
            GrammarRow(
                source_file="f", row=i, topic=f"t{i}", level=level, uid=f"u{i}"
            )
            for i in range(count)
        ]

    def test_970_dropping_a_topic_leaves_every_other_topics_step(self):
        # Shipped 4 + 3. Split anew by count, dropping t6 moves t3 into B1.2
        # under learners who finished B1.1. Kept, nothing moves, whichever
        # topic goes, the first B1.2 topic too: the next one takes over.
        shipped_rows = self.grammar("B1", 7)
        split_grammar(shipped_rows)
        shipped = {row.uid: row.sublevel_code for row in shipped_rows}

        for gone in range(7):
            rest = [r for r in self.grammar("B1", 7) if r.uid != f"u{gone}"]
            split_grammar(rest, shipped)
            assert all(r.sublevel_code == shipped[r.uid] for r in rest), gone
        rest = self.grammar("B1", 6)
        split_grammar(rest)
        assert rest[3].sublevel_code != shipped["u3"], "by count it moved"

    def test_970_a_new_topic_takes_the_step_of_its_place(self):
        shipped = {f"u{i}": "A2.1" if i < 3 else "A2.2" for i in range(6)}
        rows = self.grammar("A2", 6)
        def new(uid: str) -> GrammarRow:
            return GrammarRow(source_file="f", row=9, topic=uid, level="A2", uid=uid)

        rows.insert(1, new("new1"))
        rows.append(new("new2"))
        report = split_grammar(rows, shipped)
        steps = {row.uid: row.sublevel_code for row in rows}
        assert (steps["new1"], steps["new2"]) == ("A2.1", "A2.2")
        assert all(steps[uid] == step for uid, step in shipped.items())
        assert report == [], "kept, A2.2 starts at t3, as by count"

    def test_970_a_level_with_no_shipped_x2_topic_left_splits_by_count(self):
        rows = self.grammar("C1", 4)
        split_grammar(rows, {"u0": "C1.1", "u1": "C1.1", "gone": "C1.2"})
        assert [r.sublevel_code for r in rows] == ["C1.1"] * 2 + ["C1.2"] * 2

    def test_970_a_kept_split_that_is_not_the_one_by_count_says_so(self):
        rows = self.grammar("B2", 6)
        report = split_grammar(rows, {"u1": "B2.2"})
        assert [r.sublevel_code for r in rows] == ["B2.1"] + ["B2.2"] * 5
        assert report == [
            "grammar boundary kept: B2.2 starts at topic 2 of 6, 't1', as "
            "shipped; split anew it would start at topic 4 (--move-boundaries)"
        ]

    @pytest.mark.parametrize("at", [0, 1])
    def test_970_a_reordered_level_stops_the_build_naming_each_move(self, at):
        # Agent-1's case on #1000: B1 shipped 4 + 3, and t5 put first (or
        # second) would have moved the shipped B1.1 topics after it into
        # B1.2, under a line that said "kept".
        shipped = {f"u{i}": "B1.1" if i < 4 else "B1.2" for i in range(7)}
        rows = self.grammar("B1", 7)
        rows.insert(at, rows.pop(5))
        with pytest.raises(SplitError) as error:
            split_grammar(rows, shipped)
        lines = str(error.value).splitlines()
        assert lines[: 4 - at] == [
            f"grammar topic moved: 't{i}' B1.1 -> B1.2" for i in range(at, 4)
        ]
        assert f"would move {4 - at} topic(s)" in lines[4 - at]

    def test_970_a_level_with_no_shipped_x1_topic_left_stops_the_build(self):
        shipped = {f"u{i}": "B1.1" if i < 4 else "B1.2" for i in range(7)}
        with pytest.raises(SplitError, match=r"leave B1\.1 with no topics"):
            split_grammar(self.grammar("B1", 7)[4:], shipped)

    def test_BR_COURSE_03_split_by_count_keeping_teaching_order(self):
        rows = self.grammar("A1", 7)
        split_grammar(rows)
        # BR-COURSE-03: by count, not by the word boundary. The odd topic goes
        # to X.1.
        assert [r.sublevel_code for r in rows] == ["A1.1"] * 4 + ["A1.2"] * 3
        assert [r.seq for r in rows] == [1, 2, 3, 4, 5, 6, 7]

    def test_order_is_the_workbook_order_not_sorted(self):
        rows = self.grammar("B1", 4)
        rows[0].topic = "zzz last alphabetically, first in teaching order"
        split_grammar(rows)
        assert rows[0].seq == 1 and rows[0].sublevel_code == "B1.1"

    def test_grammar_does_not_follow_the_word_boundary(self):
        # The two are authored separately: a level can teach most of its
        # grammar early and most of its vocabulary late. Following the word
        # boundary here would leave one step with a single topic.
        rows = self.grammar("C1", 10)
        split_grammar(rows)
        assert sum(r.sublevel_code == "C1.1" for r in rows) == 5
        assert sum(r.sublevel_code == "C1.2" for r in rows) == 5

    def test_a_single_topic_goes_to_the_first_step(self):
        rows = self.grammar("C2", 1)
        split_grammar(rows)
        assert rows[0].sublevel_code == "C2.1"

    def test_a_row_with_no_level_takes_the_workbook_fallback(self):
        rows = self.grammar(None, 2)
        resolve_grammar_levels(rows, "B2")
        split_grammar(rows)
        assert [r.level_code for r in rows] == ["B2", "B2"]

    def test_the_fallback_is_the_book_level_not_its_earliest(self, tmp_path):
        # A book that carries A1 and A2 on the way to B1, as the combined
        # tracker did until it was split. An unlabelled topic in it is a B1
        # topic; filing it under A1 would teach it in the very first step.
        from excel_to_sqlite import derive, read_workbook  # noqa: PLC0415

        from fixtures.make_workbooks import write_all, write_workbook

        directory = tmp_path  # pytest removes it; mkdtemp leaked (#707)
        write_all(directory)
        write_workbook(directory / "German_A1-B1_Tracker.xlsx", ["A1", "A2", "B1"])
        sources = [
            read_workbook(directory / name)
            for name in (
                "German_A1-B1_Tracker.xlsx",
                "German_B2_Tracker.xlsx",
                "German_C1_Tracker.xlsx",
                "German_C2_Tracker.xlsx",
            )
        ]
        for row in sources[0].grammar:
            row.level = None

        derive(sources)
        assert {r.level_code for r in sources[0].grammar} == {"B1"}

    def test_the_fallback_does_not_overwrite_a_level_that_is_there(self):
        rows = self.grammar("A1", 2)
        resolve_grammar_levels(rows, "C2")
        assert [r.level for r in rows] == ["A1", "A1"]
