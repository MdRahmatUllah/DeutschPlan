"""#1257: the additions workbook. Its words take their week's place among the
trackers' (seq), and none of the trackers' words moves."""

from __future__ import annotations

import dataclasses
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def test_a_later_workbooks_word_takes_its_weeks_place_and_no_other_moves(tmp_path):
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    first = sources[0].words[0]
    tracker = [w for s in sources for w in s.words]
    # Read last, as the additions workbook is: the first level, its first week.
    added = dataclasses.replace(first, row=999, german="Neuwort", english="new word")
    sources[-1].words.append(added)

    derive(sources)

    in_order = sorted((w for s in sources for w in s.words), key=lambda w: w.seq)
    level = [w for w in in_order if w.level == first.level]
    week = [w for w in level if w.week == first.week]
    # After the week's tracker words, before the next week's.
    assert week[-1] is added
    assert level.index(added) == len(week) - 1
    # The trackers' words keep their order and their steps.
    assert [w for w in in_order if w is not added] == tracker
    assert added.sublevel_code == first.sublevel_code


def test_the_committed_additions_are_complete():
    from additions_workbook import category_names, problems, read_entries

    entries = read_entries()
    assert len(entries) == 73
    assert problems(entries, category_names()) == []


def test_a_broken_entry_is_refused():
    from additions_workbook import category_names, problems, read_entries

    entry = dict(read_entries()[0])
    entry["ru"] = {**entry["ru"], "examples": "nur eine Zeile"}
    entry["category"] = "Nowhere"
    entry["week"] = 0
    found = problems([entry, dict(entry)], category_names())
    assert any("ru examples don't pair" in p for p in found)
    assert any("category 'Nowhere'" in p for p in found)
    assert any("week 0" in p for p in found)
    assert any(p.endswith("twice") for p in found)


def test_the_workbook_reads_as_the_trackers_do(tmp_path):
    from additions_workbook import read_entries, write
    from excel_to_sqlite import read_workbook

    entries = read_entries()
    out = tmp_path / "German_Everyday_Additions.xlsx"
    write(entries, out)
    book = read_workbook(out)
    assert len(book.words) == len(entries)
    name = next(w for w in book.words if w.german == "Name")
    assert (name.article, name.level, name.week, name.category) == (
        "der", "A1", 1, "Greetings & politeness")
    assert name.examples_de.count("\n") == name.examples_en.count("\n") == 1
    assert book.grammar == []
