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


def test_a_word_without_a_week_sits_in_week_1_as_its_step_does(tmp_path):
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all
    from pipeline_steps import week_of

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    first = sources[0].words[0]
    assert first.week == 1
    added = dataclasses.replace(first, row=999, german="Ohnewoche", english="no week", week=None)
    sources[-1].words.append(added)

    derive(sources)

    level = sorted((w for s in sources for w in s.words if w.level == first.level), key=lambda w: w.seq)
    # Read last: after week 1's tracker words (agent-1 on #1335), not first.
    assert level.index(added) == sum(week_of(w) == 1 for w in level) - 1
    assert added.sublevel_code == first.sublevel_code


def test_the_build_writes_the_additions_workbook_afresh_when_it_reads_it(tmp_path, monkeypatch):
    import additions_workbook
    from excel_to_sqlite import Manifest, refresh_additions

    out = tmp_path / "German_Everyday_Additions.xlsx"
    monkeypatch.setattr(additions_workbook, "OUT", out)
    refresh_additions(Manifest(workbooks=[tmp_path / "German_A1_Tracker.xlsx"], tips=None))
    assert not out.exists()
    refresh_additions(Manifest(workbooks=[out], tips=None))
    assert out.exists()


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


def test_the_content_build_refreshes_it_before_reading_the_workbooks(monkeypatch):
    import excel_to_sqlite

    class Refreshed(Exception):
        pass

    def refreshed(manifest):
        assert any(book.name == "German_Everyday_Additions.xlsx" for book in manifest.workbooks)
        raise Refreshed

    def read(*_):
        raise AssertionError("read before the refresh")

    monkeypatch.setattr(excel_to_sqlite, "refresh_additions", refreshed)
    monkeypatch.setattr(excel_to_sqlite, "read_sources", read)
    try:
        excel_to_sqlite.main([])
    except Refreshed:
        return
    raise AssertionError("the build never refreshed the additions workbook")
