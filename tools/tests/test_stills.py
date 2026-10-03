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



@pytest.mark.parametrize("card", sorted(__import__("yaml").safe_load(stills.CARDS.read_text(encoding="utf-8"))))
def test_every_card_fills_its_course_words_in_each_of_its_languages_1244(card):
    for locale in stills.card_locales(card):
        headline, line = stills.card_copy(card, locale)
        assert headline and line and "{" not in headline + line, (card, locale)


def test_a_card_takes_its_words_and_meaning_from_the_course_1244():
    import sqlite3
    db = sqlite3.connect(f"{stills.CONTENT.as_uri()}?mode=ro", uri=True)
    meaning = db.execute("select meaning from word_meanings where word_uid = ? and lang = 'ru'", ("4a51e6804d593c0b",)).fetchone()[0]
    article, german = db.execute("select article, german from words where uid = ?", ("4a51e6804d593c0b",)).fetchone()
    db.close()
    headline, line = stills.card_copy("termin-ru", "ru")
    assert headline.startswith(f"{article} {german} ") and line.endswith(meaning)
    page = stills.page_html("card", "ru", "square", card="termin-ru")
    assert "«термин»" in page and meaning in page.replace("&nbsp;", " ")  # as it reads


def test_a_card_with_a_word_the_course_lacks_is_refused_1244(tmp_path, monkeypatch):
    (tmp_path / "cards.yaml").write_text("bad:\n  text:\n    en:\n      headline: '{word:ffffffffffffffff}'\n      line: x\n", encoding="utf-8")
    monkeypatch.setattr(stills, "CARDS", tmp_path / "cards.yaml")
    with pytest.raises(SystemExit):
        stills.card_copy("bad", "en")


def test_a_card_with_a_malformed_token_is_refused_1244(tmp_path, monkeypatch):
    (tmp_path / "cards.yaml").write_text("bad:\n  text:\n    en:\n      headline: '{word:Termin}'\n      line: x\n", encoding="utf-8")
    monkeypatch.setattr(stills, "CARDS", tmp_path / "cards.yaml")
    with pytest.raises(SystemExit):
        stills.card_copy("bad", "en")


def test_a_level_range_never_breaks_at_its_dash_1240():
    page = stills.page_html("banner", "en", "facebook_cover")
    assert '<span style="white-space:nowrap">A1–C2</span>' in page


def test_a_level_range_and_the_last_word_stay_together_in_the_body_1240():
    page = stills.page_html("banner", "bn", "facebook_cover")
    assert "A1&nbsp;থেকে&nbsp;C2" in page
    body = page.split("<p>", 1)[1].split("</p>", 1)[0]
    assert "&nbsp;" in body.rsplit(" ", 1)[-1] or body.count(" ") == 0
