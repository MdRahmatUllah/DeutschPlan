"""`tools/plant.py`: a plant is applied, judged and always undone."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import plant  # noqa: E402

# Stands in for `flutter test`: "fails" when the guarded line is gone.
CHECK = [sys.executable, "-c",
         "import sys; t = open('lib/x.dart').read(); "
         "print('All tests passed!' if 'guard()' in t else 'Some tests failed.')"]


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
    assert plant.verdict("00:01 +3: All tests passed!") == "*MISSED*"
    assert plant.verdict("Some tests failed.") == "CAUGHT"
    assert plant.verdict('Failed to load "x_test.dart": Compilation failed') == "COMPILE?"
    assert plant.verdict("TIMEOUT") == "CAUGHT (hung)"


def test_a_snippet_that_is_not_there_exactly_once_is_skipped(app):
    assert plant.plant({"name": "n", "file": "lib/x.dart", "old": "nowhere", "new": "x"}, [], CHECK).startswith("SKIP")
