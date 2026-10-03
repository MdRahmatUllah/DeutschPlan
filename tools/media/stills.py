"""Branded stills for posts, every format and language, by one command (#1205).

    python tools/media/stills.py screen                    # 4 formats x 5 languages
    python tools/media/stills.py screen --shot 03-card-back.png --locales en,bn --formats square
    python tools/media/stills.py screen --out ../dp-media/2026-10-03-1205-stills   # an issue's folder

A template is `tools/media/templates/<name>.html`, filled by string.Template:
a value it names and isn't given stops the run, so no `$name` ever reaches an
image. Every value comes from `brand.json` through brand.py (the colours, the
type, the frame, each format's safe area), and the words from reviewed copy:
the Play listing's title and short description (`site-facts.json`'s
`listing`, its numbers already the facts, each language's way). German has no
listing, so it takes the promise of messaging.md's (de) audience, said to be
a draft while messaging.md marks it so. The screen is the language's Play set
(`docs/05-dev-guide/store/`), English's for German: the app has no German
interface.

**A card** (`--card <id>`, #1242, #1244) takes its words from `cards.yaml`
instead: a headline and a line per language, where `{word:<uid>}` is a course
word with its article («der Termin»), `{noun:<uid>}` the word alone
(«Termin»), and `{meaning:<uid>}` its meaning in the card's language, all read
from content.db, so no course word or meaning is ever typed.

Renders go to the `media` branch's worktree, never to main: by default
`<root>/dp-media/<yyyy-mm-dd>-stills-<template>/<locale>-<format>.png`; a run
for an issue names its folder as the media README asks, `<yyyy-mm-dd>-<issue>-<slug>`.
Rendered with Playwright's Chromium, as feature_graphic.py.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import html
import io
import json
import re
import sqlite3
import string
import struct
import sys
from pathlib import Path

from brand import BRAND, ROOT, colour, safe_box, size

TEMPLATES = Path(__file__).parent / "templates"
FACTS = json.loads((ROOT / "docs" / "05-dev-guide" / "site-facts.json").read_text(encoding="utf-8"))
MESSAGING = ROOT / "docs" / "marketing" / "messaging.md"
STORE = ROOT / "docs" / "05-dev-guide" / "store"
CARDS = Path(__file__).parent / "cards.yaml"
CONTENT = ROOT / "app" / "assets" / "db" / "content.db"
COURSE = re.compile(r"\{(word|noun|meaning):([0-9a-f]+)\}")
MEDIA = ROOT.parent / "dp-media"
LOCALES = ("en", "de", "bn", "pl", "ru")
FORMATS = ("square", "portrait", "vertical", "landscape")
SETS = {"en": "phone-light", "de": "phone-light", "bn": "bn-phone-light",
        "pl": "pl-phone-light", "ru": "ru-phone-light"}


def copy(locale: str) -> tuple[str, str, bool]:
    """The headline, the line under it, and whether that copy is a draft."""
    if listing := FACTS["listing"].get(locale):
        title = listing["title"].removeprefix("Sogda: ")
        return title[0].upper() + title[1:], listing["short"], False
    # messaging.md: the audience whose heading ends in (locale), its promise.
    text = MESSAGING.read_text(encoding="utf-8")
    block = re.search(rf"^### .*\({locale}\)\n(.*?)(?=^##)", text, re.M | re.S).group(1)
    promise = re.search(r"^- \*\*Promise\*\*( \(\*draft\*\))?: (.+)$", block, re.M)
    head, _, line = promise.group(2).partition(": ")
    return head, line[0].upper() + line[1:], promise.group(1) is not None


def course(kind: str, uid: str, locale: str) -> str:
    """A course word's text from content.db: with its article, alone, or its
    meaning in [locale] (en and bn from `words`, the others from `word_meanings`)."""
    db = sqlite3.connect(f"{CONTENT.as_uri()}?mode=ro", uri=True)
    try:
        row = db.execute("select article, german, english, bangla from words where uid = ?", (uid,)).fetchone()
        if row is None:
            raise SystemExit(f"no course word {uid}")
        article, german, english, bangla = row
        if kind == "word":
            return f"{article} {german}" if article else german
        if kind == "noun":
            return german
        if locale in ("en", "bn"):
            return english if locale == "en" else bangla
        meaning = db.execute("select meaning from word_meanings where word_uid = ? and lang = ?", (uid, locale)).fetchone()
        if meaning is None:
            raise SystemExit(f"{uid} has no {locale} meaning")
        return meaning[0]
    finally:
        db.close()


def card_copy(card: str, locale: str) -> tuple[str, str]:
    """A card's headline and line in [locale], its course words filled from content.db."""
    import yaml
    cards = yaml.safe_load(CARDS.read_text(encoding="utf-8"))
    if card not in cards:
        raise SystemExit(f"no card {card!r} in cards.yaml")
    text = cards[card]["text"].get(locale)
    if text is None:
        raise SystemExit(f"card {card!r} has no {locale}")
    fill = lambda t: COURSE.sub(lambda m: course(m.group(1), m.group(2), locale), t)  # noqa: E731
    headline, line = fill(text["headline"]), fill(text["line"])
    if "{" in headline + line:
        raise SystemExit(f"card {card!r} ({locale}): a token isn't a course word")
    return headline, line


def card_locales(card: str) -> list[str]:
    import yaml
    return list(yaml.safe_load(CARDS.read_text(encoding="utf-8"))[card]["text"])


def _base64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def page_html(template: str, locale: str, fmt: str, shot: str = "01-today.png", card: str | None = None) -> str:
    """The template filled for one language in one format: the listing's copy, or a card's."""
    width, height = size(fmt)
    left, top, right, bottom = safe_box(fmt)
    sizes, kind, frame = BRAND["type"]["sizes"][fmt], BRAND["type"], BRAND["frame"]
    headline, line = card_copy(card, locale) if card else copy(locale)[:2]
    lockup = (ROOT / frame["logo"]["light"]).read_text(encoding="utf-8")
    values = {
        "lang": locale,
        "inter": _base64(ROOT / kind["fonts"]["Inter"]),
        "bengali": _base64(ROOT / kind["fonts"]["Noto Sans Bengali"]),
        "width": width,
        "height": height,
        "left": left,
        "top": top,
        "safe_width": right - left,
        "safe_height": bottom - top,
        # Wide: the words beside the screen; otherwise above it.
        "direction": "row" if width > height else "column",
        "copy_flex": "1 1 0" if width > height else "0 0 auto",
        "gap": sizes["caption"],
        "ground": colour("lagoon"),
        "ink": colour("ink"),
        # The lockup sizes itself by its viewBox once its own size goes.
        "logo": re.sub(r' width="[\d.]+" height="[\d.]+"', "", lockup, count=1),
        "logo_width": round((right - left) * frame["logo"]["width"]),
        "radius": frame["radius"],
        "shadow": frame["shadow"],
        "border": frame["border"],
        "headline": sizes["headline"],
        "headline_weight": kind["weights"]["headline"],
        "headline_tracking": kind["tracking"]["headline"],
        "body": sizes["body"],
        "body_weight": kind["weights"]["body"],
        "line_height": kind["line_height"]["bengali" if locale == "bn" else "latin"],
        # A level range never breaks at its dash («A1–» / «C2»), as on the feature graphic.
        "headline_text": re.sub(r"(\w+–\w+)", r'<span style="white-space:nowrap">\1</span>', html.escape(headline)),
        # «A1 to C2» («A1 থেকে C2») stays on one line, and the last word never stands alone.
        "body_text": re.sub(r" (\S+)$", r"&nbsp;\1", re.sub(
            r"\b([ABC][12]) (\S{1,6}) ([ABC][12])\b", r"\1&nbsp;\2&nbsp;\3", html.escape(line))),
        "screen": _base64(STORE / SETS[locale] / shot),
    }
    page = (TEMPLATES / f"{template}.html").read_text(encoding="utf-8")
    return string.Template(page).substitute(values)


def png_size(png: bytes) -> tuple[int, int]:
    """A PNG's width and height, from its header."""
    width, height = struct.unpack(">II", png[16:24])
    return width, height


def render(template: str, locales: list[str], formats: list[str], shot: str, out: Path, card: str | None = None) -> None:
    from PIL import Image
    from playwright.sync_api import sync_playwright

    out.mkdir(parents=True, exist_ok=True)
    for locale in [] if card else locales:
        if copy(locale)[2]:
            print(f"{locale}: the copy is a draft in messaging.md; not for use until reviewed")
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for fmt in formats:
            width, height = size(fmt)
            page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=1)
            for locale in locales:
                page.set_content(page_html(template, locale, fmt, shot, card))
                page.evaluate("document.fonts.ready")
                buffer = io.BytesIO()
                Image.open(io.BytesIO(page.screenshot())).convert("RGB").save(buffer, "PNG", optimize=True)
                png = buffer.getvalue()
                if png_size(png) != (width, height):
                    raise SystemExit(f"{locale}-{fmt}: {png_size(png)}, not {width} x {height}")
                name = f"{card}-{locale}-{fmt}.png" if card else f"{locale}-{fmt}.png"
                (out / name).write_bytes(png)
                print(f"{out.name}/{name}")
            page.close()
        browser.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("template", help="a name in tools/media/templates/")
    parser.add_argument("--shot", default="01-today.png", help="a file of the Play sets")
    parser.add_argument("--locales", default=",".join(LOCALES))
    parser.add_argument("--formats", default=",".join(FORMATS))
    parser.add_argument("--out", type=Path, help="default: the media worktree's dated folder")
    parser.add_argument("--card", help="a card in cards.yaml (its own languages, unless --locales says)")
    args = parser.parse_args()
    out = args.out or MEDIA / f"{datetime.date.today():%Y-%m-%d}-stills-{args.template}"
    locales = args.locales.split(",")
    if args.card and args.locales == ",".join(LOCALES):
        locales = card_locales(args.card)
    render(args.template, locales, args.formats.split(","), args.shot, out, args.card)


if __name__ == "__main__":
    sys.exit(main())
