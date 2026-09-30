"""docs/05-dev-guide/site-facts.json, what sogda.de syncs (#1174)."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import export_site_facts as export  # noqa: E402


def course(query: str, *args) -> list[tuple]:
    db = sqlite3.connect(f"{export.DB.as_uri()}?mode=ro", uri=True)
    try:
        return db.execute(query, args).fetchall()
    finally:
        db.close()


def committed() -> dict:
    return json.loads(export.OUT.read_text(encoding="utf-8"))


def test_1174_the_committed_file_is_todays_course():
    # A content build that moves a count can't merge without a re-export,
    # so the site's pinned file is always true for its commit.
    assert export.main(["--check"]) == 0, "run python tools/export_site_facts.py"


def test_1174_a_stale_file_fails_the_check(tmp_path, monkeypatch):
    stale = tmp_path / "site-facts.json"
    stale.write_text(export.OUT.read_text(encoding="utf-8").replace('"words": ', '"words": 1', 1), encoding="utf-8")
    monkeypatch.setattr(export, "OUT", stale)
    assert export.main(["--check"]) == 1


def test_1174_the_totals_are_the_courses():
    totals = committed()["totals"]
    ((vocab,),) = course("select count(*) from words where kind = 'vocab'")
    ((topics,),) = course("select count(*) from grammar_topics")
    ((steps,),) = course("select count(*) from sublevels")
    assert totals == {
        "words": vocab,
        "grammar_topics": topics,
        "steps": steps,
        "mock_exams_per_step": 3,
        "mock_exams": 3 * steps,
    }


def test_1174_each_step_is_its_own_counts_and_topics():
    for step in committed()["steps"]:
        ((words,),) = course(
            "select count(*) from words where sublevel_code = ? and kind = 'vocab'", step["code"]
        )
        topics = [uid for (uid,) in course(
            "select uid from grammar_topics where sublevel_code = ? order by seq", step["code"]
        )]
        assert step["words"] == words, step["code"]
        assert [g["uid"] for g in step["grammar"]] == topics, step["code"]
        assert step["grammar_topics"] == len(topics), step["code"]
        # Russian and Polish carry the grammar's names; Bangla has none (#1147).
        assert all(set(g["topic"]) == {"en", "ru", "pl"} for g in step["grammar"]), step["code"]


def test_1174_the_sample_is_the_steps_words_in_every_language():
    for step in committed()["steps"]:
        uids = {uid for (uid,) in course(
            "select uid from words where sublevel_code = ? and kind = 'vocab' and pos != 'phrase'",
            step["code"],
        )}
        assert len(step["sample"]) == export.SAMPLE, step["code"]
        for word in step["sample"]:
            assert word["uid"] in uids, (step["code"], word["german"])
            assert set(word["meaning"]) == set(word["guide"]) == {"en", "bn", "ru", "pl"}
            assert all(word["meaning"].values()) and all(word["guide"].values()), word["german"]


def test_1174_the_sample_is_stable():
    # The level pages mustn't reshuffle on every build: the order is a hash of
    # the uid, so only a change to the step's words changes its sample.
    step = committed()["steps"][0]
    order = [w["uid"] for w in step["sample"]]
    assert order == sorted(order, key=export._sample_order)


def test_1174_the_paper_is_br_exam_03s():
    paper = committed()["mock_exam"]
    assert (paper["questions"], paper["tasks"], paper["points"]) == (40, 2, 48)
    assert [s["id"] for s in paper["sections"]][-2:] == ["writing", "speaking"]
    assert set(paper["writing_min_words"]) == set(paper["speaking_seconds"]) == {
        "A1", "A2", "B1", "B2", "C1", "C2",
    }


def test_1174_the_listing_is_store_listing_md_verbatim():
    listing = committed()["listing"]
    texts = export.listing_texts()
    assert listing["en"]["title"] == texts[("English (en-US)", "Title")]
    assert listing["bn"]["full"] == texts[("Bangla (bn-BD)", "Full description")]
    assert set(listing) == {"en", "bn", "pl", "ru"}
