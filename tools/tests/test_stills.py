"""#1205: stills.py fills every template in every format and language from
brand.json and reviewed copy, and leaves no placeholder on an image."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "media"))

import stills  # noqa: E402
from brand import BRAND, safe_box, size  # noqa: E402

TEMPLATES = sorted(p.stem for p in stills.TEMPLATES.glob("*.html"))
PLACEHOLDER = re.compile(r"\$\{?[A-Za-z_]")


@pytest.mark.parametrize("template", TEMPLATES)
@pytest.mark.parametrize("fmt", stills.FORMATS)
@pytest.mark.parametrize("locale", stills.LOCALES)
def test_every_page_is_filled_at_its_formats_size(template, fmt, locale):
    page = stills.page_html(template, locale, fmt)
    assert not PLACEHOLDER.search(page), "a placeholder reached the page"
    width, height = size(fmt)
    assert f"width:{width}px;height:{height}px" in page
    left, top, right, bottom = safe_box(fmt)
    assert f"left:{left}px;top:{top}px;width:{right - left}px;height:{bottom - top}px" in page
    line_height = BRAND["type"]["line_height"]["bengali" if locale == "bn" else "latin"]
    assert f"line-height:{line_height}" in page


def test_the_copy_is_reviewed_but_for_german_which_says_it_is_a_draft():
    for locale in stills.LOCALES:
        headline, line, draft = stills.copy(locale)
        assert headline and line and "{" not in headline + line, locale
        assert draft == (locale not in stills.FACTS["listing"]), locale
    # The listing's own numbers, as written, never retyped.
    assert stills.copy("en")[1] == stills.FACTS["listing"]["en"]["short"]


def test_every_language_has_its_play_set_with_every_shot():
    assert set(stills.SETS) == set(stills.LOCALES)
    shots = {p.name for p in (stills.STORE / "phone-light").glob("*.png")}
    assert "01-today.png" in shots
    for locale, folder in stills.SETS.items():
        assert shots <= {p.name for p in (stills.STORE / folder).glob("*.png")}, locale


def test_png_size_reads_the_header():
    png = (stills.STORE / "phone-light" / "01-today.png").read_bytes()
    assert stills.png_size(png) == (1080, 2160)


def test_renders_never_go_to_main():
    assert stills.MEDIA == ROOT.parent / "dp-media"
