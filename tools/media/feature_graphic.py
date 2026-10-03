"""Play's feature graphic, 1024 x 500, one per listing language (#1200).

On full-bleed Lagoon: the brand kit's wordmark and, under it, the listing's
title without its "Sogda: " (the wordmark says Sogda), read from
store-listing.md; beside them, the listing's own card back from its Play set,
the screen that shows Sogda best. No tiles: Play advises against branding that
repeats the icon shown next to the graphic (#1323). A title change is one re-run:

    python tools/media/feature_graphic.py   # writes docs/05-dev-guide/store/feature-graphic/<locale>.png

Rendered with Playwright's Chromium (`pip install playwright && playwright
install chromium`, as tools/render_design.py), flattened to RGB with Pillow:
Play takes no alpha. test_store_listing.py checks the files.
"""

from __future__ import annotations

import base64
import io
import re
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from export_site_facts import LISTING, listing_texts  # noqa: E402

from brand import BRAND, colour, size  # noqa: E402  # #1209: the one place

OUT = LISTING.parent / "store" / "feature-graphic"
KIT = ROOT / "docs" / "sogda-brand-kit"
FONTS = ROOT / "app" / "assets" / "fonts"
LOCALES = {"en": "English (en-US)", "bn": "Bangla (bn-BD)", "pl": "Polish (pl-PL)", "ru": "Russian (ru-RU)"}
WIDTH, HEIGHT = size("feature")
FRAME, TYPE = BRAND["frame"], BRAND["type"]


def font(name: str) -> str:
    return base64.b64encode((FONTS / name).read_bytes()).decode()


# Each listing's own Play set (store-listing.md, Screenshots).
SETS = {"en": "phone-light", "bn": "bn-phone-light", "pl": "pl-phone-light", "ru": "ru-phone-light"}


def wordmark() -> str:
    """The kit's Ink wordmark, the name alone (#1323: not the icon's tiles).
    Its viewBox starts 10 units left of the S: at 300 px wide that's 8 px,
    which the page takes back so the S lines up with the title."""
    svg = (KIT / "svg" / "wordmark-ink.svg").read_text(encoding="utf-8")
    sized = re.sub(r' width="[^"]+" height="[^"]+"', ' width="300"', svg, count=1)
    assert sized != svg, "the kit's wordmark changed: check its size"
    return sized


def screen(locale: str) -> str:
    return base64.b64encode((LISTING.parent / "store" / SETS[locale] / "03-card-back.png").read_bytes()).decode()


def page_html(title: str, lang: str) -> str:
    title = title.replace("&", "&amp;").replace("<", "&lt;")
    # A level range never breaks at its dash: «A1–» / «C2» on two lines reads badly.
    title = re.sub(r"(\w+–\w+)", r'<span class="nb">\1</span>', title)
    # A short last word stays with the one before it: «do C2», never a lone «C2».
    title = re.sub(r" (?=[^ ]{1,3}$)", "&nbsp;", title)
    # Everything sits in the middle (Play crops the edges in some placements).
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>
@font-face{{font-family:Inter;src:url(data:font/ttf;base64,{font("Inter-Variable.ttf")});font-weight:100 900}}
@font-face{{font-family:Bengali;src:url(data:font/ttf;base64,{font("NotoSansBengali-Variable.ttf")});font-weight:100 900}}
*{{margin:0}}
body{{width:{WIDTH}px;height:{HEIGHT}px;background:{colour("lagoon")};color:{colour("ink")};font-family:Inter,Bengali,sans-serif;
display:flex;align-items:center;justify-content:center;gap:56px;overflow:hidden}}
.copy{{display:flex;flex-direction:column;gap:22px;width:460px}}
.nb{{white-space:nowrap}}
svg{{display:block;margin-left:-8px}}
h1{{font-size:{TYPE["sizes"]["feature"]["title"]}px;font-weight:{TYPE["weights"]["title"]};letter-spacing:{TYPE["tracking"]["title"]}em;line-height:1.15}}
img{{display:block;height:400px;border:{FRAME["border"]}px solid {colour("ink")};border-radius:{FRAME["radius"]}px;box-shadow:{FRAME["shadow"]}px {FRAME["shadow"]}px 0 {colour("ink")}}}
</style></head><body><div class="copy">{wordmark()}<h1>{title}</h1></div>
<img alt="" src="data:image/png;base64,{screen(lang)}"></body></html>"""


def rgb_png(png: bytes) -> bytes:
    out = io.BytesIO()
    Image.open(io.BytesIO(png)).convert("RGB").save(out, "PNG", optimize=True)
    return out.getvalue()


def main() -> None:
    texts = listing_texts(LISTING)
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": WIDTH, "height": HEIGHT}, device_scale_factor=1)
        for locale, language in LOCALES.items():
            title = texts[(language, "Title")].removeprefix("Sogda: ")
            title = title[0].upper() + title[1:]  # a line of its own: «Niemiecki od zera do C2»
            page.set_content(page_html(title, locale))
            page.evaluate("document.fonts.ready")
            (OUT / f"{locale}.png").write_bytes(rgb_png(page.screenshot()))
            print(f"{locale}: {title}")
        browser.close()


if __name__ == "__main__":
    main()
