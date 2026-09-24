"""Planted violations: break the code on purpose and check a test notices.

A test that has never failed is not a guard. For each plant, this replaces
one exact snippet in one file, runs the tests, puts the file back, and says
whether the tests caught it:

    python tools/plant.py plants.json            # every plant
    python tools/plant.py plants.json "no ring"  # just the named ones

`plants.json` (write it with an editor, not a shell heredoc, which mangles
backslashes):

    {
      "tests": ["test/features/today_screen_test.dart"],
      "plants": [
        {"name": "no ring", "file": "lib/features/today/today_view.dart",
         "old": "revise.done + newToday.done", "new": "revise.done"}
      ]
    }

Paths are relative to `app/`. A plant whose file is a codegen input (a
`.drift` file, or a Dart file with a `part '*.g.dart'` whose generated part
the change affects) sets `"codegen": true` and build_runner runs before and
after it.

    CAUGHT     the tests failed: good
    *MISSED*   the tests passed: strengthen them, then plant again
    COMPILE?   the plant does not compile: rewrite it (it proves nothing)
    SKIP       `old` is not in the file exactly once

This never kills other processes: several agents run tests on this machine at
once. A stale `flutter_tester` holding this worktree's DLLs is stopped with
`--kill-own-testers`, which only touches processes started from this worktree.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "app"


def run_tests(tests: list[str], command: list[str] | None = None) -> str:
    cmd = command or ["flutter", "test", "--timeout", "60s", *tests]
    try:
        out = subprocess.run(cmd, cwd=APP, capture_output=True, text=True, encoding="utf-8",
                             errors="replace", shell=sys.platform == "win32", timeout=1200)
        return out.stdout + out.stderr
    except subprocess.TimeoutExpired:
        return "TIMEOUT"


def verdict(output: str) -> str:
    if output == "TIMEOUT":
        return "CAUGHT (hung)"
    if "Compilation failed" in output:  # flutter test: 'Failed to load "...": Compilation failed'
        return "COMPILE?"
    return "*MISSED*" if "All tests passed!" in output else "CAUGHT"


def codegen() -> None:
    subprocess.run(["dart", "run", "build_runner", "build", "--delete-conflicting-outputs"],
                   cwd=APP, capture_output=True, shell=sys.platform == "win32", check=False)


def plant(entry: dict, tests: list[str], command: list[str] | None = None) -> str:
    path = APP / entry["file"]
    original = path.read_bytes()
    # The working tree is CRLF on Windows (core.autocrlf); snippets are
    # written with \n. Match on \n, and put the original bytes back after.
    text = original.decode("utf-8").replace("\r\n", "\n")
    count = text.count(entry["old"])
    if count != 1:
        return f"SKIP (found {count} times)"
    try:
        path.write_bytes(text.replace(entry["old"], entry["new"]).encode("utf-8"))
        if entry.get("codegen"):
            codegen()
        return verdict(run_tests(entry.get("tests", tests), command))
    finally:
        path.write_bytes(original)
        if entry.get("codegen"):
            codegen()


def kill_own_testers() -> None:
    """Stop flutter_tester processes whose command line points into this
    worktree — never anyone else's."""
    if sys.platform != "win32":
        return
    here = str(APP.parent).replace("/", "\\")
    script = (
        "Get-CimInstance Win32_Process -Filter \"Name='flutter_tester.exe'\" | "
        f"Where-Object {{ $_.CommandLine -like '*{here}*' }} | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, check=False)


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    if "--kill-own-testers" in argv:
        kill_own_testers()
    spec = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    only = set(args[1:])
    missed = 0
    for entry in spec["plants"]:
        if only and entry["name"] not in only:
            continue
        result = plant(entry, spec["tests"], spec.get("command"))
        missed += result in ("*MISSED*", "COMPILE?") or result.startswith("SKIP")
        print(f"{result:<14} {entry['name']}", flush=True)
    failures = APP / "test" / "golden" / "failures"
    if failures.exists():
        for png in failures.glob("*"):
            png.unlink()
        failures.rmdir()
    print("all caught" if not missed else f"{missed} not caught: strengthen the tests or fix the plants")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
