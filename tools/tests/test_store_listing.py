"""docs/05-dev-guide/store-listing.md: each Play text fits Play's limits (#175)."""

from __future__ import annotations

import re
import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from export_site_facts import listing_texts, mock_exam  # noqa: E402

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


def test_translation_is_named_as_hymt2_on_the_phone_175_1235():
    # v1 left translation out (ADR 9); from 1.2.0 Hy-MT2 is an optional
    # download that runs on the phone (ADR 30, #154). Wherever the listing
    # names translation it names Hy-MT2 too, so no text promises a cloud
    # translator.
    for (language, field), text in texts().items():
        low = text.lower()
        if any(word in low for word in ("translat", "অনুবাদ", "tłumacz", "перевод")):
            assert "Hy-MT2" in text, f"{language} {field}"


def test_the_counts_are_abouts_175_631_1176():
    # A content rebuild changes them (#545 dropped a duplicate word). The words
    # are About's (content.drift's contentCounts): words to learn, not the lesson
    # notes and comparisons (#630). CHANGELOG's entries keep their release's count.
    root = LISTING.parents[2]
    # Read-only: a missing asset is an error, not a new empty file (#722).
    db = sqlite3.connect(f"{(root / 'app' / 'assets' / 'db' / 'content.db').as_uri()}?mode=ro", uri=True)
    words = f"{db.execute('select count(*) from words where kind = ?', ('vocab',)).fetchone()[0]:,}"
    topics = str(db.execute("select count(*) from grammar_topics").fetchone()[0])
    steps = db.execute("select count(*) from sublevels").fetchone()[0]
    db.close()
    # BR-EXAM-02's mock exams per step, read as the site's facts read it.
    mocks = mock_exam()[0] * steps
    bangla = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
    listing = texts()
    en = listing[("English (en-US)", "Full description")]
    assert f"{words} words" in en and f"{topics} grammar topics" in en
    bn = listing[("Bangla (bn-BD)", "Full description")]
    assert f"{words.translate(bangla)}টি শব্দ" in bn and f"{topics.translate(bangla)}টি ব্যাকরণ" in bn
    # CLDR's forms (#1194): Polish writes four digits solid, Russian groups
    # them with a no-break space, as the app and sogda.de write it.
    plain = words.replace(",", "")
    pl = listing[("Polish (pl-PL)", "Full description")]
    assert f"{plain} słów" in pl and f"{topics} tematy gramatyczne" in pl
    ru = listing[("Russian (ru-RU)", "Full description")]
    grouped = words.replace(",", " ")
    assert f"{grouped} слов" in ru and f"{topics} грамматические темы" in ru
    assert plain not in ru, "Russian groups the count: «5 069», not «5069»"
    assert words.replace(",", " ") not in ru, "a no-break space, so the count never breaks"
    # The short descriptions state the steps and the mock exams (#1176).
    bn_steps, bn_mocks = str(steps).translate(bangla), str(mocks).translate(bangla)
    for language, phrases in {
        "English (en-US)": (f"{steps} steps", f"{mocks} mock exams"),
        "Bangla (bn-BD)": (f"{bn_steps}টি ধাপ", f"{bn_mocks}টি মক পরীক্ষা"),
        "Polish (pl-PL)": (f"{steps} etapów", f"{mocks} egzaminów próbnych"),
        "Russian (ru-RU)": (f"{steps} этапов", f"{mocks} пробных экзаменов"),
    }.items():
        short = listing[(language, "Short description")]
        assert all(p in short for p in phrases), (language, short)


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


@pytest.mark.parametrize("locale", ["en", "bn", "pl", "ru"])
def test_every_feature_graphic_is_one_play_takes_1200(locale):
    # tools/media/feature_graphic.py renders them; Play wants 1024 x 500, no alpha, under 15 MB.
    path = STORE / "feature-graphic" / f"{locale}.png"
    assert png_header(path) == (1024, 500, 2), f"{locale}: (width, height, colour type), 2 is RGB"
    assert path.stat().st_size < 15 * 1024 * 1024, locale
    assert f"store/feature-graphic/{locale}.png" in LISTING.read_text(encoding="utf-8"), f"{locale}: not linked"


def test_the_title_the_website_and_the_icon_are_the_brand_kits_602_1176():
    listing = texts()
    # "Sogda: " and the phrase people search in each language (#1176).
    assert listing[("English (en-US)", "Title")] == "Sogda: Learn German A1–C2"
    assert listing[("Bangla (bn-BD)", "Title")] == "Sogda: জার্মান ভাষা A1–C2"
    assert listing[("Polish (pl-PL)", "Title")] == "Sogda: niemiecki od zera do C2"
    assert listing[("Russian (ru-RU)", "Title")] == "Sogda: немецкий с нуля до C2"
    for language in LANGUAGES:
        # Their trademarks, and Play's policy on third-party marks: never in a
        # title or a short description, the texts Play searches first.
        for field in ("Title", "Short description"):
            assert not re.search(r"goethe|telc", listing[(language, field)], re.I), (language, field)
    text = LISTING.read_text(encoding="utf-8")
    assert "**Website:** https://sogda.de" in text
    icon = re.search(r"\*\*App icon:\*\* \[`([^`]+)`\]", text)[1]
    assert png_header(LISTING.parents[2] / icon)[:2] == (512, 512), icon
