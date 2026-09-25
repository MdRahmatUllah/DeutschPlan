"""`tools/licences.py`: M8's texts are their makers', and no package goes
unlisted (#172)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import licences  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def test_every_bundled_text_and_every_one_m8_lists_has_a_source():
    bundled = {path.name for path in licences.LICENCES.glob("*.txt")}
    assert bundled == set(licences.SOURCES)
    screen = (ROOT / "app/lib/features/me/licences_screen.dart").read_text(encoding="utf-8")
    listed = set(re.findall(r"assets/licences/([\w.-]+\.txt)", screen))
    assert listed == set(licences.SOURCES)


def test_a_text_is_stale_when_it_differs_is_missing_or_has_no_source(tmp_path):
    published = {url: f"The text of {name}.\n" for name, url in licences.SOURCES.items()}
    for name, url in licences.SOURCES.items():
        # git's line endings and a trailing blank line are not a difference.
        (tmp_path / name).write_text(published[url].replace("\n", "\r\n") + "\r\n",
                                     encoding="utf-8", newline="")
    assert licences.stale(tmp_path, published.__getitem__) == []

    changed, missing = list(licences.SOURCES)[:2]
    (tmp_path / changed).write_text("An older text.\n", encoding="utf-8")
    (tmp_path / missing).unlink()
    (tmp_path / "Extra.txt").write_text("?\n", encoding="utf-8")
    problems = licences.stale(tmp_path, published.__getitem__)
    assert [p.split(":")[0] for p in problems] == [changed, missing, "Extra.txt"]


def test_update_writes_the_text_as_published(tmp_path):
    licences.update(tmp_path, lambda url: f"{url}\r\n\r\n")
    for name, url in licences.SOURCES.items():
        assert (tmp_path / name).read_bytes() == f"{url}\r\n\r\n".encode()


def test_a_package_without_a_licence_file_is_named(tmp_path):
    hosted, flutter, app = tmp_path / "cache", tmp_path / "flutter", tmp_path / "app"
    for package in ("licensed", "copying", "bare"):
        (hosted / package).mkdir(parents=True)
    (hosted / "licensed" / "LICENSE").write_text("MIT\n", encoding="utf-8")
    (hosted / "copying" / "COPYING.txt").write_text("GPL\n", encoding="utf-8")
    (flutter / "packages" / "flutter_test").mkdir(parents=True)
    (app / ".dart_tool").mkdir(parents=True)
    config = app / ".dart_tool" / "package_config.json"
    config.write_text(json.dumps({
        "flutterRoot": (flutter).as_uri(),
        "packages": [
            *({"name": p, "rootUri": (hosted / p).as_uri()} for p in ("licensed", "copying", "bare")),
            # Covered by the SDK's licence, and ours.
            {"name": "flutter_test", "rootUri": (flutter / "packages" / "flutter_test").as_uri()},
            {"name": "deutschplan", "rootUri": "../"},
        ],
    }), encoding="utf-8")
    assert [p.split(":")[0] for p in licences.unlicensed(config)] == ["bare"]
