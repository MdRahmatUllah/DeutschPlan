"""Play's feature graphic, 1024 x 500, one per listing language (#1200).

The brand kit's horizontal lockup on full-bleed Lagoon, and under it the
listing's title without its "Sogda: " (the lockup already says Sogda), read
from store-listing.md, so a title change is one re-run:

    python tools/media/feature_graphic.py   # writes docs/05-dev-guide/store/feature-graphic/<locale>.png

Rendered with Playwright's Chromium (`pip install playwright && playwright
install chromium`, as tools/render_design.py), flattened to RGB with Pillow:
Play takes no alpha. test_store_listing.py checks the files.
"""

from __future__ import annotations

import base64
import io
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


def lockup() -> str:
    """The kit's light lockup, its Paper ground made a card on the Lagoon."""
    svg = (KIT / "svg" / "lockup-horizontal-tiles-light.svg").read_text(encoding="utf-8")
    return svg.replace('width="574" height="190"', 'width="560"', 1)


def page_html(title: str, lang: str) -> str:
    title = title.replace("&", "&amp;").replace("<", "&lt;")
    # Everything sits in the middle: Play crops the edges in some placements.
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>
@font-face{{font-family:Inter;src:url(data:font/ttf;base64,{font("Inter-Variable.ttf")});font-weight:100 900}}
@font-face{{font-family:Bengali;src:url(data:font/ttf;base64,{font("NotoSansBengali-Variable.ttf")});font-weight:100 900}}
*{{margin:0}}
body{{width:{WIDTH}px;height:{HEIGHT}px;background:{colour("lagoon")};color:{colour("ink")};font-family:Inter,Bengali,sans-serif;
display:flex;flex-direction:column;align-items:center;justify-content:center;gap:34px;overflow:hidden}}
svg{{display:block;border-radius:{FRAME["radius"]}px;box-shadow:{FRAME["shadow"]}px {FRAME["shadow"]}px 0 {colour("ink")}}}
h1{{font-size:{TYPE["sizes"]["feature"]["title"]}px;font-weight:{TYPE["weights"]["title"]};letter-spacing:{TYPE["tracking"]["title"]}em;white-space:nowrap}}
</style></head><body>{lockup()}<h1>{title}</h1></body></html>"""


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
