"""A calendar week's post drafts and its due-list, from the plan's own files (#1207).

    python tools/media/posts.py --week -3 --monday 2026-10-05
    python tools/media/posts.py --week launch --monday 2026-11-02 --due   # the due-list only

`--week` names a section of docs/marketing/calendar.md: -3, -2, -1, launch or
rhythm (weeks 2 to 6), or an update, 1.2.0, whose drafts come from its own
section of messaging.md. `--monday` is the real week's Monday: it names the file,
`docs/marketing/posts/<yyyy>-<ww>.md` (ISO week), and heads it. The calendar's
days stay as it writes them (T0, L−14): only the owner knows when T0 and L are.

Each row is the owner's to do, in the due-list. A row with languages also gets
a draft per language, from messaging.md's block for that language's audience:
its promise (in the language), its proof points and its call to action. Every
`{token}` is filled from site-facts.json, each number written the way the
language writes it (bn in Bangla digits, de 5.069, ru 5 069 with a no-break
space, pl 5069, en 5,069), so no number is ever typed. A promise messaging.md
marks *draft* says so.

Nothing is posted or sent: the owner reviews, posts, and approves. The
due-list goes to the board by hand (`team.py msg agent-0 --kind report`).
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARKETING = ROOT / "docs" / "marketing"
POSTS = MARKETING / "posts"
FACTS = json.loads((ROOT / "docs" / "05-dev-guide" / "site-facts.json").read_text(encoding="utf-8"))
WEEKS = {"-3": "Week −3", "-2": "Week −2", "-1": "Week −1", "launch": "Launch week", "rhythm": "Weeks 2 to 6",
         "1.2.0": "v1.2.0: what's new"}
# An update's weeks take their audiences from its own section of messaging.md (#1236).
UPDATES = {"1.2.0": "## What's new in 1.2.0"}
LANGS = ("en", "de", "bn", "pl", "ru")
TOKEN = re.compile(r"\{([a-z_]+(?:\.\w+)+)\}")
BANGLA_DIGITS = str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")
NBSP = " "


def number(n: int, lang: str) -> str:
    """[n] as [lang] writes it (messaging.md, #1194)."""
    grouped = f"{n:,}"
    if lang == "bn":
        return grouped.translate(BANGLA_DIGITS)
    if lang == "de":
        return grouped.replace(",", ".")
    if lang == "ru":
        return grouped.replace(",", NBSP)
    if lang == "pl":
        return str(n) if n < 10000 else grouped.replace(",", NBSP)
    return grouped


def fact(path: str):
    value = FACTS
    for key in path.split("."):
        value = value[int(key)] if isinstance(value, list) else value[key]
    return value


def fill(text: str, lang: str) -> str:
    """Every `{token}` filled from site-facts.json, numbers in [lang]'s way."""
    def one(m: re.Match) -> str:
        value = fact(m.group(1))
        return number(value, lang) if isinstance(value, int) and not isinstance(value, bool) else str(value)

    return TOKEN.sub(one, text)


def section(markdown: str, heading: str) -> str:
    """The calendar section whose `###` heading starts with [heading]."""
    m = re.search(rf"^### {re.escape(heading)}.*?\n(.*?)(?=^##)", markdown + "\n##", re.M | re.S)
    if not m:
        raise SystemExit(f"calendar.md has no section «{heading}»")
    return m.group(0)


def rows(text: str) -> list[dict[str, str]]:
    """A Markdown table's rows, keyed by the header's first words (Day, Time, …)."""
    lines = [line for line in text.splitlines() if line.startswith("|")]
    if len(lines) < 3:
        return []
    cells = lambda line: [c.strip() for c in line.strip().strip("|").split("|")]  # noqa: E731
    header = [h.split(" ")[0] for h in cells(lines[0])]
    return [dict(zip(header, cells(line))) for line in lines[2:]]


def audience(messaging: str, lang: str) -> dict[str, str | bool | list[str]]:
    """messaging.md's block for [lang]: the first audience whose heading's
    brackets start with it, «(bn)», «(bn, or en …)»."""
    m = re.search(rf"^### (\d+\. [^\n]*?)\({lang}\b[^)]*\)\n(.*?)(?=^##)", messaging + "\n##", re.M | re.S)
    if not m:
        raise SystemExit(f"messaging.md has no audience for {lang}")
    block = m.group(2)
    # «**Promise:**» reviewed, «**Promise** (*draft*):» not yet.
    promise = re.search(r"^- \*\*Promise(?::\*\*|\*\*( \(\*draft\*\))?:) (.+)$", block, re.M)
    proof = re.search(r"^- \*\*Proof:\*\*\n((?:  \d+\. .+\n?)+)", block, re.M)
    action = re.search(r"^- \*\*Call to action:\*\* (.+)$", block, re.M)
    return {
        "name": m.group(1).strip(),
        "promise": promise.group(2),
        "draft": promise.group(1) is not None,
        "proof": [re.sub(r"^\s*\d+\. ", "", p) for p in proof.group(1).splitlines()] if proof else [],
        "action": action.group(1) if action else "",
    }


def week_file(monday: datetime.date) -> Path:
    year, week, _ = monday.isocalendar()
    return POSTS / f"{year}-{week:02d}.md"


def drafts(week: str, monday: datetime.date) -> tuple[str, list[str]]:
    """The week's file and its due-list."""
    calendar = (MARKETING / "calendar.md").read_text(encoding="utf-8")
    messaging = (MARKETING / "messaging.md").read_text(encoding="utf-8")
    if week in UPDATES:
        messaging = messaging[messaging.index(UPDATES[week]):]
    heading = WEEKS[week]
    table = rows(section(calendar, heading))
    year, number_, _ = monday.isocalendar()
    due = [
        f"- [ ] {r.get('Day', '')} · {r.get('Time', '')} · {r.get('Channel', '')} · "
        f"{r.get('Lang', '')}: {r.get('What', '')} ({r.get('Asset', '')})"
        for r in table
    ]
    out = [
        f"<!-- python tools/media/posts.py --week {week} --monday {monday.isoformat()} -->",
        f"# Posts for {year}-W{number_:02d}: calendar.md's «{heading}»",
        "",
        f"*Week of Monday {monday.isoformat()}. Made by `tools/media/posts.py` from `calendar.md` and "
        "`messaging.md`, with `site-facts.json`'s numbers. Nothing here is posted: the owner reviews, "
        "posts and approves. The days are the calendar's own (T0, L−14), until the owner sets them.*",
        "",
        "## Due this week: the owner's actions",
        "",
        *due,
        "",
        "## Drafts",
    ]
    for r in table:
        langs = [lang for lang in re.findall(r"\b([a-z]{2})\b", r.get("Lang", "")) if lang in LANGS]
        for lang in dict.fromkeys(langs):
            a = audience(messaging, lang)
            out += [
                "",
                f"### {r.get('Day', '')} · {r.get('Channel', '')} · {lang}",
                "",
                f"**What:** {r.get('What', '')}  ",
                f"**When:** {r.get('Time', '') or '—'} · **Asset:** {r.get('Asset', '') or '—'} · "
                f"**Audience:** messaging.md, {a['name']}",
                "",
                f"> {fill(a['promise'], lang)}",
                "",
                *(["*The promise is still a draft in messaging.md: it needs its native review first.*", ""]
                  if a["draft"] else []),
                "Proof to use:",
                *[f"- {fill(p, lang)}" for p in a["proof"]],
                "",
                f"Call to action: {fill(a['action'], lang)}",
            ]
    return "\n".join(out) + "\n", due


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--week", required=True, choices=list(WEEKS))
    parser.add_argument("--monday", required=True, type=datetime.date.fromisoformat)
    parser.add_argument("--due", action="store_true", help="print the due-list only; write nothing")
    args = parser.parse_args()
    if args.monday.weekday() != 0:
        raise SystemExit(f"{args.monday} is not a Monday")
    text, due = drafts(args.week, args.monday)
    if args.due:
        print("\n".join(due))
        return
    path = week_file(args.monday)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    print(f"{path.relative_to(ROOT).as_posix()}: {len(due)} rows")


if __name__ == "__main__":
    sys.exit(main())
