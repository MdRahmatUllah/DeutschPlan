"""`tools/plant.py`: a plant is applied, judged and always undone."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import plant  # noqa: E402

# Stands in for `flutter test`: "fails" (exit 1) when the guarded line is gone.
CHECK = [sys.executable, "-c",
         "import sys; t = open('lib/x.dart').read(); ok = 'guard()' in t; "
         "print('All tests passed!' if ok else 'Some tests failed.'); sys.exit(0 if ok else 1)"]


@pytest.fixture()
def app(tmp_path, monkeypatch):
    (tmp_path / "lib").mkdir()
    # write_text gives CRLF on Windows, as the working tree has.
    (tmp_path / "lib" / "x.dart").write_text("void f() {\n  guard();\n}\n", encoding="utf-8")
    monkeypatch.setattr(plant, "APP", tmp_path)
    return tmp_path


def test_a_plant_is_judged_and_the_file_put_back_byte_for_byte(app):
    before = (app / "lib" / "x.dart").read_bytes()
    removed = {"name": "n", "file": "lib/x.dart", "old": "{\n  guard();\n", "new": "{\n"}
    assert plant.plant(removed, [], CHECK) == "CAUGHT"
    assert (app / "lib" / "x.dart").read_bytes() == before
    kept = {"name": "n", "file": "lib/x.dart", "old": "  guard();\n", "new": "  guard(); // keep\n"}
    assert plant.plant(kept, [], CHECK) == "*MISSED*"
    assert (app / "lib" / "x.dart").read_bytes() == before


def test_verdicts():
    assert plant.verdict(0, "00:01 +3: All tests passed!") == "*MISSED*"
    assert plant.verdict(1, "Some tests failed.") == "CAUGHT"
    assert plant.verdict(1, 'Failed to load "x_test.dart": Compilation failed') == "COMPILE?"


def test_685_a_broken_run_is_not_caught():
    # A mistyped test path, no flutter, a locked DLL: flutter exits non-zero
    # without a single test failing. That proves nothing.
    assert plant.verdict(1, "Test file not found: test/typo_test.dart") == "ERROR?"
    assert plant.verdict(127, "flutter is not on PATH") == "ERROR?"
    # A custom command's baseline proved it runs, so its failure counts.
    assert plant.verdict(1, "1 failed", flutter=False) == "CAUGHT"
    # The exit code decides, not flutter's wording: a passing pytest run is
    # a miss though it never says "All tests passed!".
    assert plant.verdict(0, "3 passed in 0.1s", flutter=False) == "*MISSED*"


def test_685_a_timeout_is_indeterminate_not_caught(app):
    sleeper = [sys.executable, "-c", "import time; time.sleep(30)"]
    code, output = plant.run_tests([], sleeper, timeout=1)
    assert (code, output) == (None, "TIMEOUT")
    assert plant.verdict(code, output) == "HUNG?"


def test_685_nothing_is_planted_against_a_red_baseline(app, tmp_path, capsys):
    red = [sys.executable, "-c", "import sys; print('Some tests failed.'); sys.exit(1)"]
    spec = tmp_path / "plants.json"
    spec.write_text(json.dumps({
        "tests": [], "command": red,
        "plants": [{"name": "n", "file": "lib/x.dart", "old": "  guard();\n", "new": ""}],
    }), encoding="utf-8")
    before = (app / "lib" / "x.dart").read_bytes()
    assert plant.main([str(spec)]) == 2
    assert "baseline failed" in capsys.readouterr().out
    assert (app / "lib" / "x.dart").read_bytes() == before


def test_685_only_caught_counts(app, tmp_path, capsys):
    spec = tmp_path / "plants.json"
    spec.write_text(json.dumps({
        "tests": [], "command": CHECK,
        "plants": [
            {"name": "gone", "file": "lib/x.dart", "old": "{\n  guard();\n", "new": "{\n"},
            {"name": "kept", "file": "lib/x.dart", "old": "  guard();\n", "new": "  guard(); // x\n"},
        ],
    }), encoding="utf-8")
    assert plant.main([str(spec)]) == 1
    out = capsys.readouterr().out
    assert "CAUGHT" in out and "*MISSED*" in out and "1 not caught" in out


def test_685_a_skipped_plant_fails_the_run(app, tmp_path, capsys):
    spec = tmp_path / "plants.json"
    spec.write_text(json.dumps({
        "tests": [], "command": CHECK,
        "plants": [{"name": "nowhere", "file": "lib/x.dart", "old": "not in the file", "new": "x"}],
    }), encoding="utf-8")
    assert plant.main([str(spec)]) == 1
    assert "1 not caught" in capsys.readouterr().out


def test_a_snippet_that_is_not_there_exactly_once_is_skipped(app):
    assert plant.plant({"name": "n", "file": "lib/x.dart", "old": "nowhere", "new": "x"}, [], CHECK).startswith("SKIP")


def test_697_kill_own_testers_matches_this_worktree_only():
    # TL-12: `*...\\agent-1*` also matched agent-1-review's testers.
    import fnmatch

    def tester(worktree: str) -> str:
        # A real flutter_tester command line, trimmed.
        return (r"F:\flutter\bin\cache\artifacts\engine\windows-x64\flutter_tester.exe "
                rf"--non-interactive --packages={worktree}\app\.dart_tool\package_config.json "
                rf"--flutter-assets-dir={worktree}\app\build\unit_test_assets C:\Temp\listener.dart.dill")

    pattern = plant.own_pattern(Path("F:/appDevs/dp-wt/agent-1"))
    assert fnmatch.fnmatchcase(tester(r"F:\appDevs\dp-wt\agent-1"), pattern)
    assert not fnmatch.fnmatchcase(tester(r"F:\appDevs\dp-wt\agent-1-review"), pattern)
    # The main checkout holds worktrees of its own under .claude/worktrees/.
    main = plant.own_pattern(Path("F:/appDevs/deutschplan"))
    assert fnmatch.fnmatchcase(tester(r"F:\appDevs\deutschplan"), main)
    assert not fnmatch.fnmatchcase(tester(r"F:\appDevs\deutschplan\.claude\worktrees\agent-a0f"), main)
