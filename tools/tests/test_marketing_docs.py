"""docs/marketing/: every fact comes from site-facts.json, never typed (#1203).

A copy names a fact as a token, `{totals.words}`, which the post drafts fill
in per language (#1207), so a content build never leaves a stale number in a
plan or a post.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
MARKETING = ROOT / "docs" / "marketing"
FACTS = json.loads((ROOT / "docs" / "05-dev-guide" / "site-facts.json").read_text(encoding="utf-8"))
DOCS = sorted(MARKETING.rglob("*.md"))
# Research quotes other apps' and channels' numbers (36 points, 182 posts); posts/ are the
# tokens filled by posts.py (#1207), and test_posts.py holds each week to a fresh run, so a
# stale number fails there. Copy is everything else.
COPY = [doc for doc in DOCS if not {"research", "posts"} & set(doc.relative_to(MARKETING).parts)]
# The counts only this course has; 12 and 3 are too common to police.
TYPED = {str(FACTS["totals"][key]): key for key in ("words", "grammar_topics", "mock_exams")}
# A number as any of the five languages writes it: 5069, 5,069, 5.069, 5 069 (nbsp or thin space), ৫,০৬৯.
NUMBER = re.compile(r"\d{1,3}(?:[,.\u00a0\u202f ]\d{3})+(?!\d)|\d+")
BANGLA = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")
TOKEN = re.compile(r"\{([a-z_]+(?:\.\w+)+)\}")


def fact(path: str):
    value = FACTS
    for key in path.split("."):
        value = value[int(key)] if isinstance(value, list) else value[key]
    return value


def test_the_marketing_docs_exist_1203():
    assert DOCS, "docs/marketing has no Markdown"


@pytest.mark.parametrize("doc", COPY, ids=lambda p: p.relative_to(MARKETING).as_posix())
def test_no_fact_is_typed_only_tokens_1203(doc):
    for n, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
        for number in NUMBER.findall(line.translate(BANGLA)):
            plain = re.sub(r"\D", "", number)
            assert plain not in TYPED, f"{doc.name}:{n}: {number} is typed; write {{totals.{TYPED[plain]}}}"


@pytest.mark.parametrize("doc", DOCS, ids=lambda p: p.relative_to(MARKETING).as_posix())
def test_every_token_is_a_fact_1203(doc):
    for n, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
        for path in TOKEN.findall(line):
            try:
                fact(path)
            except (KeyError, IndexError, ValueError, TypeError):
                pytest.fail(f"{doc.name}:{n}: {{{path}}} is not in site-facts.json")
