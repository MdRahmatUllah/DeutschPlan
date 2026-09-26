"""docs/05-dev-guide/store-listing.md: each Play text fits Play's limits (#175)."""

from __future__ import annotations

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
