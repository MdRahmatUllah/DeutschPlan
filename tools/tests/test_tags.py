"""`grammar_topics.tags` — which practice item types a topic can produce.

`grammar-practice.md`: "Topics tagged in the pipeline (`grammar_topics.tags`,
comma list, derived from topic title keywords) decide which item types apply.
Every topic yields at least Gap fill + Pick the form."
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import GrammarRow  # noqa: E402
from pipeline_steps import (  # noqa: E402
    BASE_TAGS,
    TAG_KEYWORDS,
    WORD_ORDER_TAGS,
    assign_tags,
    tags_for,
)


def test_every_topic_yields_gap_fill_and_pick_the_form():
    # The guarantee the doc makes, for any title at all — including one that
    # matches no keyword, and an empty one.
    for title in ("Dativ nach Präpositionen", "Something nobody tagged", ""):
        assert set(BASE_TAGS) <= set(tags_for(title)), title


def test_the_base_tags_are_the_two_item_types_every_topic_supports():
    # Both are built from the example and the rule alone, which is why they
    # need no tag.
    assert BASE_TAGS == ("gap-fill", "pick-the-form")


def test_the_word_order_tags_are_the_three_the_doc_names():
    # "word-order topics only, detected by tags word-order, nebensatz, v2".
    assert WORD_ORDER_TAGS == {"word-order", "nebensatz", "v2"}


class TestDerivation:
    def test_german_and_english_titles_tag_alike(self):
        # The Topic column is authored in either, depending on the workbook.
        assert "nebensatz" in tags_for("Nebensätze mit weil")
        assert "nebensatz" in tags_for("Subordinate clauses with weil")

    def test_a_word_order_topic_unlocks_order_the_sentence(self):
        for title in (
            "Wortstellung im Hauptsatz",
            "Word order: time, manner, place",
            "Verbzweitstellung",
            "Nebensatz: dass",
        ):
            assert WORD_ORDER_TAGS & set(tags_for(title)), title

    def test_a_topic_that_is_not_about_order_does_not_get_those_tags(self):
        for title in ("Adjektivdeklination", "Das Perfekt", "Genus der Nomen"):
            assert not WORD_ORDER_TAGS & set(tags_for(title)), title

    def test_a_short_keyword_must_be_a_whole_word(self):
        # Both of these were live bugs in the first version, which matched
        # short keywords as substrings: "verb" fired on "Verbindung" and
        # "artikel" on "Partikel", tagging each topic with an item type it
        # cannot produce.
        assert "verb-form" not in tags_for("Die Verbindung von Sätzen")
        assert "gender" not in tags_for("Partikeln im Satz")
        assert "nebensatz" not in tags_for("Die Verwendung des Genitivs")

        # And still fires where it should.
        assert "verb-form" in tags_for("Das Verb im Hauptsatz")
        assert "gender" in tags_for("Der Artikel")
        assert "nebensatz" in tags_for("Konditionalsätze mit wenn")

    def test_a_long_keyword_may_continue_into_a_compound(self):
        # German writes these as one word, and they are exactly the topics
        # being looked for. A whole-word rule would miss every one.
        assert "v2" in tags_for("Verbzweitstellung")
        assert "preposition" in tags_for("Wechselpräpositionen")
        assert "adjective" in tags_for("Adjektivdeklination")
        assert "pronoun" in tags_for("Reflexivpronomen")

    def test_the_two_rules_meet_at_the_documented_length(self):
        from pipeline_steps import COMPOUND_HEAD_LENGTH

        assert COMPOUND_HEAD_LENGTH == 8
        short = [
            k
            for keywords in TAG_KEYWORDS.values()
            for k in keywords
            if len(k) < COMPOUND_HEAD_LENGTH and " " not in k
        ]
        # A short keyword that is a prefix of a common unrelated word is the
        # hazard; this just confirms the set is small enough to eyeball.
        assert short

    def test_one_title_can_carry_several_tags(self):
        tags = tags_for("Nebensatz: Wortstellung mit Dativ")
        assert {"nebensatz", "word-order", "case"} <= set(tags)

    def test_it_is_case_and_umlaut_insensitive_where_it_should_be(self):
        assert tags_for("PRÄTERITUM") == tags_for("präteritum")

    def test_the_result_is_deterministic_and_sorted(self):
        # A rebuild of unchanged content has to produce an identical database,
        # and the tags are a stored string.
        first = tags_for("Nebensatz und Wortstellung im Perfekt")
        assert first == tags_for("Nebensatz und Wortstellung im Perfekt")
        derived = first[len(BASE_TAGS) :]
        assert derived == sorted(derived)

    def test_every_keyword_reaches_its_tag(self):
        # Every one, not just the first: a typo in a later entry would never
        # be exercised, because an earlier keyword already produced the tag.
        for tag, keywords in TAG_KEYWORDS.items():
            for keyword in keywords:
                assert tag in tags_for(keyword), (
                    f"{tag} is not reached by {keyword!r}"
                )

    def test_a_function_word_does_not_tag_a_topic_about_something_else(self):
        # "Nicht trennbare Verben" is about separable prefixes. Tagging it
        # `negation` because the title contains "nicht" steers the
        # generator's distractors at the wrong thing.
        assert "negation" not in tags_for("Nicht trennbare Verben")
        assert "negation" in tags_for("Die Verneinung mit kein")


class TestAssignment:
    def rows(self, *titles: str) -> list[GrammarRow]:
        return [
            GrammarRow(source_file="f", row=i, topic=t, level="A1")
            for i, t in enumerate(titles, start=1)
        ]

    def test_it_stores_a_comma_list(self):
        rows = self.rows("Nebensatz mit weil")
        assign_tags(rows)
        assert rows[0].tags == "gap-fill,pick-the-form,nebensatz"

    def test_coverage_counts_what_matters(self):
        # Order the sentence is the one item type a missing tag silently
        # removes — the other four still appear, so nobody notices.
        rows = self.rows("Wortstellung", "Adjektivdeklination", "Nebensatz")
        coverage = assign_tags(rows)
        assert coverage == {"topics": 3, "word-order": 2}

    def test_every_row_gets_tags(self):
        rows = self.rows("a", "b", "c")
        assign_tags(rows)
        assert all(row.tags for row in rows)


def test_the_build_reports_tag_coverage(tmp_path, capsys):
    """#50 asks for coverage in the build summary.

    Through `derive`, not `assign_tags`: the count exists because Order the
    sentence disappears silently when the tag is missing, so losing the report
    loses the only signal that it did.
    """
    from excel_to_sqlite import derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    derive(sources)

    err = capsys.readouterr().err
    assert "grammar tags:" in err
    assert "can produce Order the sentence" in err


def test_the_tags_reach_the_database(tmp_path):
    import sqlite3

    from content_writer import build
    from excel_to_sqlite import collect, derive, read_workbook
    from fixtures.make_workbooks import BOOK_LEVELS, write_all

    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    path = tmp_path / "content.db"
    build(path, collect(sources, derive(sources)))

    connection = sqlite3.connect(path)
    try:
        rows = connection.execute("SELECT tags FROM grammar_topics").fetchall()
        assert rows
        for (tags,) in rows:
            assert set(BASE_TAGS) <= set(tags.split(",")), tags
    finally:
        connection.close()
