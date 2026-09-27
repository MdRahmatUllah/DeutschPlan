"""#608: every model download and licence source is pinned to a commit.

A URL on a branch (`resolve/main`) moves when its maker pushes: the pinned
SHA-256 then fails on every phone, and *Retry* fetches the same wrong file
again until an app update ships. A commit never moves.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from licences import SOURCES  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "app" / "assets" / "models" / "manifest.json"
COMMIT = r"[0-9a-f]{40}"
PINNED = (
    re.compile(rf"^https://huggingface\.co/[^/]+/[^/]+/resolve/{COMMIT}/"),
    re.compile(rf"^https://raw\.githubusercontent\.com/[^/]+/[^/]+/{COMMIT}/"),
)


def _urls(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "url":
                yield value
            else:
                yield from _urls(value)
    elif isinstance(node, list):
        for value in node:
            yield from _urls(value)


def _pinned(url: str) -> bool:
    return any(pattern.match(url) for pattern in PINNED)


def test_every_model_file_is_downloaded_from_a_commit():
    urls = list(_urls(json.loads(MANIFEST.read_text(encoding="utf-8"))))
    assert len(urls) >= 10
    assert [url for url in urls if not _pinned(url)] == []


def test_every_licence_is_checked_against_a_commit():
    assert [url for url in SOURCES.values() if not _pinned(url)] == []


def test_a_branch_url_is_refused():
    assert not _pinned("https://huggingface.co/Supertone/supertonic-3/resolve/main/onnx/vocoder.onnx")
    assert not _pinned("https://raw.githubusercontent.com/google/fonts/main/ofl/inter/OFL.txt")
