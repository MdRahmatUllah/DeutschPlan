"""`make content`: build, verify, copy.

The Makefile is where the three tools meet, and a broken recipe is a broken
release step. These run the same sequence the target does, so the check is on
the commands rather than on the tab characters — and one test reads the
Makefile itself to make sure the two have not diverged.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import verify_content  # noqa: E402
from excel_to_sqlite import main as build_main  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
MAKEFILE = REPO / "Makefile"


def recipe(target: str) -> list[str]:
    """The command lines of one Makefile target."""
    body = MAKEFILE.read_text(encoding="utf-8").split("\n" + target + ":", 1)
    assert len(body) == 2, f"no {target} target in the Makefile"
    lines = []
    for line in body[1].splitlines()[1:]:
        if not line.startswith("\t"):
            break
        lines.append(line.strip())
    return lines


class TestTheRecipe:
    def test_it_builds_then_verifies_then_copies(self):
        # Order matters: copying before verifying would ship a database the
        # gates reject, and the app would be none the wiser.
        commands = " | ".join(recipe("content"))
        build = commands.index("excel_to_sqlite")
        check = commands.index("verify_content")
        copy = commands.index("cp content/build/content.db")
        assert build < check < copy

    def test_it_copies_the_manifest_beside_the_asset(self):
        # The next build diffs against it to say what changed; leaving it in
        # content/build/ would lose it, since that directory is ignored.
        commands = " ".join(recipe("content"))
        assert "content_manifest.json" in commands

    def test_the_intermediate_is_ignored_and_the_asset_is_not(self):
        ignored = (REPO / ".gitignore").read_text(encoding="utf-8")
        assert "content/build/" in ignored
        assert "assets/db" not in ignored

    def test_content_diff_compares_the_committed_asset(self):
        # Against the shipped manifest, not against another build output —
        # "what changed since what the learner has" is the question.
        commands = " ".join(recipe("content-diff"))
        assert "assets/db/content_manifest.json" in commands
        assert "content/build/content_manifest.json" in commands

    def test_everything_the_recipe_copies_is_a_declared_flutter_asset(self):
        """The one nothing else can catch.

        `make content` can copy the database into `app/assets/db/` all day;
        unless pubspec.yaml declares the directory, Flutter bundles nothing
        and the app throws on the first read. There is no build error — the
        file is simply not there at run time.
        """
        declared = set(
            yaml.safe_load((REPO / "app" / "pubspec.yaml").read_text("utf-8"))[
                "flutter"
            ]["assets"]
        )

        copied = {
            match.group(1)
            for line in recipe("content")
            for match in [re.search(r"\$\(APP\)/(assets/\S+)/[^/\s]+$", line)]
            if match
        }
        assert copied, "the recipe copies nothing into assets/"

        for directory in copied:
            assert f"{directory}/" in declared, (
                f"`make content` copies into {directory}/ and pubspec.yaml "
                f"does not declare it, so the file never ships"
            )

    def test_every_target_in_the_file_is_declared_phony(self):
        text = MAKEFILE.read_text(encoding="utf-8")
        declared = set(
            re.search(r"^\.PHONY:(.*)$", text, re.MULTILINE).group(1).split()
        )
        targets = {
            match.group(1)
            for match in re.finditer(r"^([a-z][a-z-]*):", text, re.MULTILINE)
        }
        assert targets <= declared, f"not .PHONY: {sorted(targets - declared)}"


def test_the_sequence_the_recipe_runs_works_end_to_end(tmp_path, capsys):
    """Build, verify, copy — the same three steps, with the fixtures."""
    write_all(tmp_path)
    manifest_yaml = tmp_path / "manifest.yaml"
    manifest_yaml.write_text(
        yaml.safe_dump(
            {
                "workbooks": [{"file": str(tmp_path / n)} for n in BOOK_LEVELS],
                "tips": str(REPO / "content" / "interference_tips.csv"),
            }
        ),
        encoding="utf-8",
    )

    out = tmp_path / "build" / "content.db"
    assert build_main(["--manifest", str(manifest_yaml), "--out", str(out)]) == 0
    assert verify_content.main(["--db", str(out)]) == 0

    assert out.exists()
    assert (out.parent / "content_manifest.json").exists()


def test_the_build_prints_the_per_step_counts(tmp_path, capsys):
    """#53: "Prints counts per step, uid collisions and verification results"."""
    write_all(tmp_path)
    manifest_yaml = tmp_path / "manifest.yaml"
    manifest_yaml.write_text(
        yaml.safe_dump(
            {"workbooks": [{"file": str(tmp_path / n)} for n in BOOK_LEVELS]}
        ),
        encoding="utf-8",
    )

    build_main(
        ["--manifest", str(manifest_yaml), "--out", str(tmp_path / "c.db")]
    )
    captured = capsys.readouterr()

    assert "A1.1 weeks" in captured.out and "words)" in captured.out
    assert "grammar tags:" in captured.err
