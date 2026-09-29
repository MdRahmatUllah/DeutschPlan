"""#634: the committed course, `app/assets/db/content.db`, passes every
PIPE-08 gate.

`verify_content.py` runs after a build; nothing ran it on the file that
ships, so an asset built from other workbooks, or edited by hand, could be
committed failing it. This runs it here, on a copy (verify's FTS check
writes, then rolls back), and shows the gates catch a planted defect in the
real file. The denylist's terms live outside git: without `data/` the gate
says it did not run.
"""

from __future__ import annotations

import json
import re
import shutil
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from verify_content import verify  # noqa: E402

ASSET = Path(__file__).resolve().parents[2] / "app" / "assets" / "db"


@pytest.fixture
def course(tmp_path) -> Path:
    copy = tmp_path / "content.db"
    shutil.copy(ASSET / "content.db", copy)
    return copy


def test_634_the_committed_course_passes_every_gate(course):
    assert [str(failure) for failure in verify(course)] == []


def test_634_it_names_the_workbooks_it_was_built_from_by_their_sha256(course):
    connection = sqlite3.connect(course)
    try:
        (meta,) = connection.execute("SELECT value FROM meta WHERE key = 'sources'").fetchone()
    finally:
        connection.close()
    manifest = json.loads((ASSET / "content_manifest.json").read_text(encoding="utf-8"))
    sources = json.loads(meta)
    assert sources == manifest["sources"]
    assert [source["file"] for source in sources] == [
        "German_A1_Tracker.xlsx",
        "German_A2_Tracker.xlsx",
        "German_B1_Tracker.xlsx",
        "German_B2_Tracker.xlsx",
        "German_C1_Tracker.xlsx",
        "German_C2_Tracker.xlsx",
    ]
    assert all(re.fullmatch(r"[0-9a-f]{64}", source["sha256"]) for source in sources)


def test_634_every_tip_in_the_csv_reaches_a_word_of_the_course(course):
    from types import SimpleNamespace

    from pipeline_steps import read_tips, resolve_tips

    connection = sqlite3.connect(course)
    try:
        words = [
            SimpleNamespace(uid=uid, german=german, pos=pos)
            for uid, german, pos in connection.execute("SELECT uid, german, pos FROM words")
        ]
    finally:
        connection.close()
    tips = ASSET.parents[2] / "content" / "interference_tips.csv"
    assert resolve_tips(read_tips(tips), words)[1] == []


@pytest.mark.parametrize(
    ("gate", "plant"),
    [
        ("steps", "UPDATE sublevels SET word_count = 0 WHERE code = 'B1.2'"),
        (
            "examples",
            "DELETE FROM word_examples WHERE word_uid = "
            "(SELECT uid FROM words WHERE kind = 'vocab' ORDER BY seq LIMIT 1)",
        ),
        (
            "duplicates",
            "UPDATE words SET german = 'Haus', pos = 'noun' WHERE uid = "
            "(SELECT uid FROM words WHERE level_code = 'A1' AND german <> 'Haus' "
            "AND kind = 'vocab' ORDER BY seq LIMIT 1)",
        ),
        ("articles", "UPDATE words SET article = NULL WHERE german = 'Haus'"),
        ("search", "DELETE FROM words_trigram WHERE rowid IN (SELECT rowid FROM words_trigram LIMIT 1)"),
    ],
)
def test_634_a_planted_defect_in_the_real_file_fails_its_gate(course, gate, plant):
    connection = sqlite3.connect(course)
    with connection:
        connection.execute(plant)
    connection.close()
    assert gate in {failure.gate for failure in verify(course)}
