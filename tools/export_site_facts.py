"""sogda.de's facts (#1174): one JSON the website syncs at a pinned commit.

Every number the site states has one source here:
- the counts come from content.db;
- the mock paper's shape comes from the app's exam code and BR-EXAM-02/03;
- the version and the Android floor come from the app's build files;
- the store texts come from store-listing.md.

The site's `pnpm sync:facts` fetches the committed file at an app commit and
commits it as `content/facts.json`, the same way it syncs the screenshots.

    python tools/export_site_facts.py           # writes docs/05-dev-guide/site-facts.json
    python tools/export_site_facts.py --check   # exits 1 if the committed file is stale
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "app" / "assets" / "db" / "content.db"
LISTING = ROOT / "docs" / "05-dev-guide" / "store-listing.md"
OUT = ROOT / "docs" / "05-dev-guide" / "site-facts.json"
EXAM = ROOT / "app" / "lib" / "domain" / "exam_generator.dart"
RULES = ROOT / "docs" / "00-product" / "business-rules.md"
PUBSPEC = ROOT / "app" / "pubspec.yaml"
GRADLE = ROOT / "app" / "android" / "app" / "build.gradle.kts"

SCHEMA = 1
# The sample's order: a hash of this and the word's uid. A new seed reshuffles
# every level page, so change it only on purpose.
SEED = "sogda-site-v1"
SAMPLE = 25  # the owner's O3 default (sogda-website #56)
# The words of a first year in Germany that the site's audience pages show
# (sogda-website #69), each as the course has it, with its step. A word the
# course drops fails the export.
FEATURED = (
    "Anmeldung",
    "Termin",
    "Visum",
    "Aufenthaltstitel",
    "Ausländerbehörde",
    "Behörde",
    "Mietvertrag",
    "Krankenversicherung",
    "Bewerbung",
    "Ausbildung",
    "Studium",
    "Einbürgerung",
)
# ponytail: the one minSdk the app has had; add a row when minSdk moves.
ANDROID = {26: "8.0"}
LISTING_LANGUAGES = {
    "English (en-US)": "en",
    "Bangla (bn-BD)": "bn",
    "Polish (pl-PL)": "pl",
    "Russian (ru-RU)": "ru",
}
LISTING_FIELDS = {"Title": "title", "Short description": "short", "Full description": "full"}


def listing_texts(path: Path = LISTING) -> dict[tuple[str, str], str]:
    """(language heading, field heading) -> the text under it."""
    found: dict[tuple[str, str], list[str]] = {}
    language, field = "", ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            language, field = line[3:].strip(), ""
        elif line.startswith("### "):
            field = line[4:].strip()
            found[(language, field)] = []
        elif field:
            found[(language, field)].append(line)
    return {key: "\n".join(lines).strip() for key, lines in found.items()}


def _one(pattern: str, text: str, what: str) -> re.Match:
    found = re.search(pattern, text, re.S | re.M)
    if not found:
        sys.exit(f"export_site_facts: can't find {what}")
    return found


def _by_level(dart: str, function: str) -> dict[str, int]:
    """A Dart `switch (level)` of level codes to ints, `_` as the rest."""
    body = _one(rf"int {function}\(String level\) => switch \(level\) \{{(.*?)\}};", dart, function)[1]
    table: dict[str, int] = {}
    for keys, value in re.findall(r"^\s*(.+?) => (\d+),", body, re.M):
        for level in ("A1", "A2", "B1", "B2", "C1", "C2"):
            if f"'{level}'" in keys or (keys.strip() == "_" and level not in table):
                table[level] = int(value)
    return table


def mock_exam() -> tuple[int, dict]:
    """Mocks per step (BR-EXAM-02) and the paper (the app's ExamSection)."""
    rules = RULES.read_text(encoding="utf-8")
    per_step = int(_one(r"\*\*BR-EXAM-02\*\*[^\n]*?seeds 1–(\d+)", rules, "BR-EXAM-02")[1])
    points = int(_one(r"\*\*BR-EXAM-03\*\*[^\n]*?→ (\d+) points", rules, "BR-EXAM-03")[1])
    dart = EXAM.read_text(encoding="utf-8")
    enum = _one(r"enum ExamSection \{(.*?);", dart, "ExamSection")[1]
    sections = [
        {"id": name, "items": int(items), "points": int(each or 1)}
        for name, items, each in re.findall(r"(\w+)\((\d+)(?:, points: (\d+))?\)", enum)
    ]
    total = sum(s["items"] * s["points"] for s in sections)
    if total != points:
        sys.exit(f"export_site_facts: ExamSection makes {total} points, BR-EXAM-03 {points}")
    return per_step, {
        # As the exam hub says it: "40 questions", and writing and speaking
        # as the two tasks (exam-generator.md).
        "questions": sum(s["items"] for s in sections if s["points"] == 1),
        "tasks": sum(s["items"] for s in sections if s["points"] > 1),
        "points": points,
        "sections": sections,
        "writing_min_words": _by_level(dart, "writingMinWords"),
        "speaking_seconds": _by_level(dart, "speakingSeconds"),
    }


def app() -> dict:
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    gradle = GRADLE.read_text(encoding="utf-8")
    min_sdk = int(_one(r"minSdk = (\d+)", gradle, "minSdk")[1])
    return {
        "version": _one(r"^version: (\d+\.\d+\.\d+)", pubspec, "the version")[1],
        "package": _one(r'applicationId = "([^"]+)"', gradle, "applicationId")[1],
        "min_sdk": min_sdk,
        "min_android": ANDROID[min_sdk],
    }


def _sample_order(uid: str) -> str:
    return hashlib.sha256(f"{SEED}{uid}".encode()).hexdigest()


def facts(db_path: Path = DB, sample: int = SAMPLE) -> dict:
    db = sqlite3.connect(f"{db_path.as_uri()}?mode=ro", uri=True)
    try:
        meta = dict(db.execute("select key, value from meta"))
        steps = db.execute(
            "select code, level_code, ord, word_count, grammar_count from sublevels order by ord"
        ).fetchall()
        meanings: dict[str, dict[str, tuple[str, str | None]]] = {}
        for uid, lang, meaning, guide in db.execute(
            "select word_uid, lang, meaning, pronunciation from word_meanings"
        ):
            meanings.setdefault(uid, {})[lang] = (meaning, guide)
        topics: dict[str, dict[str, str]] = {}
        for uid, lang, topic in db.execute("select grammar_uid, lang, topic from grammar_translations"):
            topics.setdefault(uid, {})[lang] = topic
        per_step, paper = mock_exam()
        columns = "uid, german, article, forms, pos, english, bangla, pron_bn"

        def word(uid, german, article, forms, pos, english, bangla, pron_bn):
            """A word as the app shows it: English's and Bangla's texts in the
            course's own columns (#1147), English's guide in word_meanings
            (#1082), Russian's and Polish's there too."""
            others = meanings.get(uid, {})
            return {
                "uid": uid,
                "german": german,
                "article": article,
                "forms": forms,
                "pos": pos,
                "meaning": {
                    "en": english,
                    "bn": bangla,
                    **{lang: m for lang, (m, _) in others.items() if lang != "en"},
                },
                "guide": {
                    "en": others.get("en", (None, None))[1],
                    "bn": pron_bn,
                    **{lang: g for lang, (_, g) in others.items() if lang != "en"},
                },
            }

        featured = []
        for german in FEATURED:
            row = db.execute(
                f"select {columns}, sublevel_code from words where german = ? and kind = 'vocab'",
                (german,),
            ).fetchone()
            if row is None:
                sys.exit(f"export_site_facts: the featured word {german!r} isn't in the course")
            featured.append({**word(*row[:-1]), "step": row[-1]})
        out_steps = []
        for code, level, ord_, word_count, grammar_count in steps:
            words = db.execute(
                f"select {columns} from words"
                " where sublevel_code = ? and kind = 'vocab' and pos != 'phrase'",
                (code,),
            ).fetchall()
            picked = sorted(words, key=lambda row: _sample_order(row[0]))[:sample]
            grammar = db.execute(
                "select uid, topic from grammar_topics where sublevel_code = ? order by seq", (code,)
            ).fetchall()
            out_steps.append(
                {
                    "code": code,
                    "level": level,
                    "ord": ord_,
                    "words": word_count,
                    "grammar_topics": grammar_count,
                    "grammar": [{"uid": uid, "topic": {"en": topic, **topics.get(uid, {})}} for uid, topic in grammar],
                    "sample": [word(*row) for row in picked],
                }
            )
        levels = [
            {"code": c, "name": n, "exam_target": t}
            for c, n, t in db.execute("select code, name, exam_target from levels order by ord")
        ]
        meaning_languages = [
            {"code": c, "own_name": n}
            for c, n in db.execute("select code, own_name from course_languages order by ord")
        ]
        grammar_in = ["en"] + [
            lang for (lang,) in db.execute("select distinct lang from grammar_translations order by lang desc")
        ]
    finally:
        db.close()

    words = int(meta["word_count"])
    grammar_topics = sum(step["grammar_topics"] for step in out_steps)
    if sum(step["words"] for step in out_steps) != words:
        sys.exit("export_site_facts: the steps' words don't add up to meta.word_count")
    texts = listing_texts()
    return {
        "schema": SCHEMA,
        "content_version": meta["content_version"],
        "app": app(),
        "totals": {
            "words": words,
            "grammar_topics": grammar_topics,
            "steps": len(out_steps),
            "mock_exams_per_step": per_step,
            "mock_exams": per_step * len(out_steps),
        },
        "languages": {
            "meaning": meaning_languages,
            "app_ui": list(LISTING_LANGUAGES.values()),
            "grammar_in": grammar_in,
        },
        "mock_exam": paper,
        "levels": levels,
        "steps": out_steps,
        "featured": featured,
        "listing": {
            code: {key: texts[(heading, field)] for field, key in LISTING_FIELDS.items()}
            for heading, code in LISTING_LANGUAGES.items()
        },
    }


def render(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="exit 1 if the committed file is stale")
    parser.add_argument("--sample", type=int, default=SAMPLE, help="words per step (O3)")
    args = parser.parse_args(argv)
    text = render(facts(sample=args.sample))
    if args.check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print(f"{OUT} is stale: run python tools/export_site_facts.py")
            return 1
        return 0
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
