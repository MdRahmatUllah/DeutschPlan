"""Removes the content tables from a dumped schema fixture.

`drift_dev schema dump` writes every entity the database declares, and
`AppDatabase` declares the content tables so drift can type-check `ContentDao`
— but `onCreate` never builds them, because an empty `words` inside user.db
would shadow the attached course.

So the raw dump describes a database that never exists. A fixture has to mean
"what user.db looks like at version N", or `migration_test` compares a real
file against tables nobody created and fails on every one of them.

Run through `make schema-dump`, which dumps and then trims.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP_DATABASE = REPO / "app" / "lib" / "data" / "db" / "app_database.dart"


def own_tables() -> set[str]:
    """`AppDatabase.ownTables`, read from the source.

    Read rather than restated: it is the same list `onCreate` uses, and a
    fixture trimmed against a different list would be wrong in exactly the way
    this script exists to prevent.
    """
    source = APP_DATABASE.read_text(encoding="utf-8")
    block = re.search(
        r"ownTables\s*=\s*<String>\{(.*?)\};", source, re.DOTALL
    )
    if not block:
        raise SystemExit(
            f"could not find ownTables in {APP_DATABASE}. It is what says "
            f"which tables user.db owns; without it this script would trim "
            f"the wrong ones."
        )
    return set(re.findall(r"'([a-z_]+)'", block.group(1)))


def trim(fixture: dict, keep: set[str]) -> dict:
    """Drops every entity that is not a user table or an index on one."""
    kept: list[dict] = []
    old_to_new: dict[int, int] = {}

    for entity in fixture["entities"]:
        name = entity["data"].get("name", "")
        if entity["type"] == "table":
            wanted = name in keep
        elif entity["type"] == "index":
            # The table the CREATE INDEX names, not the index's own name:
            # idx_one_active_enrollment shares no substring with enrollments.
            on = re.search(
                r"\bON\s+\"?(\w+)\"?",
                entity["data"].get("sql", ""),
                re.IGNORECASE,
            )
            wanted = on is not None and on.group(1) in keep
        else:
            wanted = True

        if not wanted:
            continue

        old_to_new[entity["id"]] = len(kept)
        kept.append(entity)

    # Ids are positional and references point at them, so both are rewritten
    # after the drop — a dangling reference makes the fixture unreadable.
    for entity in kept:
        entity["id"] = old_to_new[entity["id"]]
        entity["references"] = [
            old_to_new[ref] for ref in entity["references"] if ref in old_to_new
        ]

    trimmed = {**fixture, "entities": kept}

    # `fixed_sql` is a second copy of every entity's DDL, and it is the one
    # `drift_dev schema generate` reads. Leaving it untouched put the content
    # tables back into the generated helper, and the migration test then
    # compared a real database against FTS shadow tables nobody had created.
    if "fixed_sql" in trimmed:
        names = {entity["data"].get("name") for entity in kept}
        trimmed["fixed_sql"] = [
            statement
            for statement in trimmed["fixed_sql"]
            if statement.get("name") in names
        ]

    return trimmed


def main(argv: list[str]) -> int:
    directory = Path(argv[1]) if len(argv) > 1 else REPO / "app" / "drift_schemas"
    keep = own_tables()

    for path in sorted(directory.glob("drift_schema_v*.json")):
        fixture = json.loads(path.read_text(encoding="utf-8"))
        before = len(fixture["entities"])
        trimmed = trim(fixture, keep)

        if len(trimmed["entities"]) == before:
            continue

        with path.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(trimmed, handle)
            handle.write("\n")
        print(
            f"{path.name}: {before} entities -> {len(trimmed['entities'])} "
            f"(content tables removed)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
