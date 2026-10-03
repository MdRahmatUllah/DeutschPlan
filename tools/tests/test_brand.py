"""#1209: brand.json, the one place the media tools read the brand from, held
to its sources (the brand kit, the app's tokens) and to the contrast it
promises; brand.md says the same."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "media"))

from brand import BRAND, contrast, safe_box, size  # noqa: E402

KIT = (ROOT / "docs" / "sogda-brand-kit" / "README.md").read_text(encoding="utf-8")
TOKENS = (ROOT / "app" / "lib" / "core" / "theme" / "sg_tokens.dart").read_text(encoding="utf-8")
DOC = (ROOT / "docs" / "marketing" / "brand.md").read_text(encoding="utf-8")


def test_the_kit_colours_are_the_kits():
    kit = {
        m.group(1).lower(): m.group(2).upper()
        for m in re.finditer(r"^\| (\w+) \([^)]*\) \| (#[0-9A-Fa-f]{6}) \|", KIT, re.M)
    }
    assert set(kit) == {"lagoon", "sun", "ink", "paper", "night"}
    for name, hex_colour in kit.items():
        assert BRAND["colours"][name] == hex_colour, name


def test_the_gender_colours_are_the_apps_light_ones():
    # The light theme comes first in sg_tokens.dart.
    for name, token in {"cobalt": "der", "raspberry": "die", "emerald": "das"}.items():
        app = re.search(rf"\b{token}: Color\(0xFF([0-9A-Fa-f]{{6}})\)", TOKENS).group(1)
        assert BRAND["colours"][name] == f"#{app.upper()}", name


def test_every_pair_passes_wcag_for_its_use():
    for pair in BRAND["pairs"]:
        ratio = contrast(pair["text"], pair["on"])
        need = {"text": 4.5, "large": 3.0}[pair["use"]]
        assert ratio >= need, f"{pair['text']} on {pair['on']}: {ratio:.2f} < {need}"


def test_every_never_pair_fails_even_large_text():
    for pair in BRAND["never"]:
        assert contrast(pair["text"], pair["on"]) < 3.0, pair


def test_every_format_has_a_safe_area_type_and_a_source():
    for fmt, spec in BRAND["formats"].items():
        left, top, right, bottom = safe_box(fmt)
        width, height = size(fmt)
        assert 0 <= left < right <= width and 0 <= top < bottom <= height, fmt
        assert all(0 <= v < 0.5 for v in spec["safe"].values()), fmt
        assert spec["source"], fmt
        assert BRAND["type"]["sizes"][fmt], fmt


def test_safe_box_is_the_fractions_in_pixels():
    # Meta's Reels zone on 1080 x 1920: 6 % sides, 14 % top, 35 % bottom.
    assert safe_box("vertical") == (65, 269, 1015, 1248)


def test_the_files_it_names_exist():
    for path in [*BRAND["type"]["fonts"].values(), BRAND["frame"]["logo"]["light"], BRAND["frame"]["logo"]["dark"]]:
        assert (ROOT / path).is_file(), path


def test_brand_md_says_what_brand_json_holds():
    for name, hex_colour in BRAND["colours"].items():
        assert hex_colour in DOC, f"{name} {hex_colour}"
    for fmt in BRAND["formats"]:
        width, height = size(fmt)
        assert f"{width} × {height}" in DOC, fmt
    for hex_colour in re.findall(r"#[0-9A-F]{6}\b", DOC):
        assert hex_colour in BRAND["colours"].values(), f"{hex_colour} is not a brand colour"
