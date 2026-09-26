"""Drive the Android emulator: install the release APK, tap by label, screenshot.

emulator-5554 is agent-3's (SQA) alone, and this refuses it to anyone else.
The developer agents share emulator-5558, the default, so hold the device lock
for the whole check:

    python tools/team.py device                # take it (or be told who has it)
    cd app && flutter build apk --release --target-platform android-x64
    python tools/device.py install
    python tools/device.py launch tap:Learn "tap:Word categories" wait:Wohnen shot:l5.png back shot:after.png
    python tools/team.py device --release      # the moment you are done

Steps run in order:
    tap:<label>    tap the first element whose content-desc starts with <label>
    find:<text>    as tap, but matching anywhere in the content-desc
    at:<x>,<y>     tap a point (a switch whose label repeats its row's text)
    type:<text>    type into the focused field (ASCII only)
    wait:<label>   wait (up to a minute) until an element starts with <label>
    shot:<file>    screenshot into --out (default: the system temp dir)
    back           the Android back key
    swipe          scroll the page up
    sleepN         wait N seconds
    labels         print what is on screen (to find labels)

Debug APKs do not fit on the emulator's storage: always the release x64
build. Screenshots and dumps go to --out, never into the repo.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PACKAGE = "io.github.rahmatullah.deutschplan"

# The owner, 2026-09-24: one emulator for SQA, one for the developers.
# ANDROID_SERIAL or --serial picks another, but never SQA_SERIAL for a
# developer.
SQA_AGENT = "agent-3"
SQA_SERIAL = "emulator-5554"
DEV_SERIAL = "emulator-5558"


def agent() -> str:
    """This worktree's agent, from the `.dp-agent` that `team.py join` wrote."""
    marker = Path(__file__).resolve().parents[1] / ".dp-agent"
    return marker.read_text(encoding="utf-8").strip() if marker.exists() else ""


def pick_serial(serial: str | None, who: str) -> str:
    """The emulator [who] drives: [serial] if given, else theirs."""
    chosen = serial or (SQA_SERIAL if who == SQA_AGENT else DEV_SERIAL)
    if chosen == SQA_SERIAL and who != SQA_AGENT:
        raise SystemExit(
            f"{SQA_SERIAL} is {SQA_AGENT}'s (SQA) alone: use {DEV_SERIAL}, the default"
        )
    return chosen
APK = Path(__file__).resolve().parents[1] / "app" / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"


def adb_path() -> str:
    found = shutil.which("adb")
    if found:
        return found
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ.get("LOCALAPPDATA", "") + "/Android/Sdk")
    candidate = sdk / "platform-tools" / ("adb.exe" if sys.platform == "win32" else "adb")
    if candidate.exists():
        return str(candidate)
    raise SystemExit("adb not found: install platform-tools or set ANDROID_HOME")


class Device:
    def __init__(self, serial: str | None = None, out: Path | None = None):
        self.adb = adb_path()
        self.serial = pick_serial(serial or os.environ.get("ANDROID_SERIAL"), agent())
        self.out = out or Path(tempfile.gettempdir())

    def run(self, *args: str, check: bool = False) -> subprocess.CompletedProcess:
        cmd = [self.adb, *(["-s", self.serial] if self.serial else []), *args]
        return subprocess.run(cmd, capture_output=True, check=check)

    def sh(self, *args: str) -> str:
        return self.run("shell", *args).stdout.decode("utf-8", "replace")

    def labels(self) -> list[tuple[str, tuple[int, int]]]:
        """Every content-desc on screen with its centre. The old dump is
        removed first: a stale one would answer for the wrong screen."""
        self.sh("rm", "-f", "/sdcard/ui.xml")
        self.sh("uiautomator", "dump", "/sdcard/ui.xml")
        xml = self.sh("cat", "/sdcard/ui.xml")
        found = []
        for m in re.finditer(r'content-desc="([^"]*)"[^>]*?bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
            a, b, c, d = map(int, m.group(2, 3, 4, 5))
            found.append((m.group(1), ((a + c) // 2, (b + d) // 2)))
        if not xml.strip():
            print("empty UI dump: the system is probably stalled on an ANR dialog — `adb reboot` fixes it")
        return found

    def find(self, label: str, anywhere: bool = False) -> tuple[int, int] | None:
        for text, centre in self.labels():
            if (label in text) if anywhere else text.startswith(label):
                return centre
        return None

    def wait(self, label: str, anywhere: bool = False, seconds: float = 60) -> tuple[int, int]:
        deadline = time.time() + seconds
        while time.time() < deadline:
            centre = self.find(label, anywhere)
            if centre:
                return centre
            time.sleep(1.5)
        raise SystemExit(f"never saw {label!r} on screen (run the `labels` step to see what is there)")

    def tap(self, label: str, anywhere: bool = False) -> None:
        x, y = self.wait(label, anywhere)
        self.sh("input", "tap", str(x), str(y))
        time.sleep(1.2)

    def shot(self, name: str) -> Path:
        path = self.out / name
        path.write_bytes(self.run("exec-out", "screencap", "-p").stdout)
        return path

    def install(self, apk: Path = APK) -> bool:
        """Installs [apk]; whether adb answered `Success`. A refusal (a version
        downgrade, say) goes to adb's stderr and leaves the old app in place."""
        if not apk.exists():
            raise SystemExit(f"no APK at {apk}: `cd app && flutter build apk --release --target-platform android-x64`")
        out = self.run("install", "-r", str(apk)).stdout.decode("utf-8", "replace")
        if "INSUFFICIENT_STORAGE" in out:
            self.sh("pm", "trim-caches", "16G")
            out = self.run("install", "-r", str(apk)).stdout.decode("utf-8", "replace")
        print(out.strip().splitlines()[-1] if out.strip() else "installed")
        return out.strip().endswith("Success")

    def launch(self) -> None:
        self.sh("am", "force-stop", PACKAGE)
        self.sh("monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")
        time.sleep(3)


def main(argv: list[str]) -> int:
    # Labels carry arrows and Bangla; a Windows console is cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not argv:
        print(__doc__)
        return 2
    serial = out = None
    steps = []
    it = iter(argv)
    for arg in it:
        if arg == "--serial":
            serial = next(it)
        elif arg == "--out":
            out = Path(next(it))
        else:
            steps.append(arg)
    device = Device(serial, out)
    # Git Bash rewrites /sdcard/... into a Windows path; this runs adb
    # directly from Python, so no MSYS_NO_PATHCONV is needed here.
    for step in steps:
        if step == "install":
            device.install()
        elif step == "launch":
            device.launch()
        elif step == "back":
            device.sh("input", "keyevent", "4")
            time.sleep(1)
        elif step == "swipe":
            device.sh("input", "swipe", "540", "1800", "540", "600", "300")
            time.sleep(1)
        elif step == "labels":
            for text, centre in device.labels():
                if text:
                    print(f"{centre}  {text}")
        elif step.startswith("sleep"):
            time.sleep(float(step[5:] or 1))
        elif step.startswith("tap:"):
            device.tap(step[4:])
        elif step.startswith("find:"):
            device.tap(step[5:], anywhere=True)
        elif step.startswith("at:"):
            x, y = step[3:].split(",")
            device.sh("input", "tap", x.strip(), y.strip())
            time.sleep(1.2)
        elif step.startswith("type:"):
            # adb's `input text` takes ASCII only, and %s for a space.
            device.sh("input", "text", step[5:].replace(" ", "%s"))
            time.sleep(1)
        elif step.startswith("wait:"):
            device.wait(step[5:])
        elif step.startswith("shot:"):
            print(device.shot(step[5:]))
        else:
            raise SystemExit(f"unknown step {step!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
