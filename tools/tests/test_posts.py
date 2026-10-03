"""#1207: posts.py makes a week's drafts and due-list from calendar.md and
messaging.md, every number from site-facts.json in its language's way, and
the committed weeks are what it makes today, so a stale number fails here."""

from __future__ import annotations

import datetime
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "media"))

import posts  # noqa: E402

MONDAY = datetime.date(2026, 10, 5)
NBSP = " "


def test_each_language_writes_a_number_its_way():
    assert posts.number(5069, "en") == "5,069"
    assert posts.number(5069, "de") == "5.069"
    assert posts.number(5069, "ru") == f"5{NBSP}069"
    assert posts.number(5069, "pl") == "5069"
    assert posts.number(50690, "pl") == f"50{NBSP}690"
    assert posts.number(5069, "bn") == "৫,০৬৯"


@pytest.mark.parametrize("lang", posts.LANGS)
def test_every_audience_fills_from_the_facts(lang):
    messaging = (posts.MARKETING / "messaging.md").read_text(encoding="utf-8")
    a = posts.audience(messaging, lang)
    for text in [a["promise"], *a["proof"], a["action"]]:
        assert "{" not in posts.fill(text, lang), text
    assert a["promise"] and a["action"]


def test_a_draft_promise_says_so_and_a_reviewed_one_does_not():
    messaging = (posts.MARKETING / "messaging.md").read_text(encoding="utf-8")
    assert posts.audience(messaging, "en")["draft"] is False
    assert posts.audience(messaging, "de")["draft"] is True  # de waits for its review; bn was reviewed (#1252)


@pytest.mark.parametrize("week", list(posts.WEEKS))
def test_every_row_is_due_and_every_language_gets_a_draft(week):
    text, due = posts.drafts(week, MONDAY)
    calendar = (posts.MARKETING / "calendar.md").read_text(encoding="utf-8")
    table = posts.rows(posts.section(calendar, posts.WEEKS[week]))
    assert table and len(due) == len(table)
    for row in table:
        for lang in set(re.findall(r"\b([a-z]{2})\b", row.get("Lang", ""))) & set(posts.LANGS):
            assert f"### {row.get('Day', '')} · {row.get('Channel', '')} · {lang}" in text
    assert "{" not in text.split("## Drafts", 1)[1], "a token reached a draft"
    assert text.startswith(f"<!-- python tools/media/posts.py --week {week} --monday {MONDAY} -->")


def test_the_file_is_named_by_the_iso_week():
    assert posts.week_file(MONDAY).name == "2026-41.md"


@pytest.mark.parametrize("path", sorted(posts.POSTS.glob("*.md")), ids=lambda p: p.name)
def test_a_committed_week_is_what_posts_py_makes_today(path):
    first = path.read_text(encoding="utf-8").splitlines()[0]
    m = re.fullmatch(r"<!-- python tools/media/posts.py --week (\S+) --monday (\S+) -->", first)
    assert m, f"{path.name} doesn't say how it was made"
    text, _ = posts.drafts(m.group(1), datetime.date.fromisoformat(m.group(2)))
    assert path.read_text(encoding="utf-8") == text, f"re-run: {first[5:-4]}"
