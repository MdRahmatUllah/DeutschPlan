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

from pipeline_steps import (  # noqa: E402
    LEADING_ARTICLE,
    SUBLEVELS,
    PipelineError,
    read_tips,
    tip_pos,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "content" / "build" / "content.db"

#: Terms that must never ship (#628): personal details that once sat in
#: example sentences. Outside git (`data/` is ignored) and outside the
#: database, so the list does not publish what it guards against.
DEFAULT_DENYLIST = REPO_ROOT / "data" / "denylist.txt"


def _manifest_tips() -> Path | None:
    """The tips CSV the build reads: `tips:` in content/manifest.yaml."""
    import yaml

    manifest = REPO_ROOT / "content" / "manifest.yaml"
    raw = yaml.safe_load(manifest.read_text(encoding="utf-8")) if manifest.exists() else None
    tips = (raw or {}).get("tips")
    return REPO_ROOT / tips if tips else None


DEFAULT_TIPS = _manifest_tips()

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
    db: sqlite3.Connection, tips: Path | None = DEFAULT_TIPS
) -> list[Failure]:
    """#321: a tip tagged as a rule about one word class ("gender" for
    nouns, "separable" for verbs) on a word of another. content.db has no
    tags, so they come from the CSV the build read."""
    failures = []
    try:
        authored = read_tips(tips if tips is not None and tips.exists() else None)
    except PipelineError as error:
        return [Failure("tips", str(error))]
    for tip in authored:
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


def check_every_category_has_words(db: sqlite3.Connection) -> list[Failure]:
    """#636: a category no word is in. It is a tab the words' Category cells
    do not name (the tab name cut at 31 characters, say), so its twin from
    the cells has no description and the tab's is lost."""
    rows = [
        name
        for (name,) in db.execute(
            "SELECT name FROM categories c WHERE NOT EXISTS "
            "(SELECT 1 FROM words w WHERE w.category_id = c.id) ORDER BY id"
        )
    ]
    if not rows:
        return []
    return [
        Failure(
            "categories",
            f"{len(rows)} categories have no words: {_sample(rows)}. The "
            f"tab's title cell ('Category: <name>') must spell the name the "
            f"Category column uses.",
        )
    ]


def check_no_article_in_german(db: sqlite3.Connection) -> list[Failure]:
    """#287: a noun whose article is still inside `german`, so the headword
    has no gender colour and the Articles quiz never asks it."""
    import re

    pattern = re.compile(LEADING_ARTICLE)
    # No exemption for duplicates: the build drops those (#407).
    rows = [
        german
        for (german,) in db.execute(
            "SELECT german FROM words "
            "WHERE pos = 'noun' AND article IS NULL ORDER BY seq"
        )
        if pattern.match(german.strip())
    ]
    if not rows:
        return []
    return [
        Failure(
            "articles",
            f"{len(rows)} nouns keep their article in the German cell: "
            f"{_sample(rows)}. Rebuild with `make content`; the build moves it "
            f"into the Article column.",
        )
    ]


#: A word-formation note ("beantworten — Präfix be-"): the one shape of
#: "X — Y" a headword may take (#629).
WORD_FORMATION = r" — (Präfix|Wortbildung|Negation) "


def check_no_pair_headword(db: sqlite3.Connection) -> list[Failure]:
    """#629: "X — Y" in `german`. Every other column of such a row was about
    Y, so the card paired Y's meaning with X, TTS read both, and the
    Articles and Forms quizzes asked X with Y's article and plural."""
    import re

    rows = [
        german
        for (german,) in db.execute(
            "SELECT german FROM words WHERE german LIKE '% — %' ORDER BY seq"
        )
        if not re.search(WORD_FORMATION, german)
    ]
    if not rows:
        return []
    return [
        Failure(
            "headwords",
            f"{len(rows)} headwords are two words, 'X — Y': {_sample(rows)}. "
            f"Make the German cell the word the row teaches, and put a real "
            f"contrast in Synonyms / register.",
        )
    ]


#: What `parseForms` reads a two-part verb or phrase cell as: the 3rd person,
#: then the Perfekt with its auxiliary. Nothing in brackets (#632).
VERB_FORMS = r"[^·()]+ · (hat|ist) [^()]+"


def check_verb_forms(db: sqlite3.Connection) -> list[Failure]:
    """#632: a two-part verb or phrase `forms` cell that is not
    "3rd person · Perfekt". The Forms quiz and the exams expect part two
    verbatim, so "hat gedurft (durfte)" marked "hat gedurft" wrong."""
    import re

    rows = [
        f"{german} ({forms})"
        for german, forms in db.execute(
            "SELECT german, forms FROM words "
            "WHERE pos IN ('verb', 'phrase') AND forms IS NOT NULL ORDER BY seq"
        )
        if len([part for part in forms.split("·") if part.strip()]) == 2
        and not re.fullmatch(VERB_FORMS, forms.strip())
    ]
    if not rows:
        return []
    return [
        Failure(
            "forms",
            f"{len(rows)} verb forms cells are not '3rd person · hat/ist "
            f"Perfekt': {_sample(rows)}. One auxiliary, and no brackets: put "
            f"a Präteritum or a second sense in Synonyms / register.",
        )
    ]


#: Nouns that take no article: the holidays (#633).
NO_ARTICLE = frozenset({"Silvester", "Weihnachten", "Neujahr", "Ostern"})

#: What makes a noun row a set of words rather than one ("Grund / Ursache",
#: "Mitleid ↔ Sympathie", "Geld vs. Kohle"): no one article fits it.
WORD_SET = r"/|↔| vs\. "


def check_articles(db: sqlite3.Connection) -> list[Failure]:
    """#633: a noun without an article, which gets no gender colour and no
    Articles practice; and a phrase with one, which the Articles quiz asks
    ("___ Fehler machen"). A note is never practised (#630): "Suffix -ismus"
    has no article to give."""
    import re

    bare = [
        german
        for (german,) in db.execute(
            "SELECT german FROM words WHERE pos = 'noun' AND article IS NULL "
            "AND kind = 'vocab' ORDER BY seq"
        )
        if german not in NO_ARTICLE and not re.search(WORD_SET, german)
    ]
    phrases = [
        f"{article} {german}"
        for article, german in db.execute(
            "SELECT article, german FROM words "
            "WHERE pos = 'phrase' AND article IS NOT NULL ORDER BY seq"
        )
    ]
    failures = []
    if bare:
        failures.append(
            Failure(
                "articles",
                f"{len(bare)} nouns have no article: {_sample(bare)}. Fill in "
                f"the Article column (a noun that takes none goes in "
                f"NO_ARTICLE in {Path(__file__).name}).",
            )
        )
    if phrases:
        failures.append(
            Failure(
                "articles",
                f"{len(phrases)} phrases carry an article, which the Articles "
                f"quiz would ask: {_sample(phrases)}. Clear it, or make a noun "
                f"phrase a noun.",
            )
        )
    return failures


def check_every_word_can_be_gapped(db: sqlite3.Connection) -> list[Failure]:
    """#631: a word to learn whose examples the cloze cannot gap gets no cloze
    card, no practice sentence and no exam gap fill. `tools/cloze.py` is the
    app's `clozeGap`; a note's examples show its lesson (#630). A word with
    no example at all is `check_every_word_has_an_example`'s."""
    from cloze import cloze_gap

    examples: dict[str, list[str]] = {}
    for uid, german in db.execute("SELECT word_uid, german FROM word_examples"):
        examples.setdefault(uid, []).append(german)
    rows = [
        f"{german} ({uid})"
        for uid, german, pos in db.execute(
            "SELECT uid, german, pos FROM words WHERE kind = 'vocab' ORDER BY seq"
        )
        if examples.get(uid)
        and all(cloze_gap(sentence, german, pos) is None for sentence in examples[uid])
    ]
    if not rows:
        return []
    return [
        Failure(
            "examples",
            f"{len(rows)} words have no example the cloze can gap, so no "
            f"cloze card, practice sentence or gap fill ever shows them: "
            f"{_sample(rows)}. Add or rewrite an example that says the word "
            f"(an infinitive or a participle for a strong verb) in "
            f"content/corrections.yaml.",
        )
    ]


def check_no_starred_example(db: sqlite3.Connection) -> list[Failure]:
    """#630: an example marked ungrammatical ("nicht: *Ich bin arbeitend"),
    which TTS reads out as a model sentence."""
    rows = [
        f"{german} ({uid})"
        for uid, german in db.execute(
            "SELECT word_uid, german FROM word_examples "
            "WHERE german LIKE '% *%' OR german LIKE '*%' ORDER BY word_uid, ord"
        )
    ]
    if not rows:
        return []
    return [
        Failure(
            "examples",
            f"{len(rows)} example sentences carry a starred, ungrammatical "
            f"one, which is read aloud as a model: {_sample(rows)}. Keep the "
            f"right sentence; the contrast belongs in Synonyms / register.",
        )
    ]


def read_denylist(path: Path | None) -> list[tuple[int, str]]:
    """One term per line; `#` starts a comment. Case-folded, with the line
    number a failure names it by."""
    if path is None or not path.exists():
        return []
    return [
        (number, line.strip().casefold())
        for number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        )
        if line.strip() and not line.lstrip().startswith("#")
    ]


def check_no_denylisted_terms(
    db: sqlite3.Connection, denylist: Path | None = None
) -> list[Failure]:
    """#628: a denylisted term anywhere in the course's text.

    Every TEXT column of every table; the search index's columns are untyped
    copies. The failure names the term by its line in the denylist, not by
    the term: a build log is not where it should appear either.
    """
    denylist = denylist or DEFAULT_DENYLIST
    terms = read_denylist(denylist)
    if not terms:
        if not denylist.exists():
            print(
                f"content verify: no denylist at {denylist}; the personal "
                f"data gate did not run",
                file=sys.stderr,
            )
        return []

    hits: dict[int, list[str]] = {}
    tables = [
        name
        for (name,) in db.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
    ]
    for table in tables:
        columns = [
            column[1]
            for column in db.execute(f'PRAGMA table_info("{table}")')
            if column[2].upper() == "TEXT"
        ]
        if not columns:
            continue
        # The word's uid where there is one: it is what corrections.yaml is
        # keyed by.
        key = next((c for c in ("word_uid", "uid") if c in columns), "rowid")
        rows = db.execute(
            f"SELECT {key}, {', '.join(columns)} FROM \"{table}\""
        ).fetchall()
        for where, *values in rows:
            text = " ".join(value for value in values if value).casefold()
            for number, term in terms:
                if term in text:
                    hits.setdefault(number, []).append(f"{table} {where}")
    return [
        Failure(
            "denylist",
            f"the denylisted term on line {number} is in {len(where)} rows: "
            f"{_sample(where)}. Replace it through content/corrections.yaml.",
        )
        for number, where in sorted(hits.items())
    ]


GATES = (
    check_the_database_is_readable,
    check_every_step_has_words,
    check_every_word_has_an_example,
    check_no_uid_collision,
    check_fts_is_populated,
    check_tips_fit_their_word_class,
    check_no_article_in_german,
    check_no_pair_headword,
    check_verb_forms,
    check_articles,
    check_every_word_can_be_gapped,
    check_no_starred_example,
    check_every_category_has_words,
    check_no_denylisted_terms,
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
