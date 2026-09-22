"""Regenerates `app/lib/data/db/content_schema.drift` from the pipeline DDL.

drift generates nothing for an attached database, so the queries in
`content.drift` are hand-written. This mirror is what drift type-checks them
against — and a mirror that has drifted type-checks against a schema
`make content` does not produce, so every query compiles and fails at run time.

Run through `make gen`. `app/test/db/content_schema_test.dart` fails if the
two ever disagree, which is what catches someone editing the mirror instead.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MIRROR = REPO / "app" / "lib" / "data" / "db" / "content_schema.drift"
SOURCES = (
    REPO / "tools" / "content_schema.sql",
    REPO / "tools" / "content_fts.sql",
)

HEADER = """-- content.db, mirrored for drift.
--
-- drift generates nothing for an attached database, so the queries in
-- `content.drift` are hand-written SQL. This file is what drift type-checks
-- them against: it declares the same tables the pipeline creates, so a query
-- naming a column that does not exist is a build error rather than a crash on
-- a learner's phone.
--
-- GENERATED from tools/content_schema.sql and tools/content_fts.sql by
-- `make gen`. `test/db/content_schema_test.dart` fails if the two disagree —
-- edit the .sql files, not this one.

"""


def mirror() -> str:
    sql = "\n".join(path.read_text(encoding="utf-8") for path in SOURCES)
    body = "\n".join(
        line for line in sql.split("\n") if not line.lstrip().startswith("--")
    )
    return HEADER + re.sub(r"\n{3,}", "\n\n", body).strip() + "\n"


def main() -> int:
    MIRROR.write_text(mirror(), encoding="utf-8", newline="\n")
    print(f"{MIRROR.relative_to(REPO)} regenerated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
