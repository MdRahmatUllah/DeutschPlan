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

    CAUGHT     the tests ran and failed: good
    *MISSED*   the tests passed: strengthen them, then plant again
    COMPILE?   the plant does not compile: rewrite it (it proves nothing)
    ERROR?     the run failed without a test failing (a bad path, no flutter,
               a locked DLL): fix the run, it proves nothing (#685)
    HUNG?      the run timed out: indeterminate, run that plant again
    SKIP       `old` is not in the file exactly once

Before any plant, the same tests run unplanted and must pass: a plant only
counts against a baseline that is green (#685). Only CAUGHT counts as caught.

This never kills other processes: several agents run tests on this machine at
once. A stale `flutter_tester` holding this worktree's DLLs is stopped with
`--kill-own-testers`, which only touches processes started from this worktree.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "app"


def run_tests(tests: list[str], command: list[str] | None = None,
              timeout: float = 1200) -> tuple[int | None, str]:
    """The run's exit code (None on a timeout) and its output."""
    cmd = command or ["flutter", "test", "--timeout", "60s", *tests]
    # On Windows dart and flutter are .bat files, which a bare Popen can't
    # find: resolve the program first, and a missing one fails the run (#814).
    exe = shutil.which(cmd[0])
    if exe is None:
        return 127, f"{cmd[0]} is not on PATH"
    proc = subprocess.Popen([exe, *cmd[1:]], cwd=APP, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace")
    try:
        out, _ = proc.communicate(timeout=timeout)
        return proc.returncode, out
    except subprocess.TimeoutExpired:
        # This run's own process tree only (flutter, its testers): never by
        # image name, which would kill every agent's tests.
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True, check=False)
        else:
            proc.kill()
        try:
            proc.communicate(timeout=30)  # a failed kill must not hang the run (#814)
        except subprocess.TimeoutExpired:
            pass
        return None, "TIMEOUT"


def verdict(code: int | None, output: str, flutter: bool = True) -> str:
    if code is None:
        return "HUNG?"
    if "Compilation failed" in output:  # flutter test: 'Failed to load "...": Compilation failed'
        return "COMPILE?"
    if code == 0:
        return "*MISSED*"
    # A custom command's own baseline proved it runs, so any failure is its
    # tests failing; flutter's must say so, or it is a broken run (#685).
    if not flutter or "Some tests failed" in output:
        return "CAUGHT"
    return "ERROR?"


def baseline(tests: list[str], command: list[str] | None = None) -> str | None:
    """None when the unplanted tests pass, else why they don't (#685)."""
    code, output = run_tests(tests, command)
    if code == 0 and (command or "All tests passed!" in output):
        return None
    tail = " / ".join(output.strip().splitlines()[-5:])
    return f"exit {code}: {tail}"


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
        return verdict(*run_tests(entry.get("tests", tests), command), flutter=command is None)
    finally:
        path.write_bytes(original)
        if entry.get("codegen"):
            codegen()


def own_pattern(worktree: Path | None = None) -> str:
    """PowerShell's -like pattern for a tester of [worktree]'s: its
    `--packages=` names the worktree's own package config, so `agent-1`
    never matches `agent-1-review` (#697 TL-12), and the main checkout never
    matches a worktree nested in it (`.claude/worktrees/`)."""
    here = str(worktree or APP.parent).replace("/", "\\")
    return f"*--packages={here}\\app\\.dart_tool\\*"


def kill_own_testers() -> None:
    """Stop flutter_tester processes whose command line points into this
    worktree — never anyone else's."""
    if sys.platform != "win32":
        return
    script = (
        "Get-CimInstance Win32_Process -Filter \"Name='flutter_tester.exe'\" | "
        f"Where-Object {{ $_.CommandLine -like '{own_pattern()}' }} | "
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
    chosen = [entry for entry in spec["plants"] if not only or entry["name"] in only]
    # The baseline: each distinct test set the chosen plants run, unplanted.
    for tests in {tuple(entry.get("tests", spec["tests"])) for entry in chosen}:
        why = baseline(list(tests), spec.get("command"))
        if why:
            print(f"baseline failed for {list(tests)}: {why}")
            print("fix the tests (or the run) before planting: nothing was planted")
            return 2
    missed = 0
    for entry in chosen:
        result = plant(entry, spec["tests"], spec.get("command"))
        missed += result != "CAUGHT"  # MISSED, COMPILE?, ERROR?, HUNG?, SKIP
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
