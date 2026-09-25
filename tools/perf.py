"""#167's performance budgets, measured on the developers' emulator.

    python tools/team.py device            # frames and start drive the emulator
    python tools/perf.py all               # size, frames, start; exit 1 on a regression
    python tools/team.py device --release

Run with the milestone's full suite and before a release, never per PR (CI
is off, #302). `accessibility-performance.md` has the budgets.

    size      the release APKs split per ABI: the arm64-v8a one's size
    frames    integration_test/perf_test.dart under `flutter drive --profile`
              on a fresh install: five cards rated (card), L2's word list
              flung under glass (list), and R1's search timed per keystroke
    start     the x86_64 split installed over the app: cold and warm
              `am start -W`, the median of five each. Run it after frames
              (as `all` does), which leaves the app past S2.
    all       size, frames, start

    --update-baseline   write today's numbers into tools/perf_baseline.json

A metric fails when it grows past its baseline by more than its margin. The
emulator is not the mid-range phone the budgets are written for, so an
absolute budget is reported, not enforced (the owner checks start on a real
phone before a release) — except search's, which fails only when it is over
its 50 ms *and* over its baseline.

Cold start is `TotalTime`: the process started to Flutter's first frame,
which is S1 — `main` runs `runApp` before bootstrap, so the wait for Today
after it is not in the number. Debug and profile builds log that wait as
`bootstrap: N ms`.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import device  # noqa: E402
from smoke import holds_device  # noqa: E402

APP = TOOLS.parent / "app"
BASELINE = TOOLS / "perf_baseline.json"
SPLITS = APP / "build" / "app" / "outputs" / "flutter-apk"
RESPONSE = APP / "build" / "integration_response_data.json"
ACTIVITY = f"{device.PACKAGE}/.MainActivity"
RUNS = 5

# The search budget is one the emulator can be held to: it is database work,
# not frames. Every other absolute budget is written for a phone.
BUDGET_GATES = {"search"}

# FrameTimingSummarizer's keys, under the names the table shows.
FRAME_KEYS = {
    "build_avg_ms": "average_frame_build_time_millis",
    "build_p90_ms": "90th_percentile_frame_build_time_millis",
    "build_p99_ms": "99th_percentile_frame_build_time_millis",
    "raster_avg_ms": "average_frame_rasterizer_time_millis",
    "raster_p90_ms": "90th_percentile_frame_rasterizer_time_millis",
    "raster_p99_ms": "99th_percentile_frame_rasterizer_time_millis",
    "missed_build": "missed_frame_build_budget_count",
    "missed_raster": "missed_frame_rasterizer_budget_count",
}


def flutter() -> str:
    return shutil.which("flutter") or "flutter"


def run(command: list[str]) -> None:
    if subprocess.run(command, cwd=APP).returncode:
        raise SystemExit(f"failed: {' '.join(command)}")


# --- What is measured --------------------------------------------------------------------------

def build_splits() -> None:
    """The release APKs, one per ABI, built as release.md builds the bundle.
    The ABI's 1000 × n stays out of the version code, so the x86_64 APK can
    replace a profile or release build without a downgrade refusal."""
    run([flutter(), "build", "apk", "--release", "--split-per-abi",
         "--obfuscate", "--split-debug-info=build/symbols",
         "-P", "force-version-code-ignoring-abi=true"])


def measure_size() -> dict[str, float]:
    build_splits()
    # ponytail: the arm64-v8a APK stands in for Play's one-ABI download. Play
    # serves compressed splits of the bundle, and this APK stores its native
    # libraries uncompressed, so a phone downloads well under this: good for
    # growth, not for the absolute number. `bundletool get-size total` on the
    # AAB is the upgrade (bundletool is not installed here).
    apk = SPLITS / "app-arm64-v8a-release.apk"
    return {"size.arm64_mb": round(apk.stat().st_size / 1e6, 2)}


def total_time(am_output: str) -> int:
    """`am start -W`'s TotalTime, in ms."""
    found = re.search(r"^TotalTime:\s*(\d+)", am_output, re.MULTILINE)
    if not found:
        raise SystemExit(f"no TotalTime in `am start -W`'s answer:\n{am_output}")
    return int(found.group(1))


def measure_start(dev: device.Device, build: bool = True) -> dict[str, float]:
    if build:
        build_splits()
    dev.install(SPLITS / "app-x86_64-release.apk")
    launcher = ["-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER"]

    def cold() -> int:
        dev.sh("am", "force-stop", device.PACKAGE)
        ms = total_time(dev.sh("am", "start", "-S", "-W", *launcher, "-n", ACTIVITY))
        time.sleep(4)  # bootstrap and Today, before the next kill
        return ms

    def warm() -> int:
        dev.sh("input", "keyevent", "3")  # HOME
        time.sleep(2)
        ms = total_time(dev.sh("am", "start", "-W", *launcher, "-n", ACTIVITY))
        time.sleep(2)
        return ms

    cold()  # the first run of a new APK: ART's work, not the app's
    colds = [cold() for _ in range(RUNS)]
    warms = [warm() for _ in range(RUNS)]
    print(f"cold {colds} ms, warm {warms} ms")
    return {"start.cold_ms": statistics.median(colds), "start.warm_ms": statistics.median(warms)}


def frame_metrics(prefix: str, summary: dict) -> dict[str, float]:
    return {f"{prefix}.{name}": summary[key] for name, key in FRAME_KEYS.items()}


def search_metrics(keystrokes: list[list]) -> dict[str, float]:
    """[query, [ms, ms, ms]] per keystroke → each one's median, and over those
    the median and the slowest; and the very first run, the cold one."""
    times = [statistics.median(runs) for _, runs in keystrokes]
    return {
        "search.median_ms": round(statistics.median(times), 2),
        "search.max_ms": round(max(times), 2),
        "search.first_ms": round(keystrokes[0][1][0], 2),
    }


def measure_frames(dev: device.Device) -> dict[str, float]:
    RESPONSE.unlink(missing_ok=True)
    dev.run("uninstall", device.PACKAGE)  # the test walks S2 on a fresh install
    dev.sh("pm", "trim-caches", "16G")
    # --no-dds: watchPerformance opens the app's own VM service, which DDS
    # would hold for the driver alone. --keep-app-running: without it drive
    # uninstalls the app, and start would find S2 again.
    run([flutter(), "drive", "--profile", "--no-dds", "--keep-app-running",
         "--driver=test_driver/perf_driver.dart",
         "--target=integration_test/perf_test.dart", "-d", dev.serial])
    dev.sh("am", "force-stop", device.PACKAGE)
    data = json.loads(RESPONSE.read_text(encoding="utf-8"))
    glass = data["glass"]
    print(f"glass blur: {'on' if glass['blur'] else 'OFF ' + ', '.join(glass['reasons'])}")
    slowest = sorted(data["search"]["keystrokes"], key=lambda pair: -statistics.median(pair[1]))[:3]
    print("slowest keystrokes: " + ", ".join(f"{q!r} {runs} ms" for q, runs in slowest))
    return {
        **frame_metrics("card", data["card"]),
        **frame_metrics("list", data["list"]),
        **search_metrics(data["search"]["keystrokes"]),
    }


# --- Verdicts ----------------------------------------------------------------------------------

def lookup(table: dict, metric: str):
    """[metric]'s own entry, else its group's (`start` for `start.cold_ms`)."""
    return table[metric] if metric in table else table.get(metric.split(".")[0])


def verdict(measured: float, baseline: float | None, margin: float | None,
            budget: float | None, budget_gates: bool) -> str:
    over_budget = budget is not None and measured > budget
    if margin is None:
        return "info"
    if baseline is None:
        return "new"
    regressed = measured > baseline * (1 + margin)
    if regressed and (over_budget or not budget_gates):
        return "FAIL"
    return "ok, over budget (info)" if over_budget else "ok"


def report(measured: dict[str, float], doc: dict) -> bool:
    """Prints the table; whether every metric passed."""
    def cell(value) -> str:
        return "-" if value is None else f"{value:.2f}"

    print(f"\n{'metric':<22}{'measured':>10}{'baseline':>10}{'budget':>9}  verdict")
    passed = True
    for metric, value in measured.items():
        baseline = doc["metrics"].get(metric)
        budget = lookup(doc["budgets"], metric)
        result = verdict(value, baseline, lookup(doc["margins"], metric), budget,
                         metric.split(".")[0] in BUDGET_GATES)
        passed &= result != "FAIL"
        print(f"{metric:<22}{cell(value):>10}{cell(baseline):>10}{cell(budget):>9}  {result}")
    return passed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("what", choices=["size", "frames", "start", "all"])
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--device", help=f"the emulator (default: {device.DEV_SERIAL})")
    args = parser.parse_args(argv)
    # A keystroke may be Bangla; a Windows console is cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.what != "size" and not holds_device(device.agent()):
        print("refused: hold the emulator first: `python tools/team.py device`", file=sys.stderr)
        return 2

    measured: dict[str, float] = {}
    if args.what in ("size", "all"):
        measured.update(measure_size())
    if args.what != "size":
        dev = device.Device(args.device)
        if args.what in ("frames", "all"):
            measured.update(measure_frames(dev))
        if args.what in ("start", "all"):
            measured.update(measure_start(dev, build=args.what == "start"))

    doc = json.loads(BASELINE.read_text(encoding="utf-8"))
    passed = report(measured, doc)
    if args.update_baseline:
        doc["metrics"].update(measured)
        BASELINE.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(f"\nbaseline written: {BASELINE.relative_to(TOOLS.parent)}")
        return 0
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
