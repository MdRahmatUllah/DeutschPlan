"""#628: the corrections layer, and the denylist gate; #635: duplicates.

The workbooks are never written by a tool (#545), so a fix to a row lives in
`content/corrections.yaml` and is applied by the pipeline. The denylist gate
fails a build that ships a term which must never ship; its terms live outside
git, so the tests plant their own.
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_writer import build  # noqa: E402
from excel_to_sqlite import (  # noqa: E402
    HEADER_MAP,
    Word,
    collect,
    correct,
    derive,
    read_workbook,
)
from excel_to_sqlite import main as build_main  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402
from pipeline_steps import (  # noqa: E402
    PipelineError,
    apply_corrections,
    cross_level_duplicates,
    read_corrections,
    uid_for,
)
from verify_content import (  # noqa: E402
    DEFAULT_DENYLIST,
    check_no_denylisted_terms,
    check_no_same_level_duplicates,
    verify,
)

REPO = Path(__file__).resolve().parents[2]
BOOK_LEVELS_FIRST = next(iter(BOOK_LEVELS))


def word(**kwargs) -> Word:
    base = {
        "source_file": "t.xlsx",
        "row": 1,
        "german": "Haus",
        "english": "house",
        "level": "A1",
        "pos": "noun",
        "examples_de": "Das Haus ist alt.\nDas Haus ist groß.",
        "examples_en": "The house is old.\nThe house is big.",
    }
    return Word(**{**base, **kwargs})


def corrected(words, entries):
    return apply_corrections(words, entries, HEADER_MAP)


class TestCorrections:
    def test_628_one_example_line_is_replaced_and_the_rest_kept(self):
        haus = word()
        corrected(
            [haus],
            {uid_for(haus): {"why": "t", "example_de_2": "Das Haus ist neu.", "example_en_2": "The house is new."}},
        )
        assert haus.examples_de == "Das Haus ist alt.\nDas Haus ist neu."
        assert haus.examples_en == "The house is old.\nThe house is new."

    def test_628_the_line_after_the_last_is_added(self):
        haus = word()
        corrected([haus], {uid_for(haus): {"why": "t", "example_de_3": "Ein Haus."}})
        assert haus.examples_de.splitlines()[-1] == "Ein Haus."

    def test_628_a_column_is_set_and_a_row_deleted(self):
        haus, maus = word(), word(german="Maus", english="mouse")
        kept = corrected(
            [haus, maus],
            {
                uid_for(haus): {"why": "t", "article": "das"},
                uid_for(maus): {"why": "t", "delete": True},
            },
        )
        assert kept == [haus]
        assert haus.article == "das"

    @pytest.mark.parametrize(
        "entry",
        [
            {"why": "t", "not_a_column": "x"},
            {"why": "t", "example_de_5": "too far"},
        ],
    )
    def test_628_an_entry_the_pipeline_cannot_apply_fails_the_build(self, entry):
        haus = word()
        with pytest.raises(PipelineError):
            corrected([haus], {uid_for(haus): entry})

    def test_628_a_key_that_matches_no_row_or_two_fails_the_build(self):
        with pytest.raises(PipelineError, match="matches 0 rows"):
            corrected([word()], {"0123456789abcdef": {"why": "t"}})
        with pytest.raises(PipelineError, match="matches 2 rows"):
            corrected([word(), word(row=2)], {uid_for(word()): {"why": "t"}})

    def test_628_every_entry_says_why_and_is_keyed_by_a_quoted_uid(self, tmp_path):
        path = tmp_path / "corrections.yaml"
        path.write_text('words:\n  "0123456789abcdef":\n    german: X\n', encoding="utf-8")
        with pytest.raises(PipelineError, match="why"):
            read_corrections(path)
        path.write_text("words:\n  1234567890123456:\n    why: t\n", encoding="utf-8")
        with pytest.raises(PipelineError, match="not a uid"):
            read_corrections(path)

    def test_628_the_committed_file_reads_and_holds_new_text_only(self):
        entries = read_corrections(REPO / "content" / "corrections.yaml")
        assert entries
        for entry in entries.values():
            assert set(entry) - {"why"}, "an entry that changes nothing"

    def test_628_the_build_reads_the_manifests_corrections(self, tmp_path):
        write_all(tmp_path)
        first = read_workbook(tmp_path / BOOK_LEVELS_FIRST).words[0]
        (tmp_path / "corrections.yaml").write_text(
            f'words:\n  "{uid_for(first)}":\n    why: t\n    example_de_1: "Ganz neu."\n',
            encoding="utf-8",
        )
        manifest = tmp_path / "manifest.yaml"
        manifest.write_text(
            yaml.safe_dump(
                {
                    "workbooks": [{"file": str(tmp_path / n)} for n in BOOK_LEVELS],
                    "corrections": str(tmp_path / "corrections.yaml"),
                }
            ),
            encoding="utf-8",
        )
        out = tmp_path / "build" / "content.db"
        # --previous: no committed course to link against (PIPE-09).
        argv = ["--manifest", str(manifest), "--out", str(out)]
        assert build_main(argv + ["--previous", str(tmp_path / "none")]) == 0
        connection = sqlite3.connect(out)
        try:
            (german,) = connection.execute(
                "SELECT german FROM word_examples WHERE ord = 1 AND word_uid = "
                "(SELECT uid FROM words WHERE seq = 1)"
            ).fetchone()
        finally:
            connection.close()
        assert german == "Ganz neu."

    def test_628_the_build_applies_them_before_the_uids(self, tmp_path):
        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        first = sources[0].words[0]
        key = uid_for(first)
        correct(sources, {key: {"why": "t", "german": "Ganz neu", "example_de_1": "Ganz neu."}})

        path = tmp_path / "content.db"
        build(path, collect(sources, derive(sources)))
        connection = sqlite3.connect(path)
        try:
            (uid,) = connection.execute("SELECT uid FROM words WHERE german = 'Ganz neu'").fetchone()
            (german,) = connection.execute(
                "SELECT german FROM word_examples WHERE word_uid = ? AND ord = 1", (uid,)
            ).fetchone()
        finally:
            connection.close()
        assert german == "Ganz neu."
        assert uid != key, "the uid is the corrected word's"


class TestDuplicates:
    """#635: a word taught twice, across levels or within one."""

    def test_635_merge_into_drops_the_row_and_the_one_that_stays_takes_its_uid_and_blanks(self):
        haus = word(bangla="বাড়ি", examples_de=None, examples_en=None)
        twin = word(row=2, level="B2", collocations="ein Haus bauen", article="das", bangla="ঘর")
        kept = corrected([haus, twin], {uid_for(twin): {"why": "t", "merge_into": uid_for(haus)}})
        assert kept == [haus]
        assert haus.merged_from == [uid_for(twin)]
        assert (haus.collocations, haus.article) == ("ein Haus bauen", "das")
        assert haus.bangla == "বাড়ি", "only its blanks"
        assert haus.examples_de is None, "never the examples"

    def test_635_the_link_is_from_the_uid_the_row_ships_with(self):
        # A row whose own correction changed its uid: learners hold that one.
        haus, twin = word(), word(row=2, level="B2", german="Haus — Heim")
        corrected(
            [haus, twin],
            {uid_for(twin): {"why": "t", "german": "Haus", "merge_into": uid_for(haus)}},
        )
        assert haus.merged_from == [uid_for(word(level="B2"))]

    def test_635_merge_into_a_row_that_does_not_stay_fails_the_build(self):
        haus, twin = word(), word(row=2, level="B2")
        with pytest.raises(PipelineError, match="not one row that stays"):
            corrected([haus], {uid_for(haus): {"why": "t", "merge_into": "0123456789abcdef"}})
        with pytest.raises(PipelineError, match="not one row that stays"):
            corrected(
                [haus, twin],
                {
                    uid_for(twin): {"why": "t", "merge_into": uid_for(haus)},
                    uid_for(haus): {"why": "t", "delete": True},
                },
            )

    def test_635_a_merged_row_links_its_uid_to_the_row_that_stays(self, tmp_path):
        write_all(tmp_path)
        keep, twin = read_workbook(tmp_path / BOOK_LEVELS_FIRST).words[:2]
        manifest = tmp_path / "manifest.yaml"
        books = [{"file": str(tmp_path / n)} for n in BOOK_LEVELS]
        manifest.write_text(yaml.safe_dump({"workbooks": books}), encoding="utf-8")
        out = tmp_path / "build" / "content.db"
        argv = ["--manifest", str(manifest), "--out", str(out)]
        assert build_main(argv + ["--previous", str(tmp_path / "none")]) == 0
        shutil.copytree(out.parent, tmp_path / "previous")

        (tmp_path / "corrections.yaml").write_text(
            f'words:\n  "{uid_for(twin)}":\n    why: t\n    merge_into: "{uid_for(keep)}"\n',
            encoding="utf-8",
        )
        manifest.write_text(
            yaml.safe_dump({"workbooks": books, "corrections": str(tmp_path / "corrections.yaml")}),
            encoding="utf-8",
        )
        assert build_main(argv + ["--previous", str(tmp_path / "previous")]) == 0
        manifest_json = json.loads((out.parent / "content_manifest.json").read_text(encoding="utf-8"))
        assert manifest_json["aliases"] == {uid_for(twin): uid_for(keep)}

    def test_635_a_word_in_two_levels_is_listed_in_the_build_report(self):
        a1, b2 = word(), word(row=2, level="B2", english="House")
        lines = cross_level_duplicates(
            [a1, b2, word(row=3, level="B2", english="home"), word(row=4, german="Maus")]
        )
        assert len(lines) == 1
        assert lines[0].startswith("cross-level duplicate: 'Haus'")
        assert "A1 (t.xlsx row 1), B2 (t.xlsx row 2)" in lines[0]
        assert cross_level_duplicates([a1, word(row=2, english="home")]) == []
        assert cross_level_duplicates([a1, word(row=2)]) == [], "one level: PIPE-08's"

    @staticmethod
    def same_level(rows):
        connection = sqlite3.connect(":memory:")
        connection.execute("CREATE TABLE words (level_code TEXT, german TEXT, pos TEXT)")
        connection.executemany("INSERT INTO words VALUES (?, ?, ?)", rows)
        try:
            return check_no_same_level_duplicates(connection)
        finally:
            connection.close()

    def test_635_one_word_twice_in_a_level_fails_verify_unless_two_words(self):
        failures = self.same_level([("A1", "Kunde", "noun")] * 2 + [("B2", "Kunde", "noun")])
        assert [f.gate for f in failures] == ["duplicates"]
        assert "Kunde (A1, noun) x2" in failures[0].message
        # Two words, kept on purpose; and case makes a word: Sie and sie.
        assert self.same_level([("A1", "ihr", "pron")] * 2 + [("A1", "Sie", "pron"), ("A1", "sie", "pron")]) == []

    def test_635_verify_runs_the_gate(self, tmp_path):
        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        course = tmp_path / "course.db"
        build(course, collect(sources, derive(sources)))
        with sqlite3.connect(course) as connection:
            connection.execute(
                "UPDATE words SET (german, pos) = (SELECT german, pos FROM words WHERE seq = 1) "
                "WHERE seq = 2"
            )
        connection.close()
        assert "duplicates" in {failure.gate for failure in verify(course)}

    def test_635_the_shipped_course_teaches_each_word_once_per_level(self):
        connection = sqlite3.connect(REPO / "app" / "assets" / "db" / "content.db")
        try:
            assert check_no_same_level_duplicates(connection) == []
        finally:
            connection.close()


class TestDenylist:
    @pytest.fixture
    def database(self, tmp_path) -> Path:
        path = tmp_path / "content.db"
        connection = sqlite3.connect(path)
        connection.executescript(
            "CREATE TABLE words (uid TEXT PRIMARY KEY, german TEXT);"
            "CREATE TABLE word_examples (word_uid TEXT, ord INTEGER, german TEXT, english TEXT);"
            "CREATE VIRTUAL TABLE examples_fts USING fts5(german);"
            "INSERT INTO words VALUES ('u1', 'Haus');"
            "INSERT INTO word_examples VALUES ('u1', 1, 'Ich wohne in Zebrastadt.', 'I live in Zebrastadt.');"
        )
        connection.commit()
        connection.close()
        return path

    def check(self, database, terms: str, tmp_path):
        denylist = tmp_path / "denylist.txt"
        denylist.write_text(terms, encoding="utf-8")
        connection = sqlite3.connect(database)
        try:
            return check_no_denylisted_terms(connection, denylist)
        finally:
            connection.close()

    def test_628_a_planted_term_fails_the_build(self, database, tmp_path):
        failures = self.check(database, "# a comment\nnichts\nZEBRASTADT\n", tmp_path)
        assert len(failures) == 1
        assert failures[0].gate == "denylist"
        assert "line 3" in failures[0].message and "word_examples u1" in failures[0].message
        # The log names the term by its line, never by the term.
        assert "zebrastadt" not in failures[0].message.casefold()

    def test_628_a_clean_course_passes(self, database, tmp_path):
        assert self.check(database, "Giraffenhausen\n", tmp_path) == []

    def test_628_verify_runs_the_gate(self, tmp_path, monkeypatch):
        import verify_content

        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        course = tmp_path / "course.db"
        build(course, collect(sources, derive(sources)))
        denylist = tmp_path / "denylist.txt"
        denylist.write_text(sources[0].words[0].german + "\n", encoding="utf-8")
        monkeypatch.setattr(verify_content, "DEFAULT_DENYLIST", denylist)
        assert "denylist" in {failure.gate for failure in verify(course)}

    def test_628_no_denylist_skips_the_gate_and_says_so(self, database, tmp_path, capsys):
        connection = sqlite3.connect(database)
        try:
            assert check_no_denylisted_terms(connection, tmp_path / "none.txt") == []
        finally:
            connection.close()
        assert "did not run" in capsys.readouterr().err

    @pytest.mark.skipif(not DEFAULT_DENYLIST.exists(), reason="data/denylist.txt is not in this checkout")
    def test_628_the_shipped_course_has_no_denylisted_term(self):
        failures = verify(REPO / "app" / "assets" / "db" / "content.db")
        assert [f for f in failures if f.gate == "denylist"] == []
