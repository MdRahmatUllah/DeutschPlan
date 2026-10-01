"""docs/05-dev-guide/store-listing.md: each Play text fits Play's limits (#175)."""

from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from export_site_facts import listing_texts  # noqa: E402

LISTING = Path(__file__).resolve().parents[2] / "docs" / "05-dev-guide" / "store-listing.md"
PUBSPEC = LISTING.parents[2] / "app" / "pubspec.yaml"
# The release's version: What's new is always the one being released.
VERSION = re.search(r"^version: (\d+\.\d+\.\d+)", PUBSPEC.read_text(encoding="utf-8"), re.M)[1]

# Play Console's limits, in characters.
LIMITS = {
    "Title": 30,
    "Short description": 80,
    "Full description": 4000,
    f"What's new ({VERSION})": 500,
}


def texts() -> dict[tuple[str, str], str]:
    """(language, field) -> the text under its heading (the site's facts read it too, #1174)."""
    return listing_texts(LISTING)


LANGUAGES = ["English (en-US)", "Bangla (bn-BD)", "Polish (pl-PL)", "Russian (ru-RU)"]


@pytest.mark.parametrize("language", LANGUAGES)
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
        assert "tłumacz" not in text.lower(), f"{language} {field}"
        assert "перевод" not in text.lower(), f"{language} {field}"


def test_the_counts_are_abouts_175_631():
    # A content rebuild changes them (#545 dropped a duplicate word). The words
    # are About's (content.drift's contentCounts): words to learn, not the lesson
    # notes and comparisons (#630). CHANGELOG's entries keep their release's count.
    root = LISTING.parents[2]
    # Read-only: a missing asset is an error, not a new empty file (#722).
    db = sqlite3.connect(f"{(root / 'app' / 'assets' / 'db' / 'content.db').as_uri()}?mode=ro", uri=True)
    words = f"{db.execute('select count(*) from words where kind = ?', ('vocab',)).fetchone()[0]:,}"
    topics = str(db.execute("select count(*) from grammar_topics").fetchone()[0])
    db.close()
    bangla = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
    listing = texts()
    en = listing[("English (en-US)", "Full description")]
    assert f"{words} words" in en and f"{topics} grammar topics" in en
    bn = listing[("Bangla (bn-BD)", "Full description")]
    assert f"{words.translate(bangla)}টি শব্দ" in bn and f"{topics.translate(bangla)}টি ব্যাকরণ" in bn
    # Polish and Russian write four digits without a separator (#1143).
    plain = words.replace(",", "")
    pl = listing[("Polish (pl-PL)", "Full description")]
    assert f"{plain} słów" in pl and f"{topics} tematy gramatyczne" in pl
    ru = listing[("Russian (ru-RU)", "Full description")]
    assert f"{plain} слов" in ru and f"{topics} грамматические темы" in ru


STORE = LISTING.parent / "store"
SHOTS = ("01-today", "02-card-front", "03-card-back", "04-course", "05-step", "06-word")


def png_header(path: Path) -> tuple[int, int, int]:
    """(width, height, colour type) from a PNG's IHDR: 2 is RGB, 6 is RGBA."""
    head = path.read_bytes()[:26]
    assert head[:8] == b"\x89PNG\r\n\x1a\n", path
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"), head[25]


@pytest.mark.parametrize(
    "folder", ["phone-light", "phone-dark", "tablet-light", "tablet-dark", "pl-phone-light", "ru-phone-light", "bn-phone-light"]
)
def test_every_screenshot_is_one_play_takes_175(folder):
    for name in SHOTS:
        width, height, colour = png_header(STORE / folder / f"{name}.png")
        assert colour == 2, f"{folder}/{name}: alpha (Play wants RGB)"
        assert 320 <= min(width, height) and max(width, height) <= 3840, f"{folder}/{name}"
        assert max(width, height) <= 2 * min(width, height), f"{folder}/{name}: over 2:1"


def test_the_title_the_website_and_the_icon_are_the_brand_kits_602():
    listing = texts()
    assert listing[("English (en-US)", "Title")] == "Sogda: German A1–C2"
    assert listing[("Bangla (bn-BD)", "Title")] == "Sogda: জার্মান A1–C2"
    assert listing[("Polish (pl-PL)", "Title")] == "Sogda: niemiecki A1–C2"
    assert listing[("Russian (ru-RU)", "Title")] == "Sogda: немецкий A1–C2"
    text = LISTING.read_text(encoding="utf-8")
    assert "**Website:** https://sogda.de" in text
    icon = re.search(r"\*\*App icon:\*\* \[`([^`]+)`\]", text)[1]
    assert png_header(LISTING.parents[2] / icon)[:2] == (512, 512), icon
