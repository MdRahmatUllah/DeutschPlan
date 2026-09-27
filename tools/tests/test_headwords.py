"""#629: a headword is the word the row teaches, not "X — Y".

In 31 of those rows every other column was about Y, so the card paired Y's
meaning with X. The fix changes their German, and so their uid: the row's
correction links the old uid to the new one exactly (PIPE-09), and the
learner keeps their progress.
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_manifest import link_uids, read_manifest, word_key  # noqa: E402
from content_writer import build  # noqa: E402
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from excel_to_sqlite import main as build_main  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from pipeline_steps import uid_for  # noqa: E402
from verify_content import check_no_pair_headword, verify  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SHIPPED = REPO / "app" / "assets" / "db" / "content.db"


def gate(path: Path, german: str):
    connection = sqlite3.connect(path)
    try:
        connection.execute("UPDATE words SET german = ? WHERE seq = 1", (german,))
        return check_no_pair_headword(connection)
    finally:
        connection.rollback()
        connection.close()


def test_629_a_pair_headword_fails_the_build_and_a_word_formation_note_does_not(tmp_path):
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources)))

    assert gate(path, "Haus") == []
    failures = gate(path, "untermauern — unterminieren")
    assert len(failures) == 1 and failures[0].gate == "headwords"
    assert "untermauern — unterminieren" in failures[0].message
    for note in ("beantworten — Präfix be-", "Freiheit — Wortbildung -heit", "unzufrieden — Negation mit un- vs. nicht"):
        assert gate(path, note) == [], note

    connection = sqlite3.connect(path)
    with connection:
        connection.execute("UPDATE words SET german = 'geschweige — desgleichen' WHERE seq = 1")
    connection.close()
    assert "headwords" in {failure.gate for failure in verify(path)}


def test_629_a_corrected_row_links_its_uid_exactly():
    # Nothing but the correction could link these: German and English both
    # changed.
    old = word_key("B2", "bestehen — nicht bestehen", "verb", "to pass / to fail an exam")
    new = word_key("B2", "bestehen", "verb", "to pass (an exam)")
    assert link_uids({"a": old}, {"b": new})[1] == ["a"]
    assert link_uids({"a": old}, {"b": new}, known={"a": "b"}) == ({"a": "b"}, [])
    # A correction that kept the uid links nothing.
    assert link_uids({"a": old}, {"a": old}, known={"a": "a"}) == ({}, [])


def test_629_the_build_links_a_corrected_german_to_the_committed_uid(tmp_path):
    write_all(tmp_path)
    workbooks = [{"file": str(tmp_path / n)} for n in BOOK_LEVELS]
    manifest = tmp_path / "manifest.yaml"
    manifest.write_text(yaml.safe_dump({"workbooks": workbooks}), encoding="utf-8")
    first = tmp_path / "first" / "content.db"
    assert build_main(["--manifest", str(manifest), "--out", str(first), "--previous", str(tmp_path / "none")]) == 0

    row = read_workbook(tmp_path / next(iter(BOOK_LEVELS))).words[0]
    old = uid_for(row)
    (tmp_path / "corrections.yaml").write_text(
        f'words:\n  "{old}":\n    why: t\n    german: "Ganz anders"\n    english: "quite different"\n',
        encoding="utf-8",
    )
    manifest.write_text(
        yaml.safe_dump({"workbooks": workbooks, "corrections": str(tmp_path / "corrections.yaml")}),
        encoding="utf-8",
    )
    out = tmp_path / "second" / "content.db"
    assert build_main(["--manifest", str(manifest), "--out", str(out), "--previous", str(first.parent)]) == 0

    connection = sqlite3.connect(out)
    (new,) = connection.execute("SELECT uid FROM words WHERE german = 'Ganz anders'").fetchone()
    connection.close()
    assert read_manifest(out.parent / "content_manifest.json")["aliases"] == {old: new}


def test_629_the_shipped_course_has_one_word_per_headword_and_the_three_articles(tmp_path):
    copy = tmp_path / "content.db"
    shutil.copy(SHIPPED, copy)
    connection = sqlite3.connect(copy)
    try:
        assert check_no_pair_headword(connection) == []
        articles = dict(
            connection.execute(
                "SELECT german, article FROM words "
                "WHERE german IN ('Weiterentwicklung', 'Freiwilligendienst', 'Vetorecht') "
                "AND level_code IN ('B2', 'C1')"
            ).fetchall()
        )
    finally:
        connection.close()
    assert articles == {"Weiterentwicklung": "die", "Freiwilligendienst": "der", "Vetorecht": "das"}
