"""PIPE-09 (#648): a word whose uid changed keeps the learner's progress.

The uid is `sha1(level|german|pos|english)`, so a gloss fix or a re-levelled
word gets a new one. The build links each removed uid to the uid the same word
has now, writes the map into the manifest for the app to move the learner's
rows along, and refuses to drop a word nothing matches.
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
import unicodedata
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_manifest import (  # noqa: E402
    MANIFEST_FORMAT,
    diff,
    link_uids,
    main as diff_main,
    read_manifest,
    word_key,
    write_manifest,
)
from excel_to_sqlite import Word, main as build_main  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from pipeline_steps import uid_for  # noqa: E402

HAUS = word_key("A1", "Haus", "noun", "house")


class TestLinks:
    def test_648_a_new_gloss_links_to_the_nearest_english(self):
        links, unmatched = link_uids(
            {"old": HAUS},
            {
                "far": word_key("A1", "Haus", "noun", "building, block"),
                "near": word_key("A1", "Haus", "noun", "house, home"),
            },
        )
        assert links == {"old": "near"}
        assert unmatched == []

    def test_648_a_relevelled_word_links_on_its_german_pos_and_english(self):
        links, _ = link_uids({"old": HAUS}, {"new": word_key("A2", *HAUS[1:])})
        assert links == {"old": "new"}

    def test_648_pos_case_and_an_nfd_paste_are_the_same_word(self):
        nfd = unicodedata.normalize("NFD", "Tür")
        links, _ = link_uids(
            {"old": word_key("A1", "Tür", "noun", "door")},
            {"new": word_key("A1", f" {nfd} ", "Noun", "the door")},
        )
        assert links == {"old": "new"}

    def test_648_another_word_is_not_linked(self):
        links, unmatched = link_uids(
            {"old": HAUS}, {"new": word_key("A1", "Maus", "noun", "mouse")}
        )
        assert links == {}
        assert unmatched == ["old"]

    def test_648_each_new_uid_takes_one_old_one(self):
        # Two senses of one word collapsed into one: one keeps its progress,
        # the other is reported rather than merged into it.
        links, unmatched = link_uids(
            {
                "a": word_key("A1", "Bank", "noun", "bench"),
                "b": word_key("A1", "Bank", "noun", "bank"),
            },
            {"c": word_key("A1", "Bank", "noun", "bank, bench")},
        )
        assert len(links) == 1 and len(unmatched) == 1

    def test_648_earlier_links_follow_this_builds(self):
        # A learner who skipped the build that made "x" into "old" still lands
        # on the word as it is now.
        links, _ = link_uids(
            {"old": HAUS},
            {"new": word_key("A1", "Haus", "noun", "home")},
            carried={"x": "old", "gone": "vanished"},
        )
        assert links == {"old": "new", "x": "new"}

    def test_648_a_word_that_came_back_is_not_linked_away(self):
        both = {"old": HAUS, "y": word_key("A1", "Maus", "noun", "mouse")}
        links, _ = link_uids(both, both, carried={"old": "y"})
        assert links == {}


def test_648_a_linked_word_is_changed_not_removed_and_added():
    def manifest(version, words, aliases=None):
        return {
            "format": MANIFEST_FORMAT,
            "content_version": version,
            "words": words,
            "meanings": words,
            "aliases": aliases or {},
        }

    result = diff(
        manifest("1", {"old": "a", "keep": "k"}),
        manifest("2", {"new": "b", "keep": "k"}, {"old": "new"}),
    )
    assert (result.added, result.removed) == ([], [])
    assert result.changed == ["new"]
    assert result.meaning == ["new"]


def test_648_a_word_linked_into_one_that_stays_is_still_removed():
    # A duplicate merged into the row that stays: the learner's rows move
    # where they can, and the card still counts one word gone.
    words = {"dup": "x", "kept": "y"}
    result = diff(
        {"format": MANIFEST_FORMAT, "content_version": "1", "words": words},
        {
            "format": MANIFEST_FORMAT,
            "content_version": "2",
            "words": {"kept": "y"},
            "aliases": {"dup": "kept"},
        },
    )
    assert (result.removed, result.changed) == (["dup"], [])


def test_648_the_uid_is_the_same_for_an_nfd_paste_and_extra_spaces():
    def word(german):
        return Word(source_file="f", row=1, german=german, english="door", level="A1", pos="noun")

    nfd = unicodedata.normalize("NFD", "Tür")
    assert nfd != "Tür"
    assert uid_for(word(nfd)) == uid_for(word("Tür"))
    assert uid_for(word(" Tür  ")) == uid_for(word("Tür"))


def test_648_the_diff_tool_says_what_is_missing_rather_than_crashing(tmp_path, capsys):
    previous = tmp_path / "previous.json"
    write_manifest(previous, {"format": MANIFEST_FORMAT, "content_version": "1", "words": {}})
    assert diff_main([str(previous), str(tmp_path / "content_manifest.json")]) == 1
    assert "no build at" in capsys.readouterr().err


class TestTheBuild:
    """The build against a committed asset, as `make content` runs it."""

    def build(self, tmp_path, *extra) -> int:
        manifest_yaml = tmp_path / "manifest.yaml"
        manifest_yaml.write_text(
            yaml.safe_dump({"workbooks": [{"file": str(tmp_path / n)} for n in BOOK_LEVELS]}),
            encoding="utf-8",
        )
        return build_main(
            ["--manifest", str(manifest_yaml), "--out", str(tmp_path / "build" / "content.db"), *extra]
        )

    def previous(self, tmp_path, sql: str) -> Path:
        """The fixture course as it was committed, then edited by [sql]."""
        write_all(tmp_path)
        assert self.build(tmp_path, "--previous", str(tmp_path / "none")) == 0
        previous = tmp_path / "previous"
        shutil.copytree(tmp_path / "build", previous)
        with sqlite3.connect(previous / "content.db") as connection:
            connection.execute(sql)
        connection.close()
        return previous

    def test_648_a_gloss_fixed_since_the_commit_is_linked_in_the_manifest(self, tmp_path):
        previous = self.previous(
            tmp_path,
            "UPDATE words SET uid = 'olduid', english = english || ' (old gloss)' "
            "WHERE seq = 1",
        )
        with sqlite3.connect(tmp_path / "build" / "content.db") as connection:
            (uid,) = connection.execute("SELECT uid FROM words WHERE seq = 1").fetchone()
        connection.close()
        # And a link from a build before that one, which has to follow.
        committed = read_manifest(previous / "content_manifest.json")
        write_manifest(
            previous / "content_manifest.json", {**committed, "aliases": {"older": "olduid"}}
        )

        assert self.build(tmp_path, "--previous", str(previous)) == 0
        manifest = read_manifest(tmp_path / "build" / "content_manifest.json")
        assert manifest["aliases"] == {"older": uid, "olduid": uid}

    def test_648_a_word_nothing_matches_stops_the_build(self, tmp_path, capsys):
        previous = self.previous(
            tmp_path,
            "INSERT INTO words (uid, sublevel_code, level_code, seq, seq_in_sublevel, "
            "german, english, search_key, search_key_alt) VALUES ('lostuid', 'A1.1', "
            "'A1', 999, 999, 'Zzyzx', 'nothing', 'zzyzx', 'zzyzx')",
        )
        assert self.build(tmp_path, "--previous", str(previous)) == 1
        err = capsys.readouterr().err
        assert "removed: lostuid" in err and "--allow-removed" in err

        assert self.build(tmp_path, "--previous", str(previous), "--allow-removed") == 0
        assert read_manifest(tmp_path / "build" / "content_manifest.json")["aliases"] == {}
