"""Writes workbooks with the shape `content-pipeline.md` describes.

The four real trackers are not in the repository. Without something to read,
the pipeline could only be tested against its own mocks, which would prove
nothing about openpyxl, about headers read by name, or about the sheet layout.

So this generates structurally faithful stand-ins: the same sheets, the same
headers, the same quirks the doc calls out — a title row above the header, a
level cell reading "B1 (Phase 2)", a cell starting with `=`, examples as
newline-separated lines with one DE line more than EN. The content is
invented; the shape is not.

They are **fixtures, not content**. `make content` reads the real workbooks
from the repository root; these are written into a temporary directory by the
tests, and by `python tools/fixtures/make_workbooks.py <dir>` when you want to
look at one.
"""

from __future__ import annotations

import sys
from pathlib import Path

from openpyxl import Workbook

# Level, and how many weeks of it each workbook carries. The real split is
# A1+A2+B1 in the first book and one level in each of the others.
BOOK_LEVELS: dict[str, list[str]] = {
    "German_B1_Tracker.xlsx": ["A1", "A2", "B1"],
    "German_B2_Tracker.xlsx": ["B2"],
    "German_C1_Tracker.xlsx": ["C1"],
    "German_C2_Tracker.xlsx": ["C2"],
}

WORD_HEADERS = [
    "Article",
    "German",
    "Plural / Forms",
    "POS",
    "Pronunciation (Bangla)",
    "English",
    "Bangla meaning",
    "Freq",
    "Level",
    "Category",
    "Week",
    "Examples (DE)",
    "Examples (EN)",
    "Collocations",
    "Synonyms / register",
]

GRAMMAR_HEADERS = [
    "Week",
    "Level",
    "Topic",
    "Rule",
    "Example (DE)",
    "Example (EN)",
    "Watch out",
]

CATEGORIES = ["Alltag", "Reisen", "Arbeit"]

# Enough nouns to give every week a handful of words, with the articles spread
# so gender colouring has something to show.
NOUNS = [
    ("der", "Tisch", "Tische", "table", "টেবিল"),
    ("die", "Lampe", "Lampen", "lamp", "বাতি"),
    ("das", "Fenster", "Fenster", "window", "জানালা"),
    ("der", "Stuhl", "Stühle", "chair", "চেয়ার"),
    ("die", "Tür", "Türen", "door", "দরজা"),
    ("das", "Buch", "Bücher", "book", "বই"),
    ("der", "Schlüssel", "Schlüssel", "key", "চাবি"),
    ("die", "Straße", "Straßen", "street", "রাস্তা"),
]

VERBS = [
    ("bekommen", "to receive"),
    ("verstehen", "to understand"),
    ("mitbringen", "to bring along"),
    ("überlegen", "to consider"),
]

# PIPE-05: cells an author would type that Excel treats as a formula. They are
# written as explicit string cells, which is what Excel stores once the author
# has escaped them — and what the pipeline has to keep as text.
FORMULA_PREFIXED = {
    0: "=SUM(A1:A2)",
    1: "+49 170 1234567",
    2: "-5 Grad",
    3: "@Kollege",
}

WEEKS_PER_LEVEL = 6
WORDS_PER_WEEK = 5


def _word_rows(level: str, weeks: int) -> list[list[object]]:
    rows: list[list[object]] = []
    for week in range(1, weeks + 1):
        for slot in range(WORDS_PER_WEEK):
            index = (week - 1) * WORDS_PER_WEEK + slot
            category = CATEGORIES[index % len(CATEGORIES)]

            if slot < len(NOUNS) and slot % 2 == 0:
                article, german, forms, english, bangla = NOUNS[
                    (index // 2) % len(NOUNS)
                ]
                german = f"{german}{_suffix(level, week, slot)}"
                pos = "noun"
            else:
                base, english = VERBS[index % len(VERBS)]
                article, forms, bangla = None, None, "বোঝা"
                german = f"{base}{_suffix(level, week, slot)}"
                pos = "verb"

            # PIPE-06: one more DE line than EN, so the unmatched line has to
            # come out with a null translation rather than shifting the pairs.
            examples_de = f"Das ist {german}.\nIch sehe {german} dort."
            examples_en = f"This is {english}."

            # PIPE-05: the four prefixes Excel reads as a formula. Spread over
            # the first week so every workbook carries all of them.
            collocations = FORMULA_PREFIXED.get(slot) if week == 1 else "mit + dative"

            # PIPE-01: the level cell sometimes carries the phase label too.
            level_cell = f"{level} (Phase {1 + (week - 1) // 3})"

            rows.append(
                [
                    article,
                    german,
                    forms,
                    pos,
                    f"{german.lower()}-pron",
                    english,
                    bangla,
                    (index % 5) + 1,
                    level_cell,
                    category,
                    week,
                    examples_de,
                    examples_en,
                    collocations,
                    "formal" if slot == 0 else None,
                ]
            )
    return rows


def _suffix(level: str, week: int, slot: int) -> str:
    """Keeps every German headword distinct across levels and weeks.

    Real content has no such suffix; here it is what stops PIPE-03 from seeing
    a genuine collision on every repeat of the small word list, which would
    hide a real collision bug behind hundreds of expected ones.
    """
    return f"{level.lower()}{week:02d}{slot}"


def _grammar_rows(level: str, weeks: int) -> list[list[object]]:
    return [
        [
            week,
            level,
            f"{level} topic {week}",
            f"Rule for {level} week {week}.",
            f"Beispiel {level} {week}.",
            f"Example {level} {week}.",
            "Watch the word order." if week % 2 else None,
        ]
        for week in range(1, weeks + 1)
    ]


def write_workbook(path: Path, levels: list[str]) -> None:
    book = Workbook()
    book.remove(book.active)

    words = book.create_sheet("All Words")
    # A title row above the header, which the real workbooks carry and which is
    # why the reader searches for the header rather than assuming row 1.
    words.append([f"Vocabulary tracker — {', '.join(levels)}"])
    words.append(WORD_HEADERS)
    for level in levels:
        for row in _word_rows(level, WEEKS_PER_LEVEL):
            words.append(row)
    _force_text(words, WORD_HEADERS.index("Collocations") + 1)

    grammar = book.create_sheet("Grammar")
    grammar.append(GRAMMAR_HEADERS)
    for level in levels:
        for row in _grammar_rows(level, WEEKS_PER_LEVEL):
            grammar.append(row)

    skills = book.create_sheet("W01")
    skills.append(["Weekly skills checklist"])
    for prompt in (
        "Introduce yourself in three sentences.",
        "Order a coffee and ask for the bill.",
        "Describe your room.",
    ):
        skills.append([prompt])

    for name in CATEGORIES:
        tab = book.create_sheet(f"C-{name}")
        tab.append([f"Words about {name.lower()}."])

    path.parent.mkdir(parents=True, exist_ok=True)
    book.save(path)


def _force_text(sheet, column: int) -> None:
    """Keeps a leading `=` a string rather than a formula.

    openpyxl types a cell by looking at the value, so "=SUM(A1:A2)" becomes a
    formula and reads back as None under `data_only=True`. Setting the type
    explicitly is how Excel stores a value the author escaped, and it is the
    case PIPE-05 exists for.
    """
    for row in sheet.iter_rows(min_col=column, max_col=column):
        for cell in row:
            if isinstance(cell.value, str):
                cell.data_type = "s"


def write_all(directory: Path) -> list[Path]:
    """Writes all four fixture workbooks into `directory`."""
    return [
        _written(directory / name, levels) for name, levels in BOOK_LEVELS.items()
    ]


def _written(path: Path, levels: list[str]) -> Path:
    write_workbook(path, levels)
    return path


def main(argv: list[str]) -> int:
    target = Path(argv[1]) if len(argv) > 1 else Path.cwd() / "fixture-workbooks"
    for path in write_all(target):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
