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

    Everything the learner sees, and nothing else. `seq` and `seq_in_sublevel`
    are left out on purpose: inserting a word at the top of a workbook shifts
    every later one, and reporting five thousand changed words for one
    insertion would make the update summary useless.
    """
    parts = (
        word.article,
        word.german,
        word.forms,
        word.pos,
        word.pron_bn,
        word.english,
        word.bangla,
        word.sublevel_code,
        "|".join(
            f"{e.german}\u001f{e.english or ''}" for e in getattr(word, "examples", [])
        ),
    )
    joined = "\u001e".join(part or "" for part in parts)
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:16]


def build_manifest(inputs, splits) -> dict:
    """The manifest for one build."""
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
    previous_version: str
    version: str

    @property
    def is_empty(self) -> bool:
        return not (self.added or self.removed or self.changed)

    def summary(self) -> str:
        if self.is_empty:
            return f"{self.version}: no content change since {self.previous_version}"
        return (
            f"{self.version}: {len(self.added)} added, "
            f"{len(self.removed)} removed, {len(self.changed)} changed "
            f"since {self.previous_version}"
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

    before = previous["words"]
    after = current["words"]

    return ContentDiff(
        added=sorted(set(after) - set(before)),
        removed=sorted(set(before) - set(after)),
        changed=sorted(
            uid for uid in set(before) & set(after) if before[uid] != after[uid]
        ),
        previous_version=previous["content_version"],
        version=current["content_version"],
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
                },
                indent=2,
            )
        )
    else:
        print(result.summary())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
