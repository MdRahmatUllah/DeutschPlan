"""The derivations between reading a workbook and writing content.db.

Pure functions over the records `excel_to_sqlite.py` reads, so each PIPE rule
can be tested on its own, without a workbook and without a database.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence

# BR-COURSE-01: six levels, twelve steps, in this fixed order. Nothing derives
# this list — it is the course.
LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
SUBLEVELS = tuple(f"{level}.{half}" for level in LEVELS for half in (1, 2))


class SplitError(Exception):
    """A split that would leave a step the app cannot show."""


@dataclass(frozen=True)
class LevelSplit:
    """Where one level divides into X.1 and X.2.

    `boundary_week` is the first week belonging to X.2; every earlier week is
    X.1. Weeks are never divided, which is the whole point of PIPE-02 — a week
    is a unit of teaching, and half of one in each step would make both look
    arbitrary.
    """

    level: str
    boundary_week: int
    words_in_first: int
    words_in_second: int

    @property
    def first(self) -> str:
        return f"{self.level}.1"

    @property
    def second(self) -> str:
        return f"{self.level}.2"

    @property
    def weeks_in_first(self) -> int:
        return self.boundary_week - 1


def split_level(words: Sequence, level: str) -> LevelSplit:
    """PIPE-02: the week boundary nearest the middle of the level by word count.

    Not the middle week, and not the middle word: the boundary that leaves the
    two halves closest to equal in *words*. A level whose early weeks are dense
    and late weeks thin would otherwise produce a 70/30 split, and the learner
    would meet X.2 in half the time X.1 took.

    Ties go to the earlier boundary, so the result never depends on iteration
    order.
    """
    of_level = [w for w in words if w.level == level]
    if not of_level:
        raise SplitError(
            f"{level} has no words. Every one of the twelve steps must be "
            f"non-empty (BR-COURSE-01), so this is a missing workbook or a "
            f"wrong Level column rather than a split to fix."
        )

    weeks = sorted({_week_of(w) for w in of_level})
    if len(weeks) < 2:
        raise SplitError(
            f"{level} has only week {weeks[0]}, so there is no boundary to "
            f"split on. Weeks are never divided — fill in the Week column, or "
            f"this level cannot become two steps."
        )

    counts = {week: sum(1 for w in of_level if _week_of(w) == week) for week in weeks}
    total = len(of_level)

    # Every boundary that leaves both halves non-empty: the first week can
    # never start X.2, or X.1 would be empty.
    best: tuple[int, int] | None = None
    running = 0
    for week in weeks[:-1]:
        running += counts[week]
        imbalance = abs(running - (total - running))
        if best is None or imbalance < best[0]:
            best = (imbalance, week)

    assert best is not None  # weeks has at least two entries
    _, last_week_of_first = best
    boundary = weeks[weeks.index(last_week_of_first) + 1]

    in_first = sum(counts[w] for w in weeks if w < boundary)
    return LevelSplit(
        level=level,
        boundary_week=boundary,
        words_in_first=in_first,
        words_in_second=total - in_first,
    )


def _week_of(word) -> int:
    """A word with no Week sits in week 1.

    The column is optional, and a level where nobody filled it in is one big
    week — which `split_level` then refuses, with a message saying so, rather
    than inventing a boundary.
    """
    return word.week if getattr(word, "week", None) else 1


def assign_sublevels(words: Sequence) -> dict[str, LevelSplit]:
    """Sets `sublevel_code` on every word and returns the boundaries.

    The returned map is what goes into `meta.sublevel_week_boundaries`, so the
    app can say "Step A1.2 starts at week 7" without re-deriving it.
    """
    splits: dict[str, LevelSplit] = {}
    for level in LEVELS:
        if not any(w.level == level for w in words):
            continue
        split = split_level(words, level)
        splits[level] = split
        for word in words:
            if word.level != level:
                continue
            word.sublevel_code = (
                split.first if _week_of(word) < split.boundary_week else split.second
            )
    return splits


def split_grammar(rows: Sequence, splits: dict[str, LevelSplit]) -> None:
    """BR-COURSE-03: grammar splits by count, keeping teaching order.

    By count and not by the word boundary, because the two are authored
    separately: a level can teach most of its grammar in the first weeks and
    most of its vocabulary in the last. Splitting grammar on the word boundary
    would leave X.2 with one topic.

    Teaching order is the order the rows appear in the workbook, which is the
    order the author wrote them in. Nothing is sorted.
    """
    for level in LEVELS:
        of_level = [r for r in rows if _grammar_level(r, splits) == level]
        if not of_level:
            continue
        half = (len(of_level) + 1) // 2  # the odd topic goes to X.1
        for index, row in enumerate(of_level):
            row.sublevel_code = (
                f"{level}.1" if index < half else f"{level}.2"
            )
            row.level_code = level
            row.seq = index + 1


def _grammar_level(row, splits: dict[str, LevelSplit]) -> str | None:
    """A grammar row's level, or the fallback when it names none.

    `content-pipeline.md`: the manifest's workbook order is the fallback level
    order. A row with no level belongs to the first level its own workbook
    carries, which `resolve_grammar_levels` fills in before this runs.
    """
    return getattr(row, "level", None)


def resolve_grammar_levels(rows: Iterable, fallback: str) -> None:
    """Fills in the level for grammar rows that name none.

    The fallback is the first level of the workbook the row came from — the
    manifest's order is what makes that deterministic.
    """
    for row in rows:
        if not getattr(row, "level", None):
            row.level = fallback


def check_every_step_has_words(words: Sequence) -> None:
    """PIPE-08's first gate, checked here so the build fails before writing.

    Twelve steps, each non-empty. A step with no words is a screen the learner
    can open and find blank, with no way to tell whether it is a bug or the
    course.
    """
    counts = {code: 0 for code in SUBLEVELS}
    for word in words:
        code = getattr(word, "sublevel_code", None)
        if code in counts:
            counts[code] += 1

    empty = [code for code, count in counts.items() if count == 0]
    if empty:
        raise SplitError(
            f"these steps have no words: {', '.join(empty)}. Every one of the "
            f"twelve must be non-empty (BR-COURSE-01)."
        )
