"""PIPE-07: content_manifest.json, and the diff between two builds.

content.db carries `content_version`, but nothing in it can say *what* changed
— only the previous build's uid list can, and once the file is replaced that
list is gone. So the manifest is written beside the database and kept.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from content_manifest import (  # noqa: E402
    MANIFEST_FORMAT,
    ManifestFormatError,
    build_manifest,
    diff,
    main,
    read_manifest,
    write_manifest,
)
from excel_to_sqlite import collect, derive, read_workbook  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402


@pytest.fixture
def built(tmp_path):
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    splits = derive(sources)
    return collect(sources, splits), splits


def manifest_of(version: str, words: dict[str, str]) -> dict:
    return {
        "format": MANIFEST_FORMAT,
        "content_version": version,
        "words": words,
    }


class TestContents:
    def test_it_carries_everything_the_issue_names(self, built):
        manifest = build_manifest(*built)
        assert set(manifest) == {
            "format",
            "content_version",
            "built_at",
            "sources",
            "counts",
            "steps",
            "boundaries",
            "words",
            "grammar",
        }

    def test_the_counts_match_the_build(self, built):
        inputs, _ = built
        manifest = build_manifest(*built)
        assert manifest["counts"]["words"] == len(inputs.words)
        assert manifest["counts"]["grammar"] == len(inputs.grammar)
        assert len(manifest["words"]) == len(inputs.words)

    def test_the_per_step_counts_add_up(self, built):
        manifest = build_manifest(*built)
        assert sum(s["words"] for s in manifest["steps"].values()) == (
            manifest["counts"]["words"]
        )
        assert sum(s["grammar"] for s in manifest["steps"].values()) == (
            manifest["counts"]["grammar"]
        )

    def test_the_boundaries_name_the_step_that_starts(self, built):
        manifest = build_manifest(*built)
        assert manifest["boundaries"]
        assert all(code.endswith(".2") for code in manifest["boundaries"])

    def test_two_builds_of_unchanged_content_are_byte_identical(
        self, built, tmp_path
    ):
        # Byte-identical is what makes `git diff` on the manifest the content
        # diff, rather than a wall of reordered lines.
        inputs, splits = built
        first, second = tmp_path / "a.json", tmp_path / "b.json"
        write_manifest(first, build_manifest(inputs, splits))
        write_manifest(second, build_manifest(inputs, splits))
        assert first.read_bytes() == second.read_bytes()


class TestDiff:
    def base(self) -> dict:
        return manifest_of("202601010000", {"a": "1", "b": "2", "c": "3"})

    def test_nothing_changed(self):
        result = diff(self.base(), manifest_of("202602020000", {"a": "1", "b": "2", "c": "3"}))
        assert result.is_empty
        assert "no content change" in result.summary()

    def test_added_removed_and_changed(self):
        after = manifest_of("202602020000", {"a": "1", "b": "CHANGED", "d": "4"})
        result = diff(self.base(), after)
        assert result.added == ["d"]
        assert result.removed == ["c"]
        assert result.changed == ["b"]
        assert not result.is_empty

    def test_the_summary_names_both_versions(self):
        text = diff(self.base(), manifest_of("202602020000", {"a": "9"})).summary()
        assert "202601010000" in text and "202602020000" in text

    def test_a_format_change_refuses_rather_than_reporting_everything(self):
        # Comparing across formats would report every word as removed, and the
        # app would tell the learner their whole course was replaced.
        old = {**self.base(), "format": 0}
        with pytest.raises(ManifestFormatError, match="every word as removed"):
            diff(old, self.base())


class TestGrammarIsTrackedToo:
    """`grammar_state.grammar_uid` points at these, so a topic that vanishes
    between builds orphans that learner's scheduling for it."""

    def built(self, tmp_path, mutate=None):
        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        splits = derive(sources)
        inputs = collect(sources, splits)
        if mutate:
            mutate(inputs)
        return build_manifest(inputs, splits)

    def test_every_topic_is_in_the_manifest(self, tmp_path):
        manifest = self.built(tmp_path)
        assert len(manifest["grammar"]) == manifest["counts"]["grammar"]

    def test_a_removed_topic_is_reported(self, tmp_path):
        before = self.built(tmp_path)
        after = self.built(tmp_path, lambda i: i.grammar.pop(0))
        result = diff(before, after)
        assert len(result.grammar_removed) == 1
        assert not result.is_empty

    def test_a_changed_rule_is_reported(self, tmp_path):
        before = self.built(tmp_path)
        after = self.built(
            tmp_path, lambda i: setattr(i.grammar[0], "rule", "a new rule")
        )
        assert len(diff(before, after).grammar_changed) == 1

    def test_the_summary_mentions_grammar_only_when_it_moved(self, tmp_path):
        before = self.built(tmp_path)
        assert "grammar" not in diff(before, self.built(tmp_path)).summary()

        after = self.built(tmp_path, lambda i: i.grammar.pop(0))
        assert "grammar" in diff(before, after).summary()


class TestWhatCountsAsChanged:
    """The digest decides, so what it covers is the definition of "changed"."""

    def build(self, tmp_path, mutate=None):
        write_all(tmp_path)
        sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
        splits = derive(sources)
        inputs = collect(sources, splits)
        if mutate:
            mutate(inputs)
        return build_manifest(inputs, splits)

    def test_the_fields_the_word_screen_shows_all_count(self, tmp_path):
        # word-detail.md renders collocations and the synonym set;
        # categories.md sorts by freq and filters by category. An author
        # rewriting any of them ships a change the update card must mention.
        for field, value in (
            ("collocations", "auf der Straße"),
            ("synonyms_register", "≈ Gasse = narrow street"),
            ("freq", 5),
            ("category", "Reisen"),
        ):
            before = self.build(tmp_path)
            after = self.build(
                tmp_path, lambda i, f=field, v=value: setattr(i.words[0], f, v)
            )
            assert len(diff(before, after).changed) == 1, field

    def test_a_changed_meaning_is_a_change(self, tmp_path):
        before = self.build(tmp_path)
        after = self.build(
            tmp_path, lambda i: setattr(i.words[0], "english", "something else")
        )
        assert len(diff(before, after).changed) == 1

    def test_a_changed_example_is_a_change(self, tmp_path):
        from pipeline_steps import Example

        before = self.build(tmp_path)

        def replace(inputs):
            inputs.words[0].examples = [Example(ord=1, german="Neu.", english="New.")]

        assert len(diff(before, self.build(tmp_path, replace)).changed) == 1

    def test_moving_a_word_to_another_step_is_a_change(self, tmp_path):
        # The learner's plan is built per step, so this one they do see.
        before = self.build(tmp_path)

        def move(inputs):
            inputs.words[0].sublevel_code = "C2.2"

        assert len(diff(before, self.build(tmp_path, move)).changed) == 1

    def test_reordering_the_workbook_is_not_a_change(self, tmp_path):
        # `seq` is deliberately outside the digest. Inserting one word at the
        # top shifts every later one, and reporting five thousand changed
        # words for one insertion would make the update summary useless.
        before = self.build(tmp_path)

        def shift(inputs):
            for word in inputs.words:
                word.seq += 1
                word.seq_in_sublevel += 1

        assert diff(before, self.build(tmp_path, shift)).is_empty


class TestTheCli:
    def write(self, tmp_path, name, version, words):
        path = tmp_path / name
        write_manifest(path, manifest_of(version, words))
        return path

    def test_it_prints_a_summary(self, tmp_path, capsys):
        a = self.write(tmp_path, "a.json", "1", {"x": "1"})
        b = self.write(tmp_path, "b.json", "2", {"x": "1", "y": "2"})
        assert main([str(a), str(b)]) == 0
        assert "1 added" in capsys.readouterr().out

    def test_json_output_is_what_content_updates_stores(self, tmp_path, capsys):
        a = self.write(tmp_path, "a.json", "1", {"x": "1"})
        b = self.write(tmp_path, "b.json", "2", {"y": "2"})
        main([str(a), str(b), "--json"])
        assert json.loads(capsys.readouterr().out) == {
            "added": ["y"],
            "removed": ["x"],
            "changed": [],
            "grammar_added": [],
            "grammar_removed": [],
            "grammar_changed": [],
        }

    def test_a_first_build_has_nothing_to_diff_and_that_is_fine(
        self, tmp_path, capsys
    ):
        # Every learner's first install is this case, and so is the first
        # build in a fresh checkout.
        b = self.write(tmp_path, "b.json", "1", {})
        assert main([str(tmp_path / "missing.json"), str(b)]) == 0
        assert "nothing to diff" in capsys.readouterr().out

    def test_a_format_mismatch_exits_non_zero(self, tmp_path):
        a = tmp_path / "a.json"
        write_manifest(a, {"format": 0, "content_version": "1", "words": {}})
        b = self.write(tmp_path, "b.json", "2", {})
        assert main([str(a), str(b)]) == 1


def test_the_build_writes_it_beside_the_database(tmp_path):
    import yaml

    from excel_to_sqlite import main as build_main

    write_all(tmp_path)
    manifest_yaml = tmp_path / "manifest.yaml"
    manifest_yaml.write_text(
        yaml.safe_dump(
            {"workbooks": [{"file": str(tmp_path / n)} for n in BOOK_LEVELS]}
        ),
        encoding="utf-8",
    )

    out = tmp_path / "build" / "content.db"
    assert build_main(["--manifest", str(manifest_yaml), "--out", str(out)]) == 0

    written = read_manifest(out.parent / "content_manifest.json")
    assert written["counts"]["words"] > 0
    assert written["format"] == MANIFEST_FORMAT


def test_content_dependent_tests_can_read_the_counts(tmp_path):
    """#51: "Content-dependent tests read the manifest instead of hard-coding
    counts."

    This is the mechanism — a test that wants to know how many words a step
    has reads it from here, so adding a fifth workbook does not mean editing
    a number in a dozen places.
    """
    write_all(tmp_path)
    sources = [read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    splits = derive(sources)
    manifest = build_manifest(collect(sources, splits), splits)

    for code, counts in manifest["steps"].items():
        assert counts["words"] > 0, code
    assert manifest["counts"]["words"] == sum(
        s["words"] for s in manifest["steps"].values()
    )
