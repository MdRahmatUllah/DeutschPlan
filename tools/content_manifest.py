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

import difflib
import hashlib
import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from pipeline_steps import PipelineError, uid_text

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
    # The escape, not the raw character: a raw U+001E is invisible, and
    # the review read it as no separator at all (#697 TL-14).
    joined = "\u001e".join(part or "" for part in parts)
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:16]


def build_manifest(inputs, splits, aliases: dict[str, str] | None = None) -> dict:
    """The manifest for one build. [aliases] is `link_uids`'s map (PIPE-09)."""

    steps: dict[str, dict[str, int]] = {}
    for word in inputs.words:
        entry = steps.setdefault(
            word.sublevel_code, {"words": 0, "grammar": 0, "examples": 0}
        )
        # BR-CONTENT-04 (#630): what the step teaches; `words` below, the
        # digests, has every row.
        entry["words"] += word.kind == "vocab"
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
        "built_at": inputs.built_at,
        "sources": inputs.sources,
        "counts": {
            "words": sum(word.kind == "vocab" for word in inputs.words),
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
        # PIPE-09: old uid -> the uid the same word, or grammar topic
        # (#808), carries now. Every link since the first build, not only
        # this one's: a learner can skip versions, and the app moves their
        # rows along these on install.
        "aliases": aliases or {},
    }


#: What `link_uids` compares a word by: `(level, german, pos, english)`.
WordKey = tuple[str, str, str, str]


def word_key(level, german, pos, english) -> WordKey:
    """The uid's four fields, spelled so that a case or spacing change to a
    part of speech, or an NFD paste, is still the same word."""
    return tuple(uid_text(part or "").casefold() for part in (level, german, pos, english))


def grammar_key(level, topic) -> WordKey:
    """#808: a grammar topic compared as a word with no part of speech or
    English, so `link_uids` links a topic whose title changed case or
    spacing (pass 1) or that moved level (pass 2). A renamed topic is not
    guessed at: its title is all a topic's uid has, and "the nearest title
    in the level" would move progress between two different topics. It is
    linked by a `links:` pin in `content/corrections.yaml`."""
    return word_key(level, topic, "", "")


@dataclass(frozen=True)
class PreviousBuild:
    """The committed asset: what learners have (PIPE-09)."""

    words: dict[str, WordKey]
    grammar: dict[str, WordKey]
    manifest: dict | None
    #: #970: each grammar topic's step as shipped, by uid ("A1.2"), whose
    #: split the next build keeps.
    grammar_steps: dict[str, str] = field(default_factory=dict)

    @property
    def boundaries(self) -> dict[str, int]:
        """#923: each level's shipped boundary week, by level ("B2": 21)."""
        kept = (self.manifest or {}).get("boundaries", {})
        return {code.split(".")[0]: week for code, week in kept.items()}


def previous_build(directory: Path) -> PreviousBuild:
    """The committed asset in [directory]: its words and grammar topics by
    uid, and its manifest.

    Empty when there is none yet: the first build has nothing to lose.
    """
    db, manifest = directory / "content.db", directory / MANIFEST_NAME
    if not db.exists() or not manifest.exists():
        return PreviousBuild({}, {}, None)
    connection = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)
    try:
        words = connection.execute(
            "SELECT uid, level_code, german, pos, english FROM words"
        ).fetchall()
        grammar = connection.execute(
            "SELECT uid, level_code, topic, sublevel_code FROM grammar_topics"
        ).fetchall()
    finally:
        connection.close()
    return PreviousBuild(
        {uid: word_key(*rest) for uid, *rest in words},
        {uid: grammar_key(level, topic) for uid, level, topic, _ in grammar},
        read_manifest(manifest),
        {uid: step for uid, *_, step in grammar},
    )


def link_uids(
    before: dict[str, WordKey],
    after: dict[str, WordKey],
    carried: dict[str, str] | None = None,
    known: dict[str, str] | None = None,
    refused: set[str] | frozenset[str] = frozenset(),
) -> tuple[dict[str, str], list[str]]:
    """PIPE-09 (#648): which new uid each removed one became.

    A uid is `sha1(level|german|pos|english)`, so fixing a gloss or re-levelling
    a word gives it a new one, and the learner's rows under the old one would
    stop appearing. A removed uid is linked to an added one that is the same
    word:

    1. the same level, German and part of speech: the nearest English wins;
    2. else the same German, part of speech and English: it moved level.

    Each added uid takes one removed uid at most, best match first across
    every pair (#807): two senses of one word re-glossed in one build each
    get their own nearest, whichever uid sorts first. [known] links come
    first: a row `content/corrections.yaml` changed maps the uid it had as
    read to the one it has now, exactly, whatever it changed (#629), and a
    `links:` pin names one outright. [refused] uids are linked to nothing
    (a `links:` refusal, #807): they come back as removed. [carried] is the
    previous build's map, followed through this one's, so a learner who
    skipped a version still lands on the word as it is now.

    Returns the map and the removed uids nothing matched, which the build
    refuses to drop without `--allow-removed`.
    """
    links = {
        old: new
        for old, new in (known or {}).items()
        if old in before and old not in after and new in after and old not in refused
    }
    removed = sorted(set(before) - set(after) - set(links))
    free = {
        uid: after[uid]
        for uid in sorted(set(after) - set(before) - set(links.values()))
    }

    def link(same, closeness) -> None:
        pairs = [
            (closeness(before[old], key), old, new)
            for old in removed
            if old not in links and old not in refused
            for new, key in free.items()
            if same(before[old], key)
        ]
        # Best first; `sorted` is stable and the pairs come in uid order, so
        # equals go to the first old uid, then the first new one.
        for _, old, new in sorted(pairs, key=lambda pair: -pair[0]):
            if old not in links and new in free:
                links[old] = new
                del free[new]

    link(
        lambda a, b: a[:3] == b[:3],
        lambda a, b: difflib.SequenceMatcher(None, a[3], b[3]).ratio(),
    )
    link(lambda a, b: a[1:] == b[1:], lambda a, b: 0)

    for old, new in (carried or {}).items():
        new = links.get(new, new)
        if old not in after and new in after and old not in refused:
            links.setdefault(old, new)

    return dict(sorted(links.items())), [uid for uid in removed if uid not in links]


def write_manifest(path: Path, manifest: dict) -> None:
    """Writes the manifest, sorted.

    `sort_keys` is what makes two builds of unchanged content identical but
    for `content_version` and `built_at`, and that is what makes `git diff`
    on the manifest the content diff rather than a wall of reordered lines.
    The uid map is built in reading order and sorted here — sorting it twice
    would only look careful.
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


class ManifestFormatError(PipelineError):
    """The two manifests cannot be compared.

    A PipelineError, so the build's diff print reports it rather than
    crashing with a traceback (#825).
    """


def diff(previous: dict, current: dict) -> ContentDiff:
    """Added, removed and changed uids between two manifests.

    A uid in both whose digest differs is *changed*: the learner's
    `word_state` for it survives, and Today says the word was updated. A uid
    only in the old one, and not linked to a new one by the current
    manifest's `aliases` (PIPE-09), is *removed*, and its `word_state` is
    kept — plan generation joins to `c.words`, so the word simply stops
    appearing. A uid linked into one the previous course already had is a
    duplicate merged into the word that stays (PIPE-12): the learner lost
    nothing, so it is neither removed nor added (#922).
    """
    for name, manifest in (("previous", previous), ("current", current)):
        if manifest.get("format") != MANIFEST_FORMAT:
            raise ManifestFormatError(
                f"the {name} manifest is format "
                f"{manifest.get('format')!r}, this build writes "
                f"{MANIFEST_FORMAT}. Comparing them would report every word "
                f"as removed; rebuild the previous version or skip the diff."
            )

    # PIPE-09: a word whose uid changed is the same word, changed, not one
    # removed and one added. ContentUpdater._diff does the same.
    aliases = current.get("aliases", {})
    words = _compare(
        _follow(previous.get("words", {}), aliases), current.get("words", {})
    )
    # A previous manifest from before `meanings` compares nothing: no chip,
    # rather than a false one.
    meanings = _compare(
        _follow(previous.get("meanings", {}), aliases), current.get("meanings", {})
    )
    # #808: a topic linked to its new uid is changed, not removed and added.
    grammar = _compare(
        _follow(previous.get("grammar", {}), aliases), current.get("grammar", {})
    )

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


def _follow(digests: dict[str, str], aliases: dict[str, str]) -> dict[str, str]:
    """[digests] under the uids their words carry now; without a merged
    duplicate, whose word was in [digests] already (#922)."""
    moved: dict[str, str] = {}
    for uid, digest in digests.items():
        new = aliases.get(uid)
        if new in digests:
            continue
        moved[new or uid] = digest
    return moved


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
    if not args.current.exists():
        # A clean checkout: content/build/ is ignored, so nothing is there
        # until the pipeline runs — which diffs by itself (#648).
        print(
            f"no build at {args.current}; run the pipeline, which prints this "
            f"diff itself",
            file=sys.stderr,
        )
        return 1

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
