"""#718 / #722: the build reads the clock once.

`meta.built_at` and the manifest's `built_at` came from two `datetime.now()`
calls; about one build in twelve straddled a second and failed the app's
FR-M9-01 test, which holds the two equal. `content_version` is the same
instant, to the second.
"""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import excel_to_sqlite  # noqa: E402
from content_manifest import build_manifest  # noqa: E402
from content_writer import build  # noqa: E402
from fixtures.make_workbooks import BOOK_LEVELS, write_all  # noqa: E402


class _AdvancingClock(datetime):
    """Two seconds later every time it is read."""

    reads = 0

    @classmethod
    def now(cls, tz=None):
        cls.reads += 1
        return datetime(2020, 1, 2, 3, 4, 5, 999_999, tzinfo=timezone.utc) + timedelta(
            seconds=2 * cls.reads
        )


def test_718_built_at_is_one_instant_in_the_database_and_the_manifest(tmp_path, monkeypatch):
    monkeypatch.setattr(_AdvancingClock, "reads", 0)
    monkeypatch.setattr(excel_to_sqlite, "datetime", _AdvancingClock)
    write_all(tmp_path)
    sources = [excel_to_sqlite.read_workbook(tmp_path / name) for name in BOOK_LEVELS]
    splits = excel_to_sqlite.derive(sources)
    inputs = excel_to_sqlite.collect(sources, splits)
    # The two writers main() calls, as it calls them.
    out = tmp_path / "content.db"
    build(out, inputs)
    written = build_manifest(inputs, splits)

    connection = sqlite3.connect(out)
    try:
        meta = dict(connection.execute("SELECT key, value FROM meta").fetchall())
    finally:
        connection.close()

    assert meta["built_at"] == written["built_at"] == "2020-01-02T03:04:07+00:00"
    # #722: to the second, from the same read.
    assert meta["content_version"] == written["content_version"] == "20200102030407"
