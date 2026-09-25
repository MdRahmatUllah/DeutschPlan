"""PIPE-07: `content_manifest.json`, and the diff between two builds.

The manifest is what makes a content update describable. content.db carries
`content_version`, but nothing in it can say *what changed* — only the previous
build's uid list can, and once the file is replaced that list is gone. So it is
written beside the database and kept.

`content-database.md` step 2: on launch the app compares the bundled version
against the installed one and, when they differ, computes added / removed /
changed uids against the manifest it kept from the previous version.

CI does the same between two builds to produce the update summary Today shows
(BR-CONTENT-03).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

MANIFEST_NAME = "content_manifest.json"

#: Bumped when the manifest's own shape changes, so a diff against an older
#: one fails loudly rather than reporting every word as removed.
MANIFEST_FORMAT = 1


def _word_digest(word) -> str:
    """What "changed" means for one word.

    Everything the learner sees, and nothing else.

    `collocations` and `synonyms_register` are in the list because
    `word-detail.md` renders both, and `freq` and `category` because
    `categories.md` sorts and filters by them.

    `seq` and `seq_in_sublevel` are left out on purpose: inserting a word at
    the top of a workbook shifts every later one, and reporting five thousand
    changed words for one insertion would make the update summary useless.
    """
    parts = (
        word.article,
        word.german,
        word.forms,
        word.pos,
        word.pron_bn,
        word.english,
        word.bangla,
        word.collocations,
        word.synonyms_register,
        str(word.freq) if word.freq is not None else None,
        word.category,
        word.sublevel_code,
        "|".join(
            f"{e.german}\u001f{e.english or ''}" for e in getattr(word, "examples", [])
        ),
    )
    joined = "\u001e".join(part or "" for part in parts)
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:16]


def _meaning_digest(word) -> str:
    """What "the meaning changed" means for one word: BR-CONTENT-02's chip.

    The meanings the learner reads on W1 and T2's back, and nothing else, so
    a freq re-rank, a category move or a new example never marks a word
    *Updated*. `english` is part of the uid (PIPE-03), so a new English
    meaning arrives as a new word and only `bangla` can differ in place; it is
    in here so the digest is the meanings, whatever the uid is made of.
    """
    joined = "\u001e".join(part or "" for part in (word.english, word.bangla))
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:16]


def _grammar_digest(row) -> str:
    """What "changed" means for one grammar topic.

    `grammar_state.grammar_uid` in the learner's database points at these, so
    a topic that disappears between two builds orphans their scheduling for
    it. Tracking the uids is what lets the update say so.
    """
    parts = (row.topic, row.rule, row.example_de, row.example_en, row.watch_out)
    joined = "".join(part or "" for part in parts)
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:16]


def build_manifest(inputs, splits) -> dict:
    """The manifest for one build."""
    from datetime import datetime, timezone

    steps: dict[str, dict[str, int]] = {}
    for word in inputs.words:
        entry = steps.setdefault(
            word.sublevel_code, {"words": 0, "grammar": 0, "examples": 0}
        )
        entry["words"] += 1
        entry["examples"] += len(getattr(word, "examples", []))
    for row in inputs.grammar:
        steps.setdefault(
            row.sublevel_code, {"words": 0, "grammar": 0, "examples": 0}
        )["grammar"] += 1

    return {
        "format": MANIFEST_FORMAT,
        "content_version": inputs.content_version,
        # The same field content.db's meta carries, so the two files describe
        # the build the same way.
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sources": inputs.sources,
        "counts": {
            "words": len(inputs.words),
            "grammar": len(inputs.grammar),
            "examples": sum(
                len(getattr(w, "examples", [])) for w in inputs.words
            ),
            "tips": len(inputs.tips),
        },
        "steps": {code: steps[code] for code in sorted(steps)},
        "boundaries": {
            split.second: split.boundary_week for split in splits.values()
        },
        "words": {word.uid: _word_digest(word) for word in inputs.words},
        # Beside `words` rather than instead of it: Today's card counts every
        # change, the *Updated* chip only these.
        "meanings": {word.uid: _meaning_digest(word) for word in inputs.words},
        "grammar": {row.uid: _grammar_digest(row) for row in inputs.grammar},
    }


def write_manifest(path: Path, manifest: dict) -> None:
    """Writes the manifest, sorted.

    `sort_keys` is what makes two builds of unchanged content byte-identical,
    and that is what makes `git diff` on the manifest the content diff rather
    than a wall of reordered lines. The uid map is built in reading order and
    sorted here — sorting it twice would only look careful.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def read_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@dataclass(frozen=True)
class ContentDiff:
    """What changed between two builds, in the shape `content_updates` wants."""

    added: list[str]
    removed: list[str]
    changed: list[str]
    #: The changed words whose meaning moved: BR-CONTENT-02's chip.
    meaning: list[str]
    grammar_added: list[str]
    grammar_removed: list[str]
    grammar_changed: list[str]
    previous_version: str
    version: str

    @property
    def is_empty(self) -> bool:
        return not (
            self.added
            or self.removed
            or self.changed
            or self.grammar_added
            or self.grammar_removed
            or self.grammar_changed
        )

    def summary(self) -> str:
        if self.is_empty:
            return f"{self.version}: no content change since {self.previous_version}"
        grammar = ""
        if self.grammar_added or self.grammar_removed or self.grammar_changed:
            grammar = (
                f"; grammar {len(self.grammar_added)} added, "
                f"{len(self.grammar_removed)} removed, "
                f"{len(self.grammar_changed)} changed"
            )
        return (
            f"{self.version}: {len(self.added)} added, "
            f"{len(self.removed)} removed, {len(self.changed)} changed "
            f"since {self.previous_version}{grammar}"
        )


class ManifestFormatError(Exception):
    """The two manifests cannot be compared."""


def diff(previous: dict, current: dict) -> ContentDiff:
    """Added, removed and changed uids between two manifests.

    A uid in both whose digest differs is *changed*: the learner's
    `word_state` for it survives, and Today says the word was updated. A uid
    only in the old one is *removed*, and its `word_state` is kept — plan
    generation joins to `c.words`, so the word simply stops appearing.
    """
    for name, manifest in (("previous", previous), ("current", current)):
        if manifest.get("format") != MANIFEST_FORMAT:
            raise ManifestFormatError(
                f"the {name} manifest is format "
                f"{manifest.get('format')!r}, this build writes "
                f"{MANIFEST_FORMAT}. Comparing them would report every word "
                f"as removed; rebuild the previous version or skip the diff."
            )

    words = _compare(previous.get("words", {}), current.get("words", {}))
    # A previous manifest from before `meanings` compares nothing: no chip,
    # rather than a false one.
    meanings = _compare(previous.get("meanings", {}), current.get("meanings", {}))
    grammar = _compare(previous.get("grammar", {}), current.get("grammar", {}))

    return ContentDiff(
        added=words[0],
        removed=words[1],
        changed=words[2],
        meaning=meanings[2],
        grammar_added=grammar[0],
        grammar_removed=grammar[1],
        grammar_changed=grammar[2],
        previous_version=previous["content_version"],
        version=current["content_version"],
    )


def _compare(
    before: dict[str, str], after: dict[str, str]
) -> tuple[list[str], list[str], list[str]]:
    return (
        sorted(set(after) - set(before)),
        sorted(set(before) - set(after)),
        sorted(
            uid for uid in set(before) & set(after) if before[uid] != after[uid]
        ),
    )


def main(argv: list[str] | None = None) -> int:
    """`python tools/content_manifest.py previous.json current.json`.

    CI runs this between the manifest of the released build and the one just
    produced, to get the update summary Today shows (BR-CONTENT-03).
    """
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="Diff two content manifests.")
    parser.add_argument("previous", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the diff as JSON, for content_updates.changed_json",
    )
    args = parser.parse_args(argv)

    if not args.previous.exists():
        # The first build has nothing to compare against, and that is not a
        # failure — it is every learner's first install.
        print(f"no previous manifest at {args.previous}; nothing to diff")
        return 0

    try:
        result = diff(read_manifest(args.previous), read_manifest(args.current))
    except ManifestFormatError as error:
        print(f"content manifest: {error}", file=sys.stderr)
        return 1

    if args.json:
        print(
            json.dumps(
                {
                    "added": result.added,
                    "removed": result.removed,
                    "changed": result.changed,
                    "meaning": result.meaning,
                    "grammar_added": result.grammar_added,
                    "grammar_removed": result.grammar_removed,
                    "grammar_changed": result.grammar_changed,
                },
                indent=2,
            )
        )
    else:
        print(result.summary())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
