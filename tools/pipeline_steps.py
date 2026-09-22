"""The derivations between reading a workbook and writing content.db.

Pure functions over the records `excel_to_sqlite.py` reads, so each PIPE rule
can be tested on its own, without a workbook and without a database.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Iterable, Sequence

# BR-COURSE-01: six levels, twelve steps, in this fixed order. Nothing derives
# this list — it is the course.
LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
SUBLEVELS = tuple(f"{level}.{half}" for level in LEVELS for half in (1, 2))


class PipelineError(Exception):
    """A failure the author can act on. Printed without a traceback.

    It lives here rather than in `excel_to_sqlite`, which imports this module —
    the other way round would be a cycle. Everything that fails a build derives
    from it, because a refusal that reaches the author as a stack trace is a
    message nobody reads.
    """


class SplitError(PipelineError):
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

    #: Every week the level actually has, sorted. Kept because the week
    #: numbers have gaps — authors skip them — so the count of weeks in a half
    #: cannot be derived from the boundary number alone.
    weeks: tuple[int, ...] = ()

    @property
    def first(self) -> str:
        return f"{self.level}.1"

    @property
    def second(self) -> str:
        return f"{self.level}.2"

    @property
    def weeks_in_first(self) -> int:
        return sum(1 for week in self.weeks if week < self.boundary_week)

    @property
    def weeks_in_second(self) -> int:
        return sum(1 for week in self.weeks if week >= self.boundary_week)


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
        weeks=tuple(weeks),
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


def split_grammar(rows: Sequence) -> None:
    """BR-COURSE-03: grammar splits by count, keeping teaching order.

    By count and not by the word boundary, because the two are authored
    separately: a level can teach most of its grammar in the first weeks and
    most of its vocabulary in the last. Splitting grammar on the word boundary
    would leave X.2 with one topic.

    Teaching order is the order the rows appear in the workbook, which is the
    order the author wrote them in. Nothing is sorted.

    It deliberately takes no splits: passing them in would say grammar
    consults the word boundary, which is the thing this must not do.
    """
    for level in LEVELS:
        of_level = [r for r in rows if getattr(r, "level", None) == level]
        if not of_level:
            continue
        half = (len(of_level) + 1) // 2  # the odd topic goes to X.1
        for index, row in enumerate(of_level):
            row.sublevel_code = (
                f"{level}.1" if index < half else f"{level}.2"
            )
            row.level_code = level
            row.seq = index + 1


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


# PIPE-03: sha1 over the four fields that identify a word, truncated.
#
# Sixteen hex characters is 64 bits. Over ~11,000 words the chance of any
# collision is about 3e-15, which is why the collision path below is a warning
# and a suffix rather than a redesign — but it exists, because a uid is a
# primary key and two words sharing one would silently merge a learner's
# progress on both.
UID_LENGTH = 16

#: The fields the uid is made of, in order. Changing this list changes every
#: uid, which orphans every learner's word_state — so it is spelled out here
#: rather than inferred from the record.
UID_FIELDS = ("level", "german", "pos", "english")


class UidCollision(PipelineError):
    """Two different words hashed to the same uid."""


def uid_for(word, *, suffix: int | None = None) -> str:
    """`sha1(level|german|pos|english)[:16]`, as PIPE-03 specifies.

    A missing `pos` joins as an empty string rather than being skipped, so
    "der|Bank||bank" and "der|Bank|noun|bank" are different words — dropping
    the separator would make them the same.

    The digest is over UTF-8, so an umlaut hashes the same on every platform.
    """
    key = "|".join(_uid_part(word, name) for name in UID_FIELDS)
    if suffix is not None:
        key = f"{key}|{suffix}"
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:UID_LENGTH]


def _uid_part(word, name: str) -> str:
    value = getattr(word, name, None)
    return "" if value is None else str(value)


def assign_uids(words: Sequence) -> list[str]:
    """Sets `uid` on every word. Returns a line per collision, for the report.

    A collision is resolved by hashing again with the *occurrence* number
    appended: the second word to hash to a given uid gets suffix 2, the third
    3. The doc says "the sequence number", and the global `seq` would satisfy
    the letter of it, but `seq` is reading order across every workbook — one
    unrelated word inserted at the top shifts it, and the colliding word's uid
    would change with it, orphaning that learner's progress over an edit that
    had nothing to do with their word. The occurrence index depends only on
    the collision.

    Two rows that are genuinely identical in all four fields are a duplicate,
    not a hash collision, and get the same treatment — the second one becomes
    its own word. `verify_content.py` is where that is reported as a data
    problem rather than a hash one.
    """
    seen: dict[str, object] = {}
    occurrences: dict[str, int] = {}
    reports: list[str] = []

    for word in words:
        uid = uid_for(word)
        if uid in seen:
            other = seen[uid]
            occurrences[uid] = occurrences.get(uid, 1) + 1
            uid = uid_for(word, suffix=occurrences[uid])
            reports.append(
                f"uid collision: {word.source_file} row {word.row} "
                f"({word.level}|{word.german}|{word.pos}|{word.english}) "
                f"collided with {other.source_file} row {other.row}; "
                f"resolved to {uid}"
            )
            # Unreachable by construction: the suffix makes every retry a
            # different key. It stays because a uid is a primary key, and
            # writing two rows with the same one is the outcome that must not
            # exist even if the reasoning above is ever wrong.
            if uid in seen:
                raise UidCollision(
                    f"{word.source_file} row {word.row} still collides after "
                    f"appending its occurrence number. Two rows cannot share "
                    f"a uid, so one of them has to change."
                )
        seen[uid] = word
        word.uid = uid

    return reports


#: Grammar topics carry a uid too: `content-database.md` gives
#: `grammar_topics.uid PK`, and `grammar_state.grammar_uid` in the learner's
#: database points at it. A different recipe, because a topic has no part of
#: speech and no English gloss.
GRAMMAR_UID_FIELDS = ("level", "topic")


def grammar_uid_for(row, *, suffix: int | None = None) -> str:
    """`sha1(level|topic)[:16]`.

    Same shape and same stability contract as `uid_for`: it keys the learner's
    grammar scheduling, so changing it loses their progress on every topic.
    """
    key = "|".join(_uid_part(row, name) for name in GRAMMAR_UID_FIELDS)
    if suffix is not None:
        key = f"{key}|{suffix}"
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:UID_LENGTH]


def assign_grammar_uids(rows: Sequence) -> list[str]:
    """Sets `uid` on every grammar row, resolving collisions as words do.

    Two rows with the same topic in the same level are a duplicate in the
    workbook rather than a hash collision, and the report names both rows.
    """
    seen: dict[str, object] = {}
    occurrences: dict[str, int] = {}
    reports: list[str] = []

    for row in rows:
        uid = grammar_uid_for(row)
        if uid in seen:
            other = seen[uid]
            occurrences[uid] = occurrences.get(uid, 1) + 1
            uid = grammar_uid_for(row, suffix=occurrences[uid])
            reports.append(
                f"grammar uid collision: {row.source_file} row {row.row} "
                f"({row.level}|{row.topic}) collided with "
                f"{other.source_file} row {other.row}; resolved to {uid}"
            )
        seen[uid] = row
        row.uid = uid

    return reports
