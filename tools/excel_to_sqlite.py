"""Compile the authoring workbooks into content.db.

Excel is the authoring tool; the app never opens a workbook.
`docs/02-data/content-pipeline.md` is the specification, and the PIPE-nn
references in this file point at the rule each piece implements.

Run it through `make content`, which also verifies the result and copies the
asset. Running this module directly does the compile step alone.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import yaml
from openpyxl import load_workbook

from cloze import examples_without_their_word
from content_manifest import (
    MANIFEST_NAME,
    PreviousBuild,
    build_manifest,
    diff,
    grammar_key,
    link_uids,
    previous_build,
    word_key,
    write_manifest,
)
from content_writer import BuildInputs, build
from pipeline_steps import (
    GRAMMAR_PARTS,
    GRAMMAR_TEXT_FIELDS,
    LANGUAGE_CODES,
    LANGUAGES,
    LEGACY_FIELDS,
    WORD_PARTS,
    gate_languages,
    assign_tags,
    LEVELS,
    check_formula_prefixes,
    read_tips,
    resolve_tips,
    PipelineError,
    assign_examples,
    assign_kinds,
    apply_corrections,
    apply_grammar_corrections,
    read_corrections,
    assign_grammar_uids,
    assign_search_keys,
    assign_uids,
    cross_level_duplicates,
    drop_article_duplicates,
    split_articles,
    LevelSplit,
    assign_sublevels,
    split_level,
    check_every_step_has_words,
    resolve_grammar_levels,
    split_grammar,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = REPO_ROOT / "content" / "manifest.yaml"
#: The committed asset: what learners have, and what this build must not
#: silently take their progress from (#648).
DEFAULT_PREVIOUS = REPO_ROOT / "app" / "assets" / "db"

# Columns are read by header name, so the authors may reorder them freely.
# Renaming a header in Excel means changing it here — that is the whole
# contract, and it is why a missing required header is a hard failure rather
# than a silent None.
#
# Several headers have drifted across the workbooks, so each field lists
# every spelling seen. The first is the canonical one the doc names.
HEADER_MAP: dict[str, list[str]] = {
    "article": ["Article"],
    "german": ["German"],
    "forms": ["Plural / Forms", "Plural/Forms", "Plural", "Forms"],
    "pos": ["POS", "Part of speech"],
    "pron_bn": ["Pronunciation (Bangla)", "Pronunciation (BN)"],
    # #1080: `Meaning (X)` is a meaning language's column; today's headers
    # are English's and Bangla's.
    "english": ["English", "Meaning (English)"],
    "bangla": ["Bangla meaning", "Bangla", "Meaning (Bangla)"],
    "freq": ["Freq", "Frequency"],
    "level": ["Level"],
    "category": ["Category"],
    "week": ["Week"],
    "examples_de": ["Examples (DE)", "Example (DE)"],
    "examples_en": ["Examples (EN)", "Example (EN)", "Examples (English)"],
    "collocations": ["Collocations"],
    "synonyms_register": ["Synonyms / register", "Synonyms/register"],
}

#: The headers a workbook must carry. `pos` is here although its cell may be
#: blank: it is part of the uid (PIPE-03), and a renamed POS header would
#: give every word of the workbook a new one (#714).
REQUIRED_WORD_FIELDS = ("german", "english", "level", "pos")

#: Headers the trackers carry for the learner's own use, which the course
#: does not read. Any other header no map knows is reported (#714).
UNREAD_HEADERS = frozenset({"id", "status", "times logged", "#", "notes"})

GRAMMAR_HEADER_MAP: dict[str, list[str]] = {
    "week": ["Week"],
    "level": ["Level"],
    "topic": ["Topic", "Topic (English)"],
    "rule": ["Rule", "Rule (English)"],
    "example_de": ["Example (DE)", "Examples (DE)"],
    "example_en": ["Example (EN)", "Examples (EN)", "Example (English)"],
    "watch_out": ["Watch out", "Watch Out", "Watch out (English)"],
}

REQUIRED_GRAMMAR_FIELDS = ("topic",)

WORDS_SHEET = "All Words"
GRAMMAR_SHEET = "Grammar"
CATEGORY_SHEET_PREFIX = "C-"

#: How a category tab's title cell begins: "Category: Regional variation:
#: AT & CH". Excel cuts a sheet name at 31 characters and forbids ':' and
#: '/' in it, so the tab is "C-Regional variation- AT & CH" and only the
#: title carries the name the words' Category cells use (#636).
CATEGORY_TITLE_PREFIX = "Category:"


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

    # Derived by pipeline_steps, not read from the workbook.
    uid: str | None = None
    #: The uid the row had as read, when content/corrections.yaml changed it:
    #: the exact link PIPE-09 needs when a correction changes a uid field.
    corrected_from: str | None = None
    #: The uids of the rows corrections.yaml merged into this one (#635):
    #: PIPE-09 links each here.
    merged_from: list = field(default_factory=list)
    sublevel_code: str | None = None
    seq: int | None = None
    seq_in_sublevel: int | None = None
    search_key: str | None = None
    search_key_alt: str | None = None
    #: PIPE-10: vocab, note or compare; a correction may set it (#630).
    kind: str | None = None
    examples: list = field(default_factory=list)
    #: (part, code) -> text: a meaning language's columns but English's and
    #: Bangla's, which are the fields above (#1080, `LEGACY_FIELDS`).
    texts: dict = field(default_factory=dict)


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

    # Derived by pipeline_steps.
    uid: str | None = None
    sublevel_code: str | None = None
    level_code: str | None = None
    seq: int | None = None
    tags: str | None = None
    #: As `Word.texts`: `Topic (Russian)`'s text is ("topic", "ru")'s.
    texts: dict = field(default_factory=dict)


@dataclass
class Category:
    """A `C-…` tab. The tab name after the prefix is the category name."""

    name: str
    description: str | None = None


@dataclass
class SourceBook:
    """Everything read out of one workbook."""

    file: str
    #: The workbook's SHA-256, so a build says which bytes it came from
    #: (#634): `meta.sources` and the manifest carry it.
    sha256: str = ""
    words: list[Word] = field(default_factory=list)
    grammar: list[GrammarRow] = field(default_factory=list)
    categories: list[Category] = field(default_factory=list)
    #: Per sheet: the fields its header row carries, and the headers no map
    #: knows. `check_columns` compares the workbooks by them (#714).
    columns: dict[str, set[str]] = field(default_factory=dict)
    unmatched: dict[str, list[str]] = field(default_factory=dict)


@dataclass
class Manifest:
    workbooks: list[Path]
    tips: Path | None
    corrections: Path | None = None
    #: Per workbook file name: the fields it is known to lack, from its
    #: entry's `without:` (#714). B1 has no Collocations column, and that is
    #: the book, not a rename.
    without: dict[str, set[str]] = field(default_factory=dict)


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
    without: dict[str, set[str]] = {}
    known = set(HEADER_MAP) | set(GRAMMAR_HEADER_MAP)
    for entry in entries:
        if not isinstance(entry, dict) or "file" not in entry:
            raise PipelineError(
                f"{path}: every workbook entry needs a 'file:' key, got {entry!r}"
            )
        books.append(_resolve(entry["file"]))
        lacks = entry.get("without") or []
        # `without: collocations` is one field, not a set of letters (#845).
        lacks = {lacks} if isinstance(lacks, str) else set(lacks)
        if lacks - known:
            raise PipelineError(
                f"{path}: {entry['file']} `without:` names "
                f"{', '.join(sorted(lacks - known))}, which no map reads. List "
                f"fields, as content-pipeline.md's tables name them."
            )
        without[books[-1].name] = lacks

    tips = raw.get("tips")
    corrections = raw.get("corrections")
    return Manifest(
        workbooks=books,
        tips=_resolve(tips) if tips else None,
        corrections=_resolve(corrections) if corrections else None,
        without=without,
    )


def _resolve(value: str) -> Path:
    candidate = Path(value)
    return candidate if candidate.is_absolute() else REPO_ROOT / candidate


def _language_column(header: str, parts: dict[str, str]) -> tuple[str, str] | None:
    """#1080: `Meaning (Russian)` is ("meaning", "Russian"), when "Meaning"
    is one of the sheet's [parts]; anything else is None."""
    match = re.fullmatch(r"(.+?)\s*\((.+)\)", header)
    words = {word.lower(): part for part, word in parts.items()}
    if match and match.group(1).lower() in words:
        return words[match.group(1).lower()], match.group(2).strip()
    return None


def _header_index(
    sheet,
    header_map: dict[str, list[str]],
    required: tuple[str, ...],
    where: str,
    parts: dict[str, str] | None = None,
) -> tuple[dict, int, list[str]]:
    """Finds the header row and maps each field to its column index.

    A meaning language's column (#1080), one of [parts] with the language's
    English name, is mapped by (part, code): `Meaning (Russian)` is
    ("meaning", "ru"). A name `LANGUAGES` does not know stops the build.

    Also returns the header row's cells no map knows and `UNREAD_HEADERS`
    does not name: a renamed column shows up there (#714).

    The header is not assumed to be row 1: the workbooks carry a title row
    above it often enough that guessing would be a coin flip. The first row
    that carries every required header wins.
    """
    wanted = {
        name.strip().lower(): field
        for field, names in header_map.items()
        for name in names
    }
    known = {name.lower(): language.code for name, language in LANGUAGES.items()}

    for row_number, row in enumerate(sheet.iter_rows(min_row=1, max_row=10), start=1):
        found: dict = {}
        unknown: list[str] = []
        languages: list[tuple[str, str, int]] = []
        for column, cell in enumerate(row, start=1):
            if not isinstance(cell.value, str) or not cell.value.strip():
                continue
            header = cell.value.strip()
            field_name = wanted.get(header.lower())
            language = None if field_name else _language_column(header, parts or {})
            # First spelling wins, so a workbook carrying both "Plural" and
            # "Forms" does not flip between them depending on column order.
            if field_name and field_name not in found:
                found[field_name] = column
            elif language:
                languages.append((*language, column))
            elif not field_name and header.lower() not in UNREAD_HEADERS:
                unknown.append(header)
        if all(name in found for name in required):
            for part, name, column in languages:
                if name.lower() not in known:
                    raise PipelineError(
                        f"{where}: {parts[part]} ({name}) names no language "
                        f"the pipeline knows. Headers name a language in "
                        f"English, one of: {', '.join(LANGUAGES)}; a new one "
                        f"goes in LANGUAGES in pipeline_steps.py."
                    )
                found.setdefault((part, known[name.lower()]), column)
            return found, row_number, unknown

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

    # Rows are ragged. openpyxl's read-only mode stops a row at its last
    # non-empty cell, so a row whose "Watch out" is blank is simply shorter
    # than the header — which is most rows in the real workbooks, and none in
    # the fixtures. A missing trailing cell is an empty one, not an error.
    if column > len(row):
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
        for required in (WORDS_SHEET, GRAMMAR_SHEET):
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

        source = SourceBook(
            file=path.name, sha256=hashlib.sha256(path.read_bytes()).hexdigest()
        )
        source.words = _read_words(book[sheets[WORDS_SHEET]], source)
        source.grammar = _read_grammar(book[sheets[GRAMMAR_SHEET]], source)
        source.categories = _read_categories(book)

        if not source.words:
            raise PipelineError(f"{path.name}: '{WORDS_SHEET}' has no word rows")
        return source
    finally:
        book.close()


def _read_words(sheet, source: SourceBook) -> list[Word]:
    file_name = source.file
    index, header_row, unknown = _header_index(
        sheet, HEADER_MAP, REQUIRED_WORD_FIELDS, f"{file_name}!{WORDS_SHEET}", WORD_PARTS
    )
    source.columns[WORDS_SHEET] = set(index)
    source.unmatched[WORDS_SHEET] = unknown

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
                texts=_texts(row, index),
            )
        )
    return words


def _texts(row, index: dict) -> dict:
    """A row's meaning-language cells, (part, code) -> text, the blank left out."""
    return {
        key: text
        for key in index
        if isinstance(key, tuple) and (text := _text(_cell(row, index, key)))
    }


def _read_grammar(sheet, source: SourceBook) -> list[GrammarRow]:
    file_name = source.file
    index, header_row, unknown = _header_index(
        sheet,
        GRAMMAR_HEADER_MAP,
        REQUIRED_GRAMMAR_FIELDS,
        f"{file_name}!{GRAMMAR_SHEET}",
        GRAMMAR_PARTS,
    )
    source.columns[GRAMMAR_SHEET] = set(index)
    source.unmatched[GRAMMAR_SHEET] = unknown

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
                texts=_texts(row, index),
            )
        )
    return rows


def _read_categories(book) -> list[Category]:
    """The `C-…` tabs. The name is the title cell's, after `Category:`, or
    else the tab's after the prefix."""
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
        name = stripped[len(CATEGORY_SHEET_PREFIX) :].strip()
        if description and description.startswith(CATEGORY_TITLE_PREFIX):
            name = description[len(CATEGORY_TITLE_PREFIX) :].strip() or name
        categories.append(Category(name=name, description=description))
    return categories


def _text(value) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def read_sources(
    manifest: Manifest, allow_missing_columns: bool = False
) -> list[SourceBook]:
    """Reads every workbook, in manifest order."""
    sources = [read_workbook(path) for path in manifest.workbooks]
    check_columns(sources, allow_missing_columns, manifest.without)
    return sources


def _quoted(headers) -> str:
    return ", ".join(repr(header) for header in headers)


def check_columns(
    sources: list[SourceBook],
    allow_missing: bool = False,
    without: dict[str, set[str]] | None = None,
) -> None:
    """#714: a column a workbook lacks.

    A renamed header is not read, and nothing else notices: every word of
    that workbook ships without the column (its Bangla, its article), with
    no error anywhere. So a workbook missing a column the map reads stops
    the build, naming the file, the column and the headers it did not know;
    `--allow-missing-columns` builds anyway. Unknown headers are reported
    either way. A field the workbook's manifest entry lists under
    `without:` is one it is known to lack.

    Every field of the map, not only those another workbook carries: a
    header renamed in every workbook at once leaves none carrying it (#837).
    """
    without = without or {}
    maps = {WORDS_SHEET: HEADER_MAP, GRAMMAR_SHEET: GRAMMAR_HEADER_MAP}
    parts = {**WORD_PARTS, **GRAMMAR_PARTS}
    problems, warnings = [], []
    for sheet, header_map in maps.items():
        # #1080: a meaning language's columns, `Meaning (Russian)`, in every
        # workbook if in one. None has a `without:`.
        languages = {
            column
            for source in sources
            for column in source.columns.get(sheet, set())
            if isinstance(column, tuple)
        }
        names = {
            **{f: header_map[f][0] for f in header_map},
            **{(p, c): f"{parts[p]} ({LANGUAGE_CODES[c].name})" for p, c in languages},
        }
        every = set(header_map) | languages
        for source in sources:
            unknown = source.unmatched.get(sheet, [])
            if unknown:
                warnings.append(
                    f"unknown header: {source.file}!{sheet}: {_quoted(unknown)} "
                    f"(not read)"
                )
            missing = sorted(
                every
                - source.columns.get(sheet, set())
                - without.get(source.file, set()),
                key=str,
            )
            if not missing:
                continue
            problem = (
                f"{source.file}!{sheet} has no "
                f"{_quoted(names[f] for f in missing)} "
                f"column{'s' if len(missing) > 1 else ''}"
            )
            if unknown:
                problem += f" (headers it did not know: {_quoted(unknown)})"
            problems.append(problem)
    _report(warnings)
    if problems and not allow_missing:
        raise PipelineError(
            "; ".join(problems)
            + f". Rename the header back, or add its spelling to the map in "
            f"{Path(__file__).name}; a column the book never had goes under "
            f"its entry's `without:` in the manifest; --allow-missing-columns "
            f"builds without it."
        )
    for problem in problems:
        print(f"warning: {problem}; built without it", file=sys.stderr)


def correct(sources: list[SourceBook], corrections: dict[str, dict]) -> None:
    """Applies `content/corrections.yaml` (#628) to the rows as read.

    Over every workbook at once, because a key has to match one row in the
    whole course; then back into `source.words`, which is what ships.
    """
    kept = apply_corrections(
        [word for source in sources for word in source.words],
        corrections,
        {*HEADER_MAP, "kind"},
    )
    ids = {id(word) for word in kept}
    for source in sources:
        source.words = [word for word in source.words if id(word) in ids]
    if corrections:
        print(f"corrections: {len(corrections)} applied", file=sys.stderr)


def derive(
    sources: list[SourceBook],
    boundaries: dict[str, int] | None = None,
    grammar_steps: dict[str, str] | None = None,
) -> dict[str, LevelSplit]:
    """Everything between reading and writing: the step split, so far.

    Runs over all workbooks at once, because a level can be spread across two
    of them and the boundary is a property of the level, not of the file.
    [boundaries] is the shipped course's boundary week per level (#923),
    kept; [grammar_steps] its step of each grammar topic by uid (#970),
    whose split is kept too.
    """
    words = [word for source in sources for word in source.words]

    # #407: before anything counts the words, and out of `source.words` too,
    # which is what `collect` ships.
    words, dropped = drop_article_duplicates(words)
    _report(dropped)
    kept = {id(word) for word in words}
    for source in sources:
        source.words = [word for word in source.words if id(word) in kept]

    for source in sources:
        # content-pipeline.md: the manifest order is the fallback level order,
        # which points at the book rather than at its earliest level. An
        # unlabelled topic in a book carrying A1 and A2 on the way to B1 (as
        # the combined tracker did until it was split) is a B1 topic, and
        # filing the topic under A1 would teach it in the very first step.
        levels_here = [
            lvl for lvl in LEVELS if any(w.level == lvl for w in source.words)
        ]
        if levels_here:
            resolve_grammar_levels(source.grammar, levels_here[-1])

    splits = assign_sublevels(words, boundaries)
    check_every_step_has_words(words)
    # #923: a kept boundary the level's middle has moved away from, so the
    # author knows a split anew is there to be asked for.
    _report(
        [
            f"boundary kept: {split.second} starts at week "
            f"{split.boundary_week}, as shipped; split anew it would start at "
            f"week {week} (--move-boundaries)"
            for level, split in splits.items()
            if level in (boundaries or {})
            and (week := split_level(words, level).boundary_week)
            != split.boundary_week
        ]
    )

    grammar = [row for source in sources for row in source.grammar]
    # Before the split, which keeps the shipped one by uid (#970). A uid is
    # the level and the title, both settled by now.
    grammar_uid_warnings = assign_grammar_uids(grammar)
    _report(split_grammar(grammar, grammar_steps))

    coverage = assign_tags(grammar)
    print(
        f"grammar tags: {coverage['topics']} topics, "
        f"{coverage['word-order']} can produce Order the sentence",
        file=sys.stderr,
    )

    # seq is the reading order across every workbook; seq_in_sublevel is what
    # the step screen lists by.
    per_step: dict[str, int] = {}
    for index, word in enumerate(words, start=1):
        word.seq = index
        code = word.sublevel_code or ""
        per_step[code] = per_step.get(code, 0) + 1
        word.seq_in_sublevel = per_step[code]

    assign_search_keys(words)
    assign_examples(words)
    kinds = assign_kinds(words)
    print(
        "kinds: " + ", ".join(f"{count} {kind}" for kind, count in kinds.items()),
        file=sys.stderr,
    )

    warnings = (
        check_formula_prefixes(words)
        + check_formula_prefixes(grammar, GRAMMAR_TEXT_FIELDS)
        + assign_uids(words)
        + grammar_uid_warnings
        + examples_without_their_word(words)
    )
    _report(warnings)
    # After the uids, which stay those of the German cell as authored (#287).
    moved = split_articles(words)
    if moved:
        print(f"articles: {moved} moved out of the German cell", file=sys.stderr)
    # After the move, so "der Satzakzent" and "Satzakzent" are one word.
    _report(cross_level_duplicates(words))

    return splits


#: How many warnings of one kind are printed in full before the rest are
#: counted. A build with three hundred formula-looking cells should say so in
#: one line rather than scroll the real problems off the screen.
WARNING_SAMPLE = 10

#: Kinds that are never capped. Every line of these names a different thing
#: someone has to go and fix — a word whose primary key changed, a row the
#: build dropped, or an authored tip that will not appear. "…and 40 more"
#: would say how many and not which.
UNCAPPED_WARNINGS = frozenset(
    {
        "uid collision",
        "grammar uid collision",
        "dropped duplicate",
        "unmatched tip",
        "uid link",
        "removed",
        "example without its word",
        "cross-level duplicate",
        "stale link",
        "boundary kept",
        "grammar boundary kept",
    }
)


def _report(warnings: list[str]) -> None:
    """Prints the warnings, grouped and capped, with a total.

    Grouped by the text before the first colon, which is how each producer
    names its kind.
    """
    if not warnings:
        return

    by_kind: dict[str, list[str]] = {}
    for line in warnings:
        kind = line.split(":", 1)[0]
        by_kind.setdefault(kind, []).append(line)

    for kind, lines in by_kind.items():
        limit = len(lines) if kind in UNCAPPED_WARNINGS else WARNING_SAMPLE
        for line in lines[:limit]:
            print(f"warning: {line}", file=sys.stderr)
        if len(lines) > limit:
            print(
                f"warning: ...and {len(lines) - limit} more {kind}",
                file=sys.stderr,
            )

    print(
        "warnings: "
        + ", ".join(f"{len(lines)} {kind}" for kind, lines in by_kind.items()),
        file=sys.stderr,
    )


def languages_found(sources: list[SourceBook]) -> dict[str, set[str]]:
    """#1080: each meaning language the workbooks carry, by code, and the
    parts it has columns for. English's and Bangla's are today's headers."""
    by_field = {field: key for key, field in LEGACY_FIELDS.items()}
    found: dict[str, set[str]] = {}
    for source in sources:
        for columns in source.columns.values():
            for column in columns:
                key = column if isinstance(column, tuple) else by_field.get(column)
                if key:
                    found.setdefault(key[1], set()).add(key[0])
    return found


def collect(
    sources: list[SourceBook],
    splits: dict[str, LevelSplit],
    tips: list | None = None,
    allow_partial: tuple[str, ...] = (),
) -> BuildInputs:
    """Flattens the per-workbook records into what the writer takes, the
    meaning languages through PIPE-08's gate (#1080)."""
    # One clock read for the whole build (#718): meta.built_at, the
    # manifest's built_at and content_version all come from it, so the two
    # files can never disagree by the second between two calls.
    now = datetime.now(timezone.utc).replace(microsecond=0)
    words = [word for source in sources for word in source.words]
    grammar = [row for source in sources for row in source.grammar]
    languages, report = gate_languages(
        words, grammar, languages_found(sources), allow_partial
    )
    for line in report:
        print(line, file=sys.stderr)
    return BuildInputs(
        words=words,
        grammar=grammar,
        categories=[c for source in sources for c in source.categories],
        splits=splits,
        tips=tips or [],
        languages=languages,
        sources=[{"file": s.file, "sha256": s.sha256} for s in sources],
        # UTC. The app compares this string against the installed copy to
        # decide whether to replace it, so a local clock would let a build in
        # UTC+6 sort above a later one in CI and the new content would
        # silently not install. To the second (#722): two builds in one
        # minute were one version, and the second never installed. A
        # 14-digit stamp still sorts after every 12-digit one before it.
        content_version=now.strftime("%Y%m%d%H%M%S"),
        built_at=now.isoformat(),
    )


def link_previous(
    inputs: BuildInputs,
    previous: PreviousBuild,
    links: dict[str, dict],
    allow_removed: bool,
) -> dict[str, str]:
    """PIPE-09 (#648): links each changed uid to the one its word, or its
    grammar topic (#808), has now. Returns the alias map for the manifest.

    Before the build writes anything, so a refusal leaves no half-built
    course behind. [links] is `content/corrections.yaml`'s `links:` (#807):
    an entry pins an old uid `to:` a new one, or `refuse: true` leaves it
    linked to nothing, so it is removed.
    """
    words, topics = inputs.words, inputs.grammar
    after_words = {w.uid: word_key(w.level, w.german, w.pos, w.english) for w in words}
    after_topics = {r.uid: grammar_key(r.level, r.topic) for r in topics}
    known = {w.corrected_from: w.uid for w in words if w.corrected_from}
    known.update({old: w.uid for w in words for old in w.merged_from})

    refused: set[str] = set()
    stale: list[str] = []
    for old, entry in links.items():
        rest = {key: value for key, value in entry.items() if key != "why"}
        target = rest.get("to")
        if rest != {"refuse": True} and not (
            set(rest) == {"to"}
            and isinstance(target, str)
            and re.fullmatch(r"[0-9a-f]{16}", target)
        ):
            raise PipelineError(
                f'corrections: links {old} needs `to: "<uid>"` or '
                f"`refuse: true`, and nothing else but `why`."
            )
        before, after = (
            (previous.words, after_words)
            if old in previous.words
            else (previous.grammar, after_topics)
        )
        if old not in before or old in after:
            stale.append(
                f"stale link: {old} is no word or grammar topic the committed "
                f"course lost, so its `links:` entry does nothing. Delete it "
                f"once the course it was written for is committed."
            )
        elif target is None:
            refused.add(old)
        elif target not in after:
            raise PipelineError(
                f"corrections: links {old} pins to {target}, which is not a "
                f"{'word' if before is previous.words else 'grammar topic'} "
                f"of this build."
            )
        else:
            known[old] = target
    _report(stale)

    carried = (previous.manifest or {}).get("aliases", {})
    aliases: dict[str, str] = {}
    lines, lost = [], []
    for kind, before, after, width in (
        ("", previous.words, after_words, 4),
        ("grammar ", previous.grammar, after_topics, 2),
    ):
        found, unmatched = link_uids(before, after, carried, known, refused)
        aliases.update(found)
        lines += [
            f"uid link: {kind}{old} ({'|'.join(before[old][:width])}) -> "
            f"{new} ({'|'.join(after[new][:width])})"
            for old, new in found.items()
            if old in before
        ]
        lost += [
            f"removed: {kind}{uid} ({'|'.join(before[uid][:width])})"
            for uid in unmatched
        ]
    _report(lines + lost)
    if lost and not allow_removed:
        raise PipelineError(
            f"{len(lost)} word(s) or grammar topic(s) of the committed course "
            f"are gone and nothing in this build matches them, so learners "
            f"would lose their progress on them (listed above as 'removed'). "
            f"Restore them, link them under `links:` in "
            f"content/corrections.yaml, or rerun with --allow-removed if that "
            f"is intended."
        )
    return dict(sorted(aliases.items()))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="content/manifest.yaml",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "content" / "build" / "content.db",
        help="where to write content.db",
    )
    parser.add_argument(
        "--previous",
        type=Path,
        default=DEFAULT_PREVIOUS,
        help="the directory holding the previous build's content.db and "
        "manifest, to link changed uids against (PIPE-09)",
    )
    parser.add_argument(
        "--allow-removed",
        action="store_true",
        help="build even when a word or grammar topic of the previous build "
        "is gone and nothing matches it: learners lose their progress on it",
    )
    parser.add_argument(
        "--move-boundaries",
        action="store_true",
        help="split each level anew rather than keep the previous build's "
        "boundary week (#923) and grammar split (#970): words and topics "
        "move between steps under learners",
    )
    parser.add_argument(
        "--allow-missing-columns",
        action="store_true",
        help="build even when a workbook lacks a column another has "
        "(its words ship without it)",
    )
    parser.add_argument(
        "--allow-partial",
        action="append",
        default=[],
        metavar="CODE",
        help="build meaning language CODE (ru, pl …) although it is not 100 %% "
        "complete, for testing only: a partial language never ships (#1080)",
    )
    args = parser.parse_args(argv)

    try:
        manifest = read_manifest(args.manifest)
        previous = previous_build(args.previous)
        sources = read_sources(manifest, args.allow_missing_columns)
        correct(sources, read_corrections(manifest.corrections))
        splits = derive(
            sources,
            None if args.move_boundaries else previous.boundaries,
            None if args.move_boundaries else previous.grammar_steps,
        )
        # After the grammar uids, which key them (#637).
        apply_grammar_corrections(
            [row for source in sources for row in source.grammar],
            read_corrections(manifest.corrections, "grammar"),
        )
        resolved, tip_warnings = resolve_tips(
            read_tips(manifest.tips),
            [word for source in sources for word in source.words],
        )
        _report(tip_warnings)
        if tip_warnings:
            # #634: a tip nobody sees is authored text that never ships.
            raise PipelineError(
                f"{len(tip_warnings)} tip(s) in the tips CSV match no word "
                f"(listed above as 'unmatched tip'). Fix the match, or delete "
                f"the row until the course has the word."
            )
        inputs = collect(sources, splits, resolved, tuple(args.allow_partial))
        aliases = link_previous(
            inputs,
            previous,
            read_corrections(manifest.corrections, "links"),
            args.allow_removed,
        )
        build(args.out, inputs)

        manifest_path = args.out.parent / MANIFEST_NAME
        current = build_manifest(inputs, splits, aliases)
        write_manifest(manifest_path, current)
        if previous.manifest is not None:
            print(diff(previous.manifest, current).summary())
    except PipelineError as error:
        print(f"content pipeline: {error}", file=sys.stderr)
        return 1

    for source in sources:
        print(
            f"{source.file}: {len(source.words)} words, "
            f"{len(source.grammar)} grammar rows, "
            f"{len(source.categories)} categories"
        )
    for level, split in splits.items():
        print(
            f"{level}: {split.first} weeks 1-{split.weeks_in_first} "
            f"({split.words_in_first} words), {split.second} from week "
            f"{split.boundary_week} ({split.words_in_second} words)"
        )
    print(f"{args.out} written, content_version {inputs.content_version}")
    print(f"{manifest_path} written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
