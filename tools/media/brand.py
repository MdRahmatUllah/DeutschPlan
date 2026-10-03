"""The brand's values for every media tool, from one place (#1209).

    from brand import BRAND, colour, contrast, safe_box

docs/marketing/brand.json holds them (brand.md says why); a tool reads a
colour, a size or a safe area here, never types it.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRAND_JSON = ROOT / "docs" / "marketing" / "brand.json"
BRAND: dict = json.loads(BRAND_JSON.read_text(encoding="utf-8"))


def colour(name: str) -> str:
    """A brand colour's hex, «#00C2B2»."""
    return BRAND["colours"][name]


def size(fmt: str) -> tuple[int, int]:
    """A format's width and height in pixels."""
    width, height = BRAND["formats"][fmt]["size"]
    return width, height


def safe_box(fmt: str) -> tuple[int, int, int, int]:
    """Where text and the logo may go in [fmt]: left, top, right, bottom in
    pixels, from the format's safe fractions."""
    width, height = size(fmt)
    safe = BRAND["formats"][fmt]["safe"]
    return (
        round(width * safe["left"]),
        round(height * safe["top"]),
        round(width * (1 - safe["right"])),
        round(height * (1 - safe["bottom"])),
    )


def _luminance(hex_colour: str) -> float:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    h = hex_colour.lstrip("#")
    r, g, b = (channel(int(h[i : i + 2], 16) / 255) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(text: str, on: str) -> float:
    """WCAG 2's contrast ratio of two brand colours, by name."""
    high, low = sorted((_luminance(colour(text)), _luminance(colour(on))), reverse=True)
    return (high + 0.05) / (low + 0.05)
