"""Compile the authoring workbooks into content.db.

Excel is the authoring tool; the app never opens a workbook.
`docs/02-data/content-pipeline.md` is the specification, and the PIPE-nn
references in this file point at the rule each piece implements.

Run it through `make content`, which also verifies the result and copies the
asset. Running this module directly does the compile step alone.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import yaml
from openpyxl import load_workbook

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "content" / "manifest.yaml"

# Columns are read by header name, so the authors may reorder them freely.
# Renaming a header in Excel means changing it here — that is the whole
# contract, and it is why a missing required header is a hard failure rather
# than a silent None.
#
# Several headers have drifted across the four workbooks, so each field lists
# every spelling seen. The first is the canonical one the doc names.
HEADER_MAP: dict[str, list[str]] = {
    "article": ["Article"],
    "german": ["German"],
    "forms": ["Plural / Forms", "Plural/Forms", "Plural", "Forms"],
    "pos": ["POS", "Part of speech"],
    "pron_bn": ["Pronunciation (Bangla)", "Pronunciation (BN)"],
    "english": ["English"],
    "bangla": ["Bangla meaning", "Bangla"],
    "freq": ["Freq", "Frequency"],
    "level": ["Level"],
    "category": ["Category"],
    "week": ["Week"],
    "examples_de": ["Examples (DE)", "Example (DE)"],
    "examples_en": ["Examples (EN)", "Example (EN)"],
    "collocations": ["Collocations"],
    "synonyms_register": ["Synonyms / register", "Synonyms/register"],
}

REQUIRED_WORD_FIELDS = ("german", "english", "level")

GRAMMAR_HEADER_MAP: dict[str, list[str]] = {
    "week": ["Week"],
    "level": ["Level"],
    "topic": ["Topic"],
    "rule": ["Rule"],
    "example_de": ["Example (DE)", "Examples (DE)"],
    "example_en": ["Example (EN)", "Examples (EN)"],
    "watch_out": ["Watch out", "Watch Out"],
}

REQUIRED_GRAMMAR_FIELDS = ("topic",)

WORDS_SHEET = "All Words"
GRAMMAR_SHEET = "Grammar"
SKILLS_SHEET = "W01"
CATEGORY_SHEET_PREFIX = "C-"

LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")


class PipelineError(Exception):
    """A failure the author can act on. Printed without a traceback."""


@dataclass
class Word:
    """One row of *All Words*, before any derivation."""

    source_file: str
    row: int
    article: str | None = None
    german: str = ""
    forms: str | None = None
    pos: str | None = None
    pron_bn: str | None = None
    english: str = ""
    bangla: str | None = None
    freq: int | None = None
    level: str = ""
    category: str | None = None
    week: int | None = None
    examples_de: str | None = None
    examples_en: str | None = None
    collocations: str | None = None
    synonyms_register: str | None = None


@dataclass
class GrammarRow:
    source_file: str
    row: int
    week: int | None = None
    level: str | None = None
    topic: str = ""
    rule: str | None = None
    example_de: str | None = None
    example_en: str | None = None
    watch_out: str | None = None


@dataclass
class Category:
    """A `C-…` tab. The tab name after the prefix is the category name."""

    name: str
    description: str | None = None


@dataclass
class SourceBook:
    """Everything read out of one workbook."""

    file: str
    words: list[Word] = field(default_factory=list)
    grammar: list[GrammarRow] = field(default_factory=list)
    skill_prompts: list[str] = field(default_factory=list)
    categories: list[Category] = field(default_factory=list)


@dataclass
class Manifest:
    workbooks: list[Path]
    tips: Path | None


def read_manifest(path: Path) -> Manifest:
    """Parses `content/manifest.yaml`.

    The order of `workbooks` is meaningful — it is the fallback level order for
    grammar without a level of its own — so it is kept as a list throughout.
    """
    if not path.exists():
        raise PipelineError(f"no manifest at {path}")

    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    entries = raw.get("workbooks")
    if not entries:
        raise PipelineError(f"{path} lists no workbooks")

    books: list[Path] = []
    for entry in entries:
        if not isinstance(entry, dict) or "file" not in entry:
            raise PipelineError(
                f"{path}: every workbook entry needs a 'file:' key, got {entry!r}"
            )
        books.append(_resolve(entry["file"]))

    tips = raw.get("tips")
    return Manifest(workbooks=books, tips=_resolve(tips) if tips else None)


def _resolve(value: str) -> Path:
    candidate = Path(value)
    return candidate if candidate.is_absolute() else REPO_ROOT / candidate


def _header_index(
    sheet, header_map: dict[str, list[str]], required: tuple[str, ...], where: str
) -> tuple[dict[str, int], int]:
    """Finds the header row and maps each field to its column index.

    The header is not assumed to be row 1: the workbooks carry a title row
    above it often enough that guessing would be a coin flip. The first row
    that carries every required header wins.
    """
    wanted = {
        name.strip().lower(): field
        for field, names in header_map.items()
        for name in names
    }

    for row_number, row in enumerate(sheet.iter_rows(min_row=1, max_row=10), start=1):
        found: dict[str, int] = {}
        for column, cell in enumerate(row, start=1):
            if not isinstance(cell.value, str):
                continue
            field_name = wanted.get(cell.value.strip().lower())
            # First spelling wins, so a workbook carrying both "Plural" and
            # "Forms" does not flip between them depending on column order.
            if field_name and field_name not in found:
                found[field_name] = column
        if all(name in found for name in required):
            return found, row_number

    missing = ", ".join(required)
    raise PipelineError(
        f"{where}: no header row in the first 10 rows carrying all of: {missing}. "
        f"Headers are read by name — if one was renamed, update HEADER_MAP in "
        f"{Path(__file__).name}."
    )


def _cell(row, index: dict[str, int], name: str):
    column = index.get(name)
    if column is None:
        return None
    value = row[column - 1].value
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


def _as_int(value) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    match = re.search(r"\d+", str(value))
    return int(match.group()) if match else None


def _as_level(value) -> str | None:
    """PIPE-01: the level is the word's own cell, never the week's phase label.

    A cell like "B1 (Phase 2)" still means B1, but "Phase 2" alone does not
    name a level and must not be guessed at from the sheet it sits on.
    """
    if value is None:
        return None
    match = re.search(r"\b(A1|A2|B1|B2|C1|C2)\b", str(value).upper())
    return match.group(1) if match else None


def read_workbook(path: Path) -> SourceBook:
    """Reads one workbook. Every required sheet must be present."""
    if not path.exists():
        raise PipelineError(
            f"{path.name} is missing. It is listed in content/manifest.yaml; "
            f"put it at {path} or take it out of the manifest."
        )

    # read_only for the row count, data_only so formula cells give their last
    # cached value rather than "=SUM(...)".
    book = load_workbook(path, read_only=True, data_only=True)
    try:
        sheets = {name.strip(): name for name in book.sheetnames}
        for required in (WORDS_SHEET, GRAMMAR_SHEET, SKILLS_SHEET):
            if required not in sheets:
                raise PipelineError(
                    f"{path.name} has no '{required}' sheet. Found: "
                    f"{', '.join(book.sheetnames)}"
                )

        # The category tabs are required too. Without one, every word's
        # category_id is null and the category filter on Search has nothing
        # to offer — which looks like a UI bug rather than a missing tab.
        if not any(
            name.strip().startswith(CATEGORY_SHEET_PREFIX) for name in sheets
        ):
            raise PipelineError(
                f"{path.name} has no '{CATEGORY_SHEET_PREFIX}…' category tab. "
                f"Found: {', '.join(book.sheetnames)}"
            )

        source = SourceBook(file=path.name)
        source.words = _read_words(book[sheets[WORDS_SHEET]], path.name)
        source.grammar = _read_grammar(book[sheets[GRAMMAR_SHEET]], path.name)
        source.skill_prompts = _read_skill_prompts(book[sheets[SKILLS_SHEET]])
        source.categories = _read_categories(book)

        if not source.words:
            raise PipelineError(f"{path.name}: '{WORDS_SHEET}' has no word rows")
        return source
    finally:
        book.close()


def _read_words(sheet, file_name: str) -> list[Word]:
    index, header_row = _header_index(
        sheet, HEADER_MAP, REQUIRED_WORD_FIELDS, f"{file_name}!{WORDS_SHEET}"
    )

    words: list[Word] = []
    for number, row in enumerate(
        sheet.iter_rows(min_row=header_row + 1), start=header_row + 1
    ):
        german = _cell(row, index, "german")
        english = _cell(row, index, "english")
        level = _as_level(_cell(row, index, "level"))

        # Padding, or a section divider that puts a label in one column and
        # nothing else. Both are rows a spreadsheet accumulates, and neither is
        # worth stopping a build over — but a row that names a word and then
        # omits its level still is.
        if german is None and english is None:
            continue

        if german is None or english is None or level is None:
            missing = [
                name
                for name, value in (
                    ("German", german),
                    ("English", english),
                    ("Level", level),
                )
                if value is None
            ]
            raise PipelineError(
                f"{file_name}!{WORDS_SHEET} row {number}: missing "
                f"{', '.join(missing)}. Required columns cannot be blank."
            )

        words.append(
            Word(
                source_file=file_name,
                row=number,
                article=_text(_cell(row, index, "article")),
                german=str(german),
                forms=_text(_cell(row, index, "forms")),
                pos=_text(_cell(row, index, "pos")),
                pron_bn=_text(_cell(row, index, "pron_bn")),
                english=str(english),
                bangla=_text(_cell(row, index, "bangla")),
                freq=_as_int(_cell(row, index, "freq")),
                level=level,
                category=_text(_cell(row, index, "category")),
                week=_as_int(_cell(row, index, "week")),
                examples_de=_text(_cell(row, index, "examples_de")),
                examples_en=_text(_cell(row, index, "examples_en")),
                collocations=_text(_cell(row, index, "collocations")),
                synonyms_register=_text(_cell(row, index, "synonyms_register")),
            )
        )
    return words


def _read_grammar(sheet, file_name: str) -> list[GrammarRow]:
    index, header_row = _header_index(
        sheet, GRAMMAR_HEADER_MAP, REQUIRED_GRAMMAR_FIELDS, f"{file_name}!{GRAMMAR_SHEET}"
    )

    rows: list[GrammarRow] = []
    for number, row in enumerate(
        sheet.iter_rows(min_row=header_row + 1), start=header_row + 1
    ):
        topic = _cell(row, index, "topic")
        if topic is None:
            continue
        rows.append(
            GrammarRow(
                source_file=file_name,
                row=number,
                week=_as_int(_cell(row, index, "week")),
                level=_as_level(_cell(row, index, "level")),
                topic=str(topic),
                rule=_text(_cell(row, index, "rule")),
                example_de=_text(_cell(row, index, "example_de")),
                example_en=_text(_cell(row, index, "example_en")),
                watch_out=_text(_cell(row, index, "watch_out")),
            )
        )
    return rows


def _read_skill_prompts(sheet) -> list[str]:
    """The weekly skills checklist.

    W01 is a free-form sheet, so every non-empty text cell in the first two
    columns counts, in reading order. Nothing downstream needs more structure
    than "the prompts, in order".

    Row 1 is the sheet's own heading, not something the learner can do. Without
    skipping it, "Weekly skills checklist" becomes the first thing they are
    asked to tick off.
    """
    prompts: list[str] = []
    for row in sheet.iter_rows(min_row=2, max_col=2):
        for cell in row:
            if isinstance(cell.value, str) and cell.value.strip():
                prompts.append(cell.value.strip())
    return prompts


def _read_categories(book) -> list[Category]:
    """The `C-…` tabs. The name after the prefix is the category."""
    categories: list[Category] = []
    for name in book.sheetnames:
        stripped = name.strip()
        if not stripped.startswith(CATEGORY_SHEET_PREFIX):
            continue
        sheet = book[name]
        description = None
        for row in sheet.iter_rows(min_row=1, max_row=1, max_col=2):
            for cell in row:
                if isinstance(cell.value, str) and cell.value.strip():
                    description = cell.value.strip()
                    break
        categories.append(
            Category(
                name=stripped[len(CATEGORY_SHEET_PREFIX) :].strip(),
                description=description,
            )
        )
    return categories


def _text(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def read_sources(manifest: Manifest) -> list[SourceBook]:
    """Reads every workbook, in manifest order."""
    return [read_workbook(path) for path in manifest.workbooks]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="content/manifest.yaml",
    )
    args = parser.parse_args(argv)

    try:
        manifest = read_manifest(args.manifest)
        sources = read_sources(manifest)
    except PipelineError as error:
        print(f"content pipeline: {error}", file=sys.stderr)
        return 1

    for source in sources:
        print(
            f"{source.file}: {len(source.words)} words, "
            f"{len(source.grammar)} grammar rows, "
            f"{len(source.categories)} categories, "
            f"{len(source.skill_prompts)} skill prompts"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
