"""PIPE-03: `uid = sha1(level|german|pos|english)[:16]`.

A uid is a primary key that outlives the build: `word_state.word_uid` in the
learner's database points at it. Changing how one is computed orphans every
learner's progress, so the fixture below is a regression guard, not a
convenience — if it fails, the question is never "update the expected value".
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    UID_FIELDS,
    UID_LENGTH,
    UidCollision,
    assign_uids,
    uid_for,
)

FIXTURE = Path(__file__).parent / "uid_fixture.json"


def word(**kwargs) -> Word:
    base = {
        "source_file": "test.xlsx",
        "row": 1,
        "german": "Haus",
        "english": "house",
        "level": "A1",
        "pos": "noun",
    }
    return Word(**{**base, **kwargs})


def test_the_recipe_is_the_one_the_doc_gives():
    assert UID_FIELDS == ("level", "german", "pos", "english")
    assert UID_LENGTH == 16
    expected = hashlib.sha1(b"A1|Haus|noun|house").hexdigest()[:16]
    assert uid_for(word()) == expected


def test_it_is_sixteen_hex_characters():
    uid = uid_for(word())
    assert len(uid) == 16
    assert all(c in "0123456789abcdef" for c in uid)


def test_every_field_changes_the_uid():
    # If one did not, two different words would share a key and a learner's
    # progress on both would merge.
    base = uid_for(word())
    for field, other in (
        ("level", "B1"),
        ("german", "Maus"),
        ("pos", "verb"),
        ("english", "building"),
    ):
        assert uid_for(word(**{field: other})) != base, field


def test_a_missing_pos_keeps_its_separator():
    # "der|Bank||bank" and "der|Bank|noun|bank" are different words. Dropping
    # the empty part instead of the value would make "Bank noun" and a word
    # whose English happens to be "noun" hash alike.
    assert uid_for(word(pos=None)) == hashlib.sha1(b"A1|Haus||house").hexdigest()[:16]
    # None and "" are the same absence, so an author clearing a cell does not
    # change the word's key.
    assert uid_for(word(pos=None)) == uid_for(word(pos=""))
    # And the empty part is still a part: without the separator, this would be
    # the same string as "A1|Haus|house" with a different field layout.
    assert uid_for(word(pos=None)) != uid_for(
        word(pos="house", english="")
    )


def test_umlauts_hash_the_same_everywhere():
    # Explicit UTF-8, so the digest does not depend on the platform's default
    # encoding — a build on Windows and one in CI must agree.
    expected = hashlib.sha1("A1|Tür|noun|door".encode("utf-8")).hexdigest()[:16]
    assert uid_for(word(german="Tür", english="door")) == expected


def test_rows_and_files_do_not_affect_it():
    # Moving a word to another row, or to another workbook, is not a change to
    # the word. The learner's progress has to survive both.
    assert uid_for(word(row=5, source_file="other.xlsx")) == uid_for(word())


class TestCollisions:
    def test_a_duplicate_row_is_resolved_with_its_sequence_number(self):
        first = word(row=1)
        second = word(row=2)
        first.seq, second.seq = 1, 2

        reports = assign_uids([first, second])

        assert first.uid != second.uid
        assert second.uid == uid_for(second, suffix=2)
        assert len(reports) == 1
        assert "row 2" in reports[0] and "row 1" in reports[0]

    def test_the_first_word_keeps_the_plain_uid(self):
        # Whoever comes first is unaffected, so adding a duplicate later in the
        # sheet cannot change an existing word's key.
        first, second = word(row=1), word(row=2)
        first.seq, second.seq = 1, 2
        assign_uids([first, second])
        assert first.uid == uid_for(word())

    def test_no_collision_means_no_report(self):
        words = [word(row=1, german="Haus"), word(row=2, german="Maus")]
        for index, w in enumerate(words, start=1):
            w.seq = index
        assert assign_uids(words) == []

    def test_a_resolution_that_still_collides_raises(self):
        # Cannot happen with sha1, but a uid is a primary key: silently writing
        # two rows with the same one is the outcome that must not exist.
        a, b, c = word(row=1), word(row=2), word(row=3)
        a.seq = b.seq = c.seq = 7  # same suffix, so the retry collides too
        with pytest.raises(UidCollision, match="still collides"):
            assign_uids([a, b, c])


def test_uids_are_stable_across_rebuilds():
    """The regression fixture.

    These are real uids from a fixed input. If this fails, a change to the
    recipe has orphaned every learner's `word_state` — the fix is to revert the
    change, not to rewrite the file. Regenerate it only alongside a migration
    that maps the old uids to the new ones.
    """
    cases = json.loads(FIXTURE.read_text(encoding="utf-8"))
    for case in cases:
        got = uid_for(
            word(
                level=case["level"],
                german=case["german"],
                pos=case["pos"],
                english=case["english"],
            )
        )
        assert got == case["uid"], (
            f"{case['german']}: uid changed from {case['uid']} to {got}. "
            f"Every learner's progress on this word is keyed to the old one."
        )


def test_the_fixture_is_not_empty():
    # Otherwise the guard above passes by having nothing to check.
    assert len(json.loads(FIXTURE.read_text(encoding="utf-8"))) >= 8
