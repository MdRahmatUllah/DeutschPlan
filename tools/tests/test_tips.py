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


def word(german: str, uid: str = "u1", pos: str | None = None) -> Word:
    w = Word(
        source_file="f", row=1, german=german, english="x", level="A1", pos=pos
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

    def test_no_pattern_fires_on_a_word_it_is_wrong_about(self):
        """The anchoring test above is not enough.

        `chen$` is anchored and still matched der Kuchen, der Knochen and das
        Zeichen — telling the learner each is `das` because of a diminutive
        suffix none of them has. A tip meant to stop a mistake that is
        confidently wrong causes one instead.
        """
        import re

        never = {
            "gender": [
                "Kuchen",
                "Knochen",
                "Zeichen",
                "Drachen",
                "Rachen",
                "Sprung",
                "Schwung",
                "Dung",
                "jung",
                # #384: a compound of an exception, and a genitive whose
                # head is the Tag.
                "Aufschwung",
                "Tag der Deutschen Einheit",
            ]
        }
        always = {
            "gender": [
                "Mädchen",
                "Brötchen",
                "Wohnung",
                "Übung",
                "Freiheit",
                "psychische Gesundheit",
            ],
            # #384: a reflexive verb is still its prefix's.
            "separable": ["sich unterhalten", "sich übergeben", "übersetzen"],
        }

        for tag, words in never.items():
            patterns = [
                re.compile(tip.match, re.IGNORECASE)
                for tip in read_tips(SEED)
                if tip.match_type == "pattern" and tag in (tip.tags or "")
            ]
            for word_text in words:
                hits = [p.pattern for p in patterns if p.search(word_text)]
                assert not hits, f"{word_text} wrongly matched {hits}"

        for tag, words in always.items():
            patterns = [
                re.compile(tip.match, re.IGNORECASE)
                for tip in read_tips(SEED)
                if tip.match_type == "pattern" and tag in (tip.tags or "")
            ]
            for word_text in words:
                assert any(p.search(word_text) for p in patterns), word_text

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

    def test_a_word_class_tag_keeps_a_rule_to_its_class(self):
        """#321: "Every -chen noun is das" is false on *versuchen*, and a
        separable-prefix rule is false on *Überraschung*."""
        words = [
            word("Mädchen", "u1", "noun"),
            word("versuchen", "u2", "verb"),
            word("übersetzen", "u3", "verb"),
            word("Überraschung", "u4", "noun"),
            word("übermorgen", "u5", "adv"),
        ]
        chen = _tip("pattern", "chen$", "chen", tags="gender")
        uber = _tip("pattern", "^über", "über", tags="case;separable")
        resolved, _ = resolve_tips([chen, uber], words)
        assert {(r.tip_en, r.word_uid) for r in resolved} == {
            ("chen", "u1"),
            ("über", "u3"),
        }

    def test_an_untagged_tip_lands_on_any_word_class(self):
        words = [word("seit", "u1", "prep"), word("seitdem", "u2", "conj")]
        resolved, _ = resolve_tips([_tip("pattern", "^seit", tags="case")], words)
        assert len(resolved) == 2

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

    def test_a_tip_its_word_class_leaves_nothing_for_is_reported(self):
        _, warnings = resolve_tips(
            [_tip("pattern", "chen$", tags="gender")],
            [word("versuchen", "u1", "verb")],
        )
        assert len(warnings) == 1

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


def _tip(
    match_type: str, match: str, tip_en: str = "a tip", tags: str | None = None
):
    from pipeline_steps import Tip

    return Tip(
        match_type=match_type,
        match=match,
        tip_en=tip_en,
        tip_bn="একটি টিপ",
        tags=tags,
        row=2,
    )


class TestTheShippedCourse:
    """#321, over the content.db that ships."""

    DB = REPO / "app" / "assets" / "db" / "content.db"

    def test_no_word_class_rule_is_on_another_class(self):
        import sqlite3

        from verify_content import check_tips_fit_their_word_class

        db = sqlite3.connect(self.DB)
        try:
            assert check_tips_fit_their_word_class(db, SEED) == []
        finally:
            db.close()

    def test_versuchen_has_no_tip_and_das_maedchen_keeps_its_own(self):
        import sqlite3

        db = sqlite3.connect(self.DB)
        try:

            def tips(german: str) -> list[str]:
                return [
                    tip
                    for (tip,) in db.execute(
                        "SELECT t.tip_en FROM interference_tips t "
                        "JOIN words w ON w.uid = t.word_uid WHERE w.german = ?",
                        (german,),
                    )
                ]

            assert tips("versuchen") == []
            assert any('"-chen"' in tip for tip in tips("Mädchen"))
            # #384
            assert tips("Aufschwung") == []
            assert tips("Tag der Deutschen Einheit") == []
            assert any("separable" in tip for tip in tips("sich unterhalten"))
        finally:
            db.close()
