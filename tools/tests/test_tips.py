"""Interference tips: `uid | german | pattern`, resolved at build time.

The app never runs a regex over the word list — every tip is attached to its
words here, which is the whole point of the CSV being compiled rather than
shipped.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    MATCH_TYPES,
    PipelineError,
    read_tips,
    resolve_tips,
)

REPO = Path(__file__).resolve().parents[2]
SEED = REPO / "content" / "interference_tips.csv"


def word(german: str, uid: str = "u1") -> Word:
    w = Word(
        source_file="f", row=1, german=german, english="x", level="A1"
    )
    w.uid = uid
    return w


def csv(tmp_path: Path, body: str) -> Path:
    path = tmp_path / "tips.csv"
    path.write_text(
        "match_type,match,tip_en,tip_bn,tags\n" + body, encoding="utf-8"
    )
    return path


class TestTheSeedSet:
    """The authored file, not a fixture — it ships."""

    def test_it_parses(self):
        tips = read_tips(SEED)
        assert len(tips) >= 15

    def test_every_match_type_is_used(self):
        # A type nobody uses is a type nobody has tested on real content.
        used = {tip.match_type for tip in read_tips(SEED)}
        assert used == {"german", "pattern"}, used

    def test_every_tip_has_bangla(self):
        # The audience is Bangla speakers. An English-only interference tip is
        # the one kind of card that helps the wrong reader.
        for tip in read_tips(SEED):
            assert tip.tip_bn, tip.match

    def test_the_false_friend_the_issue_names_is_there(self):
        tips = {tip.match: tip for tip in read_tips(SEED)}
        assert "bekommen" in tips
        assert "become" in tips["bekommen"].tip_en

    def test_every_pattern_compiles_and_is_anchored_or_suffixed(self):
        import re

        for tip in read_tips(SEED):
            if tip.match_type != "pattern":
                continue
            re.compile(tip.match)  # raises if it does not
            assert tip.match.startswith("^") or tip.match.endswith("$"), (
                f"{tip.match!r} is unanchored, so it would match anywhere "
                f"inside a compound and attach the tip to the wrong words"
            )


class TestMatching:
    def test_uid_matches_exactly_one_word(self):
        words = [word("Haus", "u1"), word("Maus", "u2")]
        tips = [
            _tip("uid", "u2"),
        ]
        resolved, warnings = resolve_tips(tips, words)
        assert [r.word_uid for r in resolved] == ["u2"]
        assert warnings == []

    def test_german_matches_case_insensitively(self):
        words = [word("Bekommen", "u1")]
        resolved, _ = resolve_tips([_tip("german", "bekommen")], words)
        assert [r.word_uid for r in resolved] == ["u1"]

    def test_german_does_not_match_a_substring(self):
        # "Rat" must not attach to "Ratte" or "Vorrat".
        words = [word("Ratte", "u1"), word("Vorrat", "u2")]
        _, warnings = resolve_tips([_tip("german", "Rat")], words)
        assert len(warnings) == 1

    def test_a_pattern_matches_a_family(self):
        words = [
            word("Mädchen", "u1"),
            word("Brötchen", "u2"),
            word("Haus", "u3"),
        ]
        resolved, _ = resolve_tips([_tip("pattern", "chen$")], words)
        assert {r.word_uid for r in resolved} == {"u1", "u2"}

    def test_a_pattern_is_case_insensitive(self):
        resolved, _ = resolve_tips(
            [_tip("pattern", "^seit")], [word("Seitdem", "u1")]
        )
        assert [r.word_uid for r in resolved] == ["u1"]

    def test_the_same_tip_twice_on_one_word_is_one_row(self):
        # (word_uid, tip_en) is the primary key. Two CSV rows that say the
        # same thing about the same word are one tip, not a write failure.
        words = [word("Haus", "u1")]
        tips = [_tip("german", "Haus"), _tip("pattern", "^Haus$")]
        resolved, _ = resolve_tips(tips, words)
        assert len(resolved) == 1

    def test_two_different_tips_on_one_word_both_land(self):
        words = [word("Haus", "u1")]
        tips = [_tip("german", "Haus", "first"), _tip("german", "Haus", "second")]
        resolved, _ = resolve_tips(tips, words)
        assert len(resolved) == 2


class TestWarnings:
    def test_a_tip_that_matches_nothing_is_reported(self):
        _, warnings = resolve_tips([_tip("german", "Nichtwort")], [word("Haus")])
        assert len(warnings) == 1
        assert "line 2" in warnings[0] and "Nichtwort" in warnings[0]

    def test_the_warning_says_the_tip_will_not_appear(self):
        # It is hand-authored prose about a word that has left the course, or
        # a regex with a typo. Either way the author expected to see it.
        _, warnings = resolve_tips([_tip("uid", "gone")], [word("Haus")])
        assert "will not appear" in warnings[0]

    def test_a_matching_tip_produces_no_warning(self):
        _, warnings = resolve_tips([_tip("german", "Haus")], [word("Haus")])
        assert warnings == []


class TestRefusals:
    def test_an_unknown_match_type_names_the_line(self, tmp_path):
        path = csv(tmp_path, "colour,red,a tip,,\n")
        with pytest.raises(PipelineError, match=r"line 2.*'colour'"):
            read_tips(path)

    def test_a_row_missing_its_english_names_what_is_missing(self, tmp_path):
        path = csv(tmp_path, "german,Haus,,only bangla,\n")
        with pytest.raises(PipelineError, match=r"line 2: missing tip_en"):
            read_tips(path)

    def test_a_broken_regex_names_the_line(self):
        with pytest.raises(PipelineError, match=r"line 2.*not a valid regex"):
            resolve_tips([_tip("pattern", "[unclosed")], [word("Haus")])

    def test_a_missing_file_says_where_it_is_named(self, tmp_path):
        with pytest.raises(PipelineError, match=r"manifest\.yaml"):
            read_tips(tmp_path / "nope.csv")

    def test_no_tips_file_is_not_an_error(self):
        # `tips:` is optional in the manifest.
        assert read_tips(None) == []

    def test_the_match_types_are_the_three_the_doc_names(self):
        assert MATCH_TYPES == ("uid", "german", "pattern")


def test_the_seed_tips_reach_words_in_a_real_build(tmp_path):
    """The wiring, not just the matcher.

    The seed patterns are written for real German; the fixture workbooks
    invent their vocabulary, so this asserts that *something* lands rather
    than a particular count.
    """
    from content_writer import build
    from excel_to_sqlite import collect, derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all
    import sqlite3

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    words = [w for s in sources for w in s.words]
    splits = derive(sources)
    resolved, _ = resolve_tips(read_tips(SEED), words)

    path = tmp_path / "content.db"
    build(path, collect(sources, splits, resolved))

    connection = sqlite3.connect(path)
    try:
        rows = connection.execute(
            "SELECT COUNT(*) FROM interference_tips"
        ).fetchone()[0]
        assert rows > 0, "no seed tip matched any fixture word"

        orphans = connection.execute(
            "SELECT COUNT(*) FROM interference_tips t "
            "LEFT JOIN words w ON w.uid = t.word_uid WHERE w.uid IS NULL"
        ).fetchone()[0]
        assert orphans == 0
    finally:
        connection.close()


def _tip(match_type: str, match: str, tip_en: str = "a tip"):
    from pipeline_steps import Tip

    return Tip(
        match_type=match_type,
        match=match,
        tip_en=tip_en,
        tip_bn="একটি টিপ",
        tags=None,
        row=2,
    )
