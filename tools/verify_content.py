"""PIPE-08: the gates a content build has to pass before it ships.

`content-pipeline.md`: "verify_content.py fails the build if: a required
sheet/column is missing, a step has 0 words, a word has no example, a uid
collision remains, FTS tables are empty, or a `gender`/`separable` tip is on a
word of another class (#321)."

The first of those is enforced while reading the workbooks, where the message
can name the sheet and the row — by the time a database exists, that
information is gone. The others are checked here, against the file that
would actually ship.

Every failure names what to change, because the person reading it is an author
with a spreadsheet open, not a programmer with a debugger.

Run it through `make content`, which builds and then verifies. Running this
module directly checks an existing content.db.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pipeline_steps import SUBLEVELS, read_tips, tip_pos  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "content" / "build" / "content.db"
DEFAULT_TIPS = REPO_ROOT / "content" / "interference_tips.csv"

#: Every step must have words. BR-COURSE-01 fixes the list, so a missing step
#: is a screen the learner can open and find blank. Taken from the pipeline's
#: own list rather than restated: a fifth workbook that adds a level should
#: change one constant, not two.
EXPECTED_STEPS = len(SUBLEVELS)

#: The three search tables. An empty one is a whole search tier that silently
#: returns nothing.
FTS_TABLES = ("words_fts", "words_trigram", "examples_fts")

#: How many offending rows a failure lists before it says "and N more". An
#: author fixing a spreadsheet needs examples, not five thousand lines.
SAMPLE = 8


@dataclass
class Failure:
    gate: str
    message: str

    def __str__(self) -> str:
        return f"{self.gate}: {self.message}"


def _sample(rows: list[str]) -> str:
    shown = ", ".join(rows[:SAMPLE])
    if len(rows) > SAMPLE:
        shown += f", and {len(rows) - SAMPLE} more"
    return shown


def check_every_step_has_words(db: sqlite3.Connection) -> list[Failure]:
    """Gate 2: a step with no words."""
    rows = db.execute(
        "SELECT code, word_count FROM sublevels ORDER BY ord"
    ).fetchall()

    failures = []
    if len(rows) != EXPECTED_STEPS:
        have = ", ".join(code for code, _ in rows) or "none"
        failures.append(
            Failure(
                "steps",
                f"the course has {len(rows)} steps, not {EXPECTED_STEPS}. "
                f"Found: {have}. Every level needs words in both halves — "
                f"check the Level column of each workbook.",
            )
        )

    empty = [code for code, count in rows if count == 0]
    if empty:
        failures.append(
            Failure(
                "steps",
                f"{_sample(empty)} have no words. The learner can open the "
                f"step and will find it blank.",
            )
        )
    return failures


def check_every_word_has_an_example(db: sqlite3.Connection) -> list[Failure]:
    """Gate 3: a word with no example sentence.

    A word with no example cannot produce a cloze card, a practice sentence or
    a gap-fill quiz item — three features that simply do not appear for it,
    with nothing on screen to say why.
    """
    rows = [
        f"{german} ({code})"
        for german, code in db.execute(
            "SELECT w.german, w.sublevel_code FROM words w "
            "LEFT JOIN word_examples e ON e.word_uid = w.uid "
            "WHERE e.word_uid IS NULL ORDER BY w.seq"
        )
    ]
    if not rows:
        return []
    return [
        Failure(
            "examples",
            f"{len(rows)} words have no example sentence: {_sample(rows)}. "
            f"Fill in the Examples (DE) column for each.",
        )
    ]


def check_no_uid_collision(db: sqlite3.Connection) -> list[Failure]:
    """Gate 4: a uid collision that survived into the database.

    The primary key makes a duplicate impossible to write, so this checks the
    thing a collision actually leaves behind: two rows that are identical in
    every field the uid is made of.
    """
    rows = [
        f"{german} x{count}"
        for german, count in db.execute(
            "SELECT german, COUNT(*) AS n FROM words "
            "GROUP BY level_code, german, pos, english HAVING n > 1 "
            "ORDER BY n DESC, german"
        )
    ]
    if not rows:
        return []
    return [
        Failure(
            "uids",
            f"{len(rows)} entries are duplicated in level, German, part of "
            f"speech and English: {_sample(rows)}. Each got a distinct uid, "
            f"so the learner will meet the same word twice. Delete the "
            f"duplicate row or make the entries differ.",
        )
    ]


def check_fts_is_populated(db: sqlite3.Connection) -> list[Failure]:
    """Gate 5: an empty FTS table.

    Counted against the table it mirrors, not against zero: a words_fts with
    one row is as broken as an empty one and would pass a non-zero check.
    """
    expected = {
        "words_fts": "words",
        "words_trigram": "words",
        "examples_fts": "word_examples",
    }

    failures = []
    for table, source in expected.items():
        try:
            indexed = db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        except sqlite3.OperationalError as error:
            failures.append(
                Failure("search", f"{table} is missing ({error}).")
            )
            continue

        rows = db.execute(f"SELECT COUNT(*) FROM {source}").fetchone()[0]
        if indexed != rows:
            failures.append(
                Failure(
                    "search",
                    f"{table} has {indexed} rows for {rows} in {source}. "
                    f"That search tier will miss words. Rebuild with "
                    f"`make content`.",
                )
            )
    return failures


def check_the_database_is_readable(db: sqlite3.Connection) -> list[Failure]:
    """Not one of the five, but the one that makes the others meaningful.

    A truncated copy passes every count check on the tables it still has.
    """
    result = db.execute("PRAGMA integrity_check").fetchone()[0]
    if result != "ok":
        return [Failure("file", f"sqlite integrity_check says: {result}")]

    for table in FTS_TABLES:
        try:
            db.execute(f"INSERT INTO {table}({table}) VALUES ('integrity-check')")
        except sqlite3.OperationalError as error:
            # A missing table and a damaged one send the author in different
            # directions, and "no such table" is an OperationalError.
            return [
                Failure(
                    "search",
                    f"{table} is missing ({error}). Rebuild with "
                    f"`make content`.",
                )
            ]
        except sqlite3.DatabaseError as error:
            return [Failure("search", f"{table} is corrupt: {error}")]
    return []


def check_tips_fit_their_word_class(
    db: sqlite3.Connection, tips: Path = DEFAULT_TIPS
) -> list[Failure]:
    """#321: a tip tagged as a rule about one word class ("gender" for
    nouns, "separable" for verbs) on a word of another. content.db has no
    tags, so they come from the CSV the build read."""
    failures = []
    for tip in read_tips(tips if tips.exists() else None):
        pos = tip_pos(tip.tags)
        if pos is None:
            continue
        rows = [
            f"{german} ({word_pos})"
            for german, word_pos in db.execute(
                "SELECT w.german, w.pos FROM interference_tips t "
                "JOIN words w ON w.uid = t.word_uid "
                "WHERE t.tip_en = ? AND coalesce(w.pos, '') <> ? "
                "ORDER BY w.seq",
                (tip.tip_en, pos),
            )
        ]
        if rows:
            failures.append(
                Failure(
                    "tips",
                    f"interference_tips.csv line {tip.row} is a rule about "
                    f"the {pos}s, but it is on {len(rows)} other words: "
                    f"{_sample(rows)}. Rebuild with `make content`; if it "
                    f"persists, the build's word-class filter is broken.",
                )
            )
    return failures


GATES = (
    check_the_database_is_readable,
    check_every_step_has_words,
    check_every_word_has_an_example,
    check_no_uid_collision,
    check_fts_is_populated,
    check_tips_fit_their_word_class,
)


def verify(path: Path) -> list[Failure]:
    """Runs every gate. Returns the failures rather than raising, so one run
    reports all of them — an author should not have to build five times."""
    if not path.exists():
        return [
            Failure(
                "file",
                f"no database at {path}. Run `make content` first, or pass "
                f"--db.",
            )
        ]

    # Read-write, and nothing is committed. FTS5's `integrity-check` is issued
    # as an INSERT, so a read-only handle refuses it — and that check is the
    # one that would catch an index the app cannot search. The read-only rule
    # is about the app, not about the tool that made the file.
    db = sqlite3.connect(path, isolation_level="DEFERRED")
    try:
        failures = [failure for gate in GATES for failure in gate(db)]
        db.rollback()
        return failures
    finally:
        db.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args(argv)

    failures = verify(args.db)
    for failure in failures:
        print(f"content verify: {failure}", file=sys.stderr)

    if failures:
        print(
            f"content verify: {len(failures)} gate(s) failed; "
            f"{args.db.name} is not shippable",
            file=sys.stderr,
        )
        return 1

    print(f"content verify: {args.db.name} passed every gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
