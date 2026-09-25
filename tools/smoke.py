"""#169's integration smoke on the Android emulator: the two flows that must never break.

    python tools/team.py device        # the emulator is shared: hold it first
    python tools/smoke.py              # --device emulator-5558 is the default
    python tools/team.py device --release

In order, stopping at the first failure:

    uninstall     a fresh install (not being installed is fine)
    trim caches   room for the debug APK `flutter test` builds
    first day     integration_test/first_day_test.dart: S1, S2, T1, T2, T3/T5, T6
    exam start    integration_test/exam_start_test.dart: Mock 1 begun, 3 answers, left mid-exam
    kill          am force-stop
    process gone  pidof finds nothing: the next run is a new process
    exam resume   integration_test/exam_resume_test.dart: Resume, the answers kept, then Leave

`flutter test` uninstalls the app after an integration test unless told
`--no-uninstall`, and installs with `adb install -r`, which keeps app data. So
every run here passes `--no-uninstall`: that is what carries user.db, and the
exam in it, from one run to the next.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import device  # noqa: E402
import team  # noqa: E402

APP = TOOLS.parent / "app"


def holds_device(agent: str) -> bool:
    """Whether [agent] holds `team.py device`'s lock: its owner file names them."""
    owner = team.team_root() / ".device.lock" / "owner"
    return bool(agent) and owner.exists() and owner.read_text(encoding="utf-8").split()[:1] == [agent]


def steps(serial: str, adb: str, flutter: str) -> list[tuple[str, list[str], bool | None]]:
    """(name, command, whether it must succeed: None when either will do)."""
    shell = [adb, "-s", serial, "shell"]
    test = [flutter, "test", "--no-uninstall", "-d", serial]
    return [
        ("uninstall", [adb, "-s", serial, "uninstall", device.PACKAGE], None),
        ("trim caches", [*shell, "pm", "trim-caches", "16G"], None),
        ("first day", [*test, "integration_test/first_day_test.dart"], True),
        ("exam start", [*test, "integration_test/exam_start_test.dart"], True),
        ("kill", [*shell, "am", "force-stop", device.PACKAGE], True),
        ("process gone", [*shell, "pidof", device.PACKAGE], False),
        ("exam resume", [*test, "integration_test/exam_resume_test.dart"], True),
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", help=f"the emulator (default: {device.DEV_SERIAL})")
    args = parser.parse_args(argv)

    me = device.agent()
    serial = device.pick_serial(args.device, me)
    if not holds_device(me):
        print("refused: hold the emulator first: `python tools/team.py device`", file=sys.stderr)
        return 2

    for name, command, succeeds in steps(serial, device.adb_path(), shutil.which("flutter") or "flutter"):
        code = subprocess.run(command, cwd=APP).returncode
        ok = succeeds is None or (code == 0) == succeeds
        print(f"{'PASS' if ok else 'FAIL'}  {name}", flush=True)
        if not ok:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
