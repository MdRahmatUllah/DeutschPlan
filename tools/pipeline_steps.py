"""The derivations between reading a workbook and writing content.db.

Pure functions over the records `excel_to_sqlite.py` reads, so each PIPE rule
can be tested on its own, without a workbook and without a database.
"""

from __future__ import annotations

import hashlib
import unicodedata
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


# PIPE-04: the two search keys.
#
# `text_norm.dart` must produce byte-identical output, which is what
# `tools/test_vectors.json` exists to hold both sides to. Search is the screen
# where a mismatch is invisible: the word is in the database, the query looks
# right, and nothing comes back.

#: Stripped from the front of a German headword before keying. Nouns are
#: authored with their article in a separate column, but the German column
#: carries one often enough — and a learner typing "Haus" must find "das Haus".
GERMAN_ARTICLES = ("der", "die", "das", "den", "dem", "des")

#: umlaut -> the spelling a German keyboard-less learner types. This is the
#: German convention, not a diacritic strip: ä is "ae", never "a".
UMLAUT_EXPANSIONS = {
    "ä": "ae",
    "ö": "oe",
    "ü": "ue",
    "ß": "ss",
}

#: The same letters folded instead of expanded, for `search_key_alt`. Someone
#: who types "Tur" for "Tür" is served by this one.
UMLAUT_FOLDS = {
    "ä": "a",
    "ö": "o",
    "ü": "u",
    "ß": "ss",
}


def _strip_article(text: str) -> str:
    """Drops a leading German article, and only a leading one.

    "die Bank" keys as "bank"; "Diebstahl" keeps its "die", because the check
    is on a whole word.
    """
    parts = text.split(None, 1)
    if len(parts) == 2 and parts[0] in GERMAN_ARTICLES:
        return parts[1]
    return text


def _strip_latin_marks(text: str) -> str:
    """Removes combining marks from Latin letters, and leaves other scripts.

    A naive NFD-and-drop-every-mark would mangle Bangla: its vowel signs are
    combining characters too, and `search.md` matches `bangla = raw`, so a
    Bangla meaning has to come back byte-for-byte.
    """
    result: list[str] = []
    base_is_latin = False
    for char in unicodedata.normalize("NFD", text):
        if unicodedata.combining(char):
            if not base_is_latin:
                result.append(char)
            continue
        base_is_latin = "LATIN" in unicodedata.name(char, "")
        result.append(char)
    return unicodedata.normalize("NFC", "".join(result))


#: Punctuation dropped before keying, as an explicit list rather than a
#: Unicode category test.
#:
#: The categories `Pc Pd Pe Pf Pi Po Ps` cover Devanagari danda, Arabic comma
#: and a hundred other marks, and `text_norm.dart` has no category lookup to
#: match them with. Worse, one of them matters: `search.md` matches
#: `bangla = raw`, so Bangla has to come back byte for byte, and a danda in a
#: Bangla meaning must survive.
#:
#: So this is the punctuation that actually appears in German and English text,
#: and `text_norm.dart` carries the same characters as a regex class. Anything
#: outside it passes through on both sides, which is the safe direction.
PUNCTUATION = frozenset(
    r"""!"#%&'()*,-./:;?@[\]_{}"""
    "¡§«¶·»¿"
) | frozenset(chr(c) for c in range(0x2010, 0x2028)) | frozenset(
    chr(c) for c in range(0x2030, 0x205F)
)


def _drop_punctuation(text: str) -> str:
    return "".join(" " if char in PUNCTUATION else char for char in text)


def _normalise(text: str, table: dict[str, str]) -> str:
    """Lower-case, article stripped, umlauts mapped, diacritics removed.

    The umlaut mapping runs before the diacritic strip, or NFD would take ä
    apart into a + combining diaeresis and it would key as "a" rather than
    reaching "ae".
    """
    # Composed first, or "u" + combining diaeresis never matches the ü in the
    # table and keys as "tur" instead of "tuer". Decomposed text is not
    # exotic — macOS pastes it — and on Search a wrong key is no results.
    lowered = unicodedata.normalize("NFC", text.strip().lower())
    mapped = "".join(table.get(char, char) for char in lowered)
    stripped = _strip_latin_marks(_drop_punctuation(mapped))

    # After the article check, because "der" only counts as an article when it
    # is a whole word, and collapsing whitespace first is what makes that test
    # reliable on "der   Tisch".
    collapsed = " ".join(stripped.split())
    return _strip_article(collapsed)


def search_key(text: str) -> str:
    """PIPE-04's first key: umlauts expanded the German way.

    "Tür" keys as "tuer", which is what someone without a German keyboard
    types.
    """
    return _normalise(text, UMLAUT_EXPANSIONS)


def search_key_alt(text: str) -> str:
    """PIPE-04's second key: umlauts folded to the bare vowel.

    "Tür" keys as "tur", for the learner who types the letter they see.
    """
    return _normalise(text, UMLAUT_FOLDS)


def assign_search_keys(words: Sequence) -> None:
    """Sets both keys on every word.

    Keyed on the German cell alone. The article column is deliberately not
    prepended: `_strip_article` drops one leading article, so a cell already
    reading "das Haus" plus an article column would key as "das haus" and a
    learner typing "haus" would find nothing. And prepending buys nothing
    otherwise — "Haus" keys as "haus" either way.
    """
    for word in words:
        word.search_key = search_key(word.german)
        word.search_key_alt = search_key_alt(word.german)


# PIPE-05 and PIPE-06: examples, and the cells Excel would have eaten.

#: The four characters Excel reads as the start of a formula. A cell beginning
#: with one is stored as text; the tool warns, because the author probably did
#: not mean the cell to start that way and the next person to open the workbook
#: may find Excel has changed it.
FORMULA_PREFIXES = ("=", "+", "-", "@")

#: Every field that carries free text an author types. Checked for the prefixes
#: above. `german` and `english` are in the list too: a word really can start
#: with a hyphen ("-los" as a suffix entry), and the warning is the point.
TEXT_FIELDS = (
    "german",
    "english",
    "bangla",
    "forms",
    "pron_bn",
    "collocations",
    "synonyms_register",
    "examples_de",
    "examples_en",
)


@dataclass(frozen=True)
class Example:
    """One example sentence, with its translation if there is one."""

    ord: int
    german: str
    english: str | None


def pair_examples(german_lines: str | None, english_lines: str | None) -> list[Example]:
    """PIPE-06: DE[i] pairs with EN[i]; an unmatched DE line gets no translation.

    Positional, not matched by content, because that is the only thing the two
    cells agree on. Blank lines are dropped from each side *before* pairing —
    an author's stray newline at the end of the German cell would otherwise
    shift every translation by one, which is the failure this ordering avoids.

    Surplus English lines are dropped: a translation with no sentence to
    attach to has nowhere to go.
    """
    german = _lines(german_lines)
    english = _lines(english_lines)

    return [
        Example(
            ord=index + 1,
            german=line,
            english=english[index] if index < len(english) else None,
        )
        for index, line in enumerate(german)
    ]


def _lines(cell: str | None) -> list[str]:
    if not cell:
        return []
    return [line.strip() for line in cell.splitlines() if line.strip()]


#: The same check for grammar rows. An author types a dash into "-en endings"
#: and an equals into "= gleich" as readily as into a word's collocations.
GRAMMAR_TEXT_FIELDS = ("topic", "rule", "example_de", "example_en", "watch_out")


def check_formula_prefixes(
    rows: Sequence, fields: tuple[str, ...] = TEXT_FIELDS
) -> list[str]:
    """PIPE-05: warns about cells Excel would treat as a formula.

    Nothing is changed — the value is already text by the time it reaches
    here, which is the requirement. The warning exists because the *workbook*
    is at risk: open it, retype the cell, and Excel turns it into a formula
    whose cached value is what the next build reads.
    """
    warnings: list[str] = []
    for row in rows:
        for field in fields:
            value = getattr(row, field, None)
            if not isinstance(value, str):
                continue
            # Line by line: examples_de and examples_en hold one sentence each,
            # and a dash on the second line is the same hazard as on the first.
            for line in value.splitlines():
                text = line.strip()
                if text.startswith(FORMULA_PREFIXES):
                    warnings.append(
                        f"formula-looking cell: {row.source_file} row "
                        f"{row.row} {field} starts with {text[0]!r} "
                        f"({text[:30]!r}). Stored as text; prefix it with an "
                        f"apostrophe in Excel so it stays that way."
                    )
    return warnings


def assign_examples(words: Sequence) -> None:
    """Sets `examples` on every word."""
    for word in words:
        word.examples = pair_examples(word.examples_de, word.examples_en)


# Interference tips: the L1 traps a Bangla speaker walks into.
#
# `content/interference_tips.csv` is authored by hand, with three ways to say
# which words a tip belongs to. All three are resolved here, at build time, so
# the app never runs a regex over five thousand words to draw one card.

#: The match types the CSV's first column may hold.
#:
#: - `uid`     — one exact word, by its uid. Survives a rename of the German.
#: - `german`  — every word whose German cell matches exactly, case-folded.
#: - `pattern` — a regex over the German, for families like `^seit\b`.
MATCH_TYPES = ("uid", "german", "pattern")


@dataclass(frozen=True)
class Tip:
    """One row of the CSV, before it is attached to any word."""

    match_type: str
    match: str
    tip_en: str
    tip_bn: str | None
    #: Authoring metadata only. content.db has no tags column: these group
    #: the tips for whoever maintains the file, and are not shipped.
    tags: str | None
    row: int


@dataclass(frozen=True)
class ResolvedTip:
    word_uid: str
    tip_en: str
    tip_bn: str | None


def read_tips(path) -> list[Tip]:
    """Reads the CSV. A malformed row fails the build, naming the line."""
    import csv

    if path is None:
        return []
    if not path.exists():
        raise PipelineError(
            f"{path} is missing. It is named by `tips:` in "
            f"content/manifest.yaml; add the file or remove the key."
        )

    tips: list[Tip] = []
    with path.open(encoding="utf-8", newline="") as handle:
        for number, row in enumerate(csv.DictReader(handle), start=2):
            missing = [
                column
                for column in ("match_type", "match", "tip_en")
                if not (row.get(column) or "").strip()
            ]
            if missing:
                raise PipelineError(
                    f"{path.name} line {number}: missing "
                    f"{', '.join(missing)}. Every tip needs a match type, "
                    f"something to match, and English text."
                )

            match_type = row["match_type"].strip()
            if match_type not in MATCH_TYPES:
                raise PipelineError(
                    f"{path.name} line {number}: match_type {match_type!r} is "
                    f"not one of {', '.join(MATCH_TYPES)}."
                )

            tips.append(
                Tip(
                    match_type=match_type,
                    match=row["match"].strip(),
                    tip_en=row["tip_en"].strip(),
                    tip_bn=(row.get("tip_bn") or "").strip() or None,
                    tags=(row.get("tags") or "").strip() or None,
                    row=number,
                )
            )
    return tips


def resolve_tips(tips: Sequence, words: Sequence) -> tuple[list[ResolvedTip], list[str]]:
    """Attaches every tip to the words it matches.

    Returns the rows to write and the warnings. A tip that matches nothing is
    **always** reported: it is hand-authored prose about a word that is no
    longer in the course, or a regex with a typo, and either way the author
    wrote it expecting it to appear.
    """
    import re

    by_uid = {word.uid: word for word in words}
    by_german: dict[str, list] = {}
    for word in words:
        by_german.setdefault(word.german.strip().lower(), []).append(word)

    resolved: list[ResolvedTip] = []
    warnings: list[str] = []
    seen: set[tuple[str, str]] = set()

    for tip in tips:
        matched = _matches(tip, by_uid, by_german, words, re)

        if not matched:
            warnings.append(
                f"unmatched tip: interference_tips.csv line {tip.row} "
                f"({tip.match_type} {tip.match!r}) matches no word. The tip "
                f"will not appear anywhere."
            )
            continue

        for word in matched:
            # (word_uid, tip_en) is the primary key: two CSV rows that say the
            # same thing about the same word are one tip, not a constraint
            # failure at write time.
            key = (word.uid, tip.tip_en)
            if key in seen:
                continue
            seen.add(key)
            resolved.append(
                ResolvedTip(word_uid=word.uid, tip_en=tip.tip_en, tip_bn=tip.tip_bn)
            )

    return resolved, warnings


def _matches(tip, by_uid, by_german, words, re) -> list:
    if tip.match_type == "uid":
        word = by_uid.get(tip.match)
        return [word] if word else []

    if tip.match_type == "german":
        return by_german.get(tip.match.strip().lower(), [])

    try:
        pattern = re.compile(tip.match, re.IGNORECASE)
    except re.error as error:
        raise PipelineError(
            f"interference_tips.csv line {tip.row}: {tip.match!r} is not a "
            f"valid regex ({error})."
        ) from error
    return [word for word in words if pattern.search(word.german)]


# Grammar tags: which practice item types a topic can produce.
#
# `grammar-practice.md`: "Topics tagged in the pipeline (`grammar_topics.tags`,
# comma list, derived from topic title keywords) decide which item types
# apply. Every topic yields at least Gap fill + Pick the form."
#
# Derived here rather than authored, because the workbooks have no tag column
# and asking authors to keep one would put a second source of truth beside the
# topic title they already write.

#: Tag -> the keywords in a topic title that imply it. Matched case-folded
#: against the title, as whole words where the keyword is a word.
#:
#: German and English both, because the Topic column is authored in either
#: depending on the workbook — "Nebensatz: weil, dass" and "Subordinate
#: clauses" are the same topic.
TAG_KEYWORDS: dict[str, tuple[str, ...]] = {
    # The three `grammar-practice.md` names for Order the sentence.
    "word-order": (
        "wortstellung",
        "satzstellung",
        "word order",
        "wortfolge",
        "inversion",
    ),
    "nebensatz": (
        "nebensatz",
        "nebensätze",
        "subordinate",
        "subjunction",
        "konjunktion",
        "weil",
        "dass",
        "obwohl",
        "wenn",
    ),
    "v2": ("verbzweit", "verb second", "v2", "hauptsatz", "position 2"),
    # The rest steer distractors and Rule recall.
    "case": ("kasus", "case", "dativ", "akkusativ", "genitiv", "nominativ"),
    "tense": (
        "tempus",
        "tense",
        "präsens",
        "präteritum",
        "perfekt",
        "plusquamperfekt",
        "futur",
    ),
    "verb-form": (
        "verb",
        "konjugation",
        "conjugation",
        "partizip",
        "participle",
        "imperativ",
        "modalverb",
        "trennbar",
        "separable",
    ),
    "gender": ("genus", "gender", "artikel", "article", "geschlecht"),
    "adjective": ("adjektiv", "adjective", "deklination", "komparativ", "superlativ"),
    "pronoun": ("pronomen", "pronoun", "reflexiv", "reflexive", "relativ"),
    "preposition": ("präposition", "preposition", "wechselpräposition"),
    # Not "nicht" or "kein": they are function words that appear in titles
    # about separable prefixes ("Nicht trennbare Verben") and article
    # choice, where the negation tag is wrong and steers the generator's
    # distractors with it.
    "negation": ("negation", "verneinung"),
    "passive": ("passiv", "passive", "vorgangspassiv", "zustandspassiv"),
    "subjunctive": ("konjunktiv", "subjunctive", "würde"),
}

#: A keyword always has to start a word. What it may do at the end depends on
#: how long it is:
#:
#: - short keywords must end a word too (allowing the German plural and weak
#:   endings), because "verb" would otherwise fire on "Verbindung" and
#:   "artikel" on "Partikel" — both tagging a topic with an item type it
#:   cannot produce.
#: - long ones may continue into a compound, because German writes
#:   "Verbzweitstellung" and "Wechselpräpositionen" as one word and those are
#:   exactly the topics being looked for.
#:
#: Eight characters is where the two stop overlapping: nothing shorter is a
#: distinctive compound head, and nothing longer turned up inside an unrelated
#: word.
COMPOUND_HEAD_LENGTH = 8

_PLURAL = r"(?:e|en|es|er|n|s)?"


def _mentions(title: str, keyword: str) -> bool:
    import re

    ending = "" if len(keyword) >= COMPOUND_HEAD_LENGTH else _PLURAL + r"\b"
    pattern = r"\b" + re.escape(keyword) + ending
    return re.search(pattern, title, re.IGNORECASE) is not None


#: Every topic gets these, whatever its title says. `grammar-practice.md`
#: guarantees Gap fill and Pick the form for every topic, and both are built
#: from the example and the rule alone — no tag needed.
BASE_TAGS = ("gap-fill", "pick-the-form")

#: The tags that unlock Order the sentence, per `grammar-practice.md`.
WORD_ORDER_TAGS = frozenset({"word-order", "nebensatz", "v2"})


def tags_for(topic: str) -> list[str]:
    """The tags a topic title implies, plus the two every topic gets.

    Deterministic and order-stable: the derived tags are sorted, so the same
    title always produces the same comma list and a rebuild of unchanged
    content produces an identical database.
    """
    title = (topic or "").casefold()
    found = {
        tag
        for tag, keywords in TAG_KEYWORDS.items()
        if any(_mentions(title, keyword) for keyword in keywords)
    }
    return list(BASE_TAGS) + sorted(found)


def assign_tags(rows: Sequence) -> dict[str, int]:
    """Sets `tags` on every grammar row. Returns the coverage, for the summary.

    The count that matters is how many topics can produce Order the sentence:
    without a word-order tag that item type never appears, and nobody would
    notice, because the other four still do.
    """
    coverage: dict[str, int] = {"topics": 0, "word-order": 0}

    for row in rows:
        tags = tags_for(row.topic)
        row.tags = ",".join(tags)
        coverage["topics"] += 1
        if WORD_ORDER_TAGS & set(tags):
            coverage["word-order"] += 1

    return coverage
