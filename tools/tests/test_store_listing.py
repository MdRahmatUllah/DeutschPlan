"""docs/05-dev-guide/store-listing.md: each Play text fits Play's limits (#175)."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

LISTING = Path(__file__).resolve().parents[2] / "docs" / "05-dev-guide" / "store-listing.md"

# Play Console's limits, in characters.
LIMITS = {
    "Title": 30,
    "Short description": 80,
    "Full description": 4000,
    "What's new (1.0.0)": 500,
}


def texts() -> dict[tuple[str, str], str]:
    """(language, field) -> the text under its heading."""
    found: dict[tuple[str, str], list[str]] = {}
    language, field = "", ""
    for line in LISTING.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            language, field = line[3:].strip(), ""
        elif line.startswith("### "):
            field = line[4:].strip()
            found[(language, field)] = []
        elif field:
            found[(language, field)].append(line)
    return {key: "\n".join(lines).strip() for key, lines in found.items()}


@pytest.mark.parametrize("language", ["English (en-US)", "Bangla (bn-BD)"])
def test_every_field_is_there_and_fits_plays_limit_175(language):
    listing = texts()
    for field, limit in LIMITS.items():
        text = listing.get((language, field), "")
        assert text, f"{language}: no {field}"
        assert len(text) <= limit, f"{language} {field}: {len(text)} > {limit}"


def test_the_listing_offers_no_translation_which_v1_leaves_out_175():
    # ADR 9: Hy-MT is off in every v1.0 build.
    for (language, field), text in texts().items():
        assert "translat" not in text.lower(), f"{language} {field}"
        assert "অনুবাদ" not in text, f"{language} {field}"


def test_the_counts_are_content_dbs_175():
    # A content rebuild changes them (#545 dropped a duplicate word).
    root = LISTING.parents[2]
    db = sqlite3.connect(root / "app" / "assets" / "db" / "content.db")
    words = f"{db.execute('select count(*) from words').fetchone()[0]:,}"
    topics = str(db.execute("select count(*) from grammar_topics").fetchone()[0])
    db.close()
    bangla = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
    listing = texts()
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    for text in (listing[("English (en-US)", "Full description")], changelog):
        assert f"{words} words" in text and f"{topics} grammar topics" in text
    bn = listing[("Bangla (bn-BD)", "Full description")]
    assert f"{words.translate(bangla)}টি শব্দ" in bn and f"{topics.translate(bangla)}টি ব্যাকরণ" in bn


STORE = LISTING.parent / "store"
SHOTS = ("01-today", "02-card-front", "03-card-back", "04-course", "05-step", "06-word")


def png_header(path: Path) -> tuple[int, int, int]:
    """(width, height, colour type) from a PNG's IHDR: 2 is RGB, 6 is RGBA."""
    head = path.read_bytes()[:26]
    assert head[:8] == b"\x89PNG\r\n\x1a\n", path
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"), head[25]


@pytest.mark.parametrize("folder", ["phone-light", "phone-dark", "tablet-light", "tablet-dark"])
def test_every_screenshot_is_one_play_takes_175(folder):
    for name in SHOTS:
        width, height, colour = png_header(STORE / folder / f"{name}.png")
        assert colour == 2, f"{folder}/{name}: alpha (Play wants RGB)"
        assert 320 <= min(width, height) and max(width, height) <= 3840, f"{folder}/{name}"
        assert max(width, height) <= 2 * min(width, height), f"{folder}/{name}: over 2:1"
