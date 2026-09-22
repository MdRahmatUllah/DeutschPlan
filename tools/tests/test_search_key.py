"""PIPE-04: the two search keys.

The vectors in `tools/test_vectors.json` are the contract between this and
`lib/domain/text_norm.dart`. Both sides load that file; neither restates it.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from excel_to_sqlite import Word  # noqa: E402
from pipeline_steps import (  # noqa: E402
    PUNCTUATION,
    UMLAUT_EXPANSIONS,
    UMLAUT_FOLDS,
    assign_search_keys,
    search_key,
    search_key_alt,
)

VECTORS = Path(__file__).resolve().parent.parent / "test_vectors.json"


def load() -> list[dict]:
    return json.loads(VECTORS.read_text(encoding="utf-8"))["vectors"]


def test_the_vector_file_is_populated():
    # Everything below iterates it; an empty file would pass by default.
    vectors = load()
    assert len(vectors) >= 25
    assert {v["input"] for v in vectors} >= {"Tür", "die Bank", "groß", "মেয়ে"}


def test_every_vector_reproduces():
    for vector in load():
        assert search_key(vector["input"]) == vector["search_key"], vector
        assert search_key_alt(vector["input"]) == vector["search_key_alt"], vector


def test_every_vector_says_what_it_is_for():
    # A vector nobody can explain is one nobody will know how to fix.
    for vector in load():
        assert vector["why"].strip()


class TestRules:
    def test_umlauts_expand_the_german_way_not_as_diacritics(self):
        # The whole point of two keys: ä is "ae" here and "a" in the alt.
        assert search_key("Tür") == "tuer"
        assert search_key_alt("Tür") == "tur"
        assert search_key("Mädchen") == "maedchen"
        assert search_key_alt("Mädchen") == "madchen"

    def test_eszett_is_ss_in_both(self):
        # There is no "s" folding of ß that anyone types.
        assert search_key("groß") == search_key_alt("groß") == "gross"
        assert search_key("Straße") == search_key("STRASSE")

    def test_a_leading_article_is_dropped(self):
        assert search_key("der Tisch") == "tisch"
        assert search_key("die Bank") == "bank"

    def test_only_a_whole_leading_word_counts_as_an_article(self):
        assert search_key("Diebstahl") == "diebstahl"
        assert search_key("Derby") == "derby"

    def test_the_article_alone_survives(self):
        # "der" is a word a learner can look up.
        assert search_key("der") == "der"

    def test_non_german_diacritics_are_stripped(self):
        assert search_key("Café") == "cafe"
        assert search_key("naïve") == "naive"

    def test_punctuation_and_spacing_do_not_matter(self):
        assert search_key("Guten Tag!") == "guten tag"
        assert search_key("der  Tisch") == "tisch"
        assert search_key("  Haus  ") == "haus"

    def test_bangla_passes_through_unchanged(self):
        # search.md matches `bangla = raw`, so a Bangla meaning has to come
        # back byte for byte. Its vowel signs are combining marks, which a
        # naive diacritic strip would eat.
        for text in ("মেয়ে", "বই", "ঘর্ষণ"):
            assert search_key(text) == text
            assert search_key_alt(text) == text

    def test_the_two_tables_cover_the_same_letters(self):
        assert set(UMLAUT_EXPANSIONS) == set(UMLAUT_FOLDS)


def test_the_article_column_is_folded_into_the_key():
    # A learner searching "das Haus" and one searching "Haus" want the same
    # row, and the article lives in its own column.
    word = Word(
        source_file="f",
        row=1,
        article="das",
        german="Haus",
        english="house",
        level="A1",
    )
    assign_search_keys([word])
    assert word.search_key == "haus"
    assert word.search_key_alt == "haus"


def test_a_word_with_no_article_keys_the_same_way():
    word = Word(
        source_file="f", row=1, german="Tür", english="door", level="A1"
    )
    assign_search_keys([word])
    assert (word.search_key, word.search_key_alt) == ("tuer", "tur")


def test_the_punctuation_list_is_the_one_dart_carries():
    """The two lists are written out separately, so this compares them.

    A Unicode category test would have been shorter on the Python side and
    impossible on the Dart side, and it would have eaten the Bangla danda.
    """
    import re

    dart = Path(__file__).resolve().parents[2] / "app/lib/domain/text_norm.dart"
    match = re.search(r"_punctuation = RegExp\(r'(.+)'\);", dart.read_text("utf-8"))
    assert match, "could not find _punctuation in text_norm.dart"

    pattern = re.compile(match.group(1))
    for code in range(0x20, 0x2100):
        char = chr(code)
        assert bool(pattern.fullmatch(char)) == (char in PUNCTUATION), (
            f"U+{code:04X} {char!r}: Dart and Python disagree on whether it is "
            f"punctuation, so the two search keys will differ on any word "
            f"containing it"
        )


def test_the_danda_is_not_treated_as_punctuation():
    # Unicode calls it Po. search.md matches `bangla = raw`, so it stays.
    assert "।" not in PUNCTUATION
    assert search_key("আমি ভালো।") == "আমি ভালো।"
