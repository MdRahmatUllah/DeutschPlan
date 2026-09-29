"""#167's performance budgets, measured on the developers' emulator.

    python tools/team.py device            # every step: APK builds and the emulator
    python tools/perf.py all               # size, frames, start; exit 1 on a regression
    python tools/team.py device --release

Run with the milestone's full suite and before a release, never per PR (CI
is off, #302). `accessibility-performance.md` has the budgets.

    size      the release APKs split per ABI: the arm64-v8a one's size
    frames    integration_test/perf_test.dart under `flutter drive --profile`
              on a fresh install: five cards rated (card), L2's word list,
              L1's step list and Today flung under glass (list, learn,
              today), and R1's search timed per keystroke
    start     the x86_64 split on a fresh install, S2 walked with its
              defaults (A1.1, the default theme, day 1 unstudied): cold and
              warm `am start -W`, the median of five each
    all       size, frames, start

    --profile year   frames and start on a learner with a year behind them
              (#818): about 13,500 ratings with their plan rows and
              daily_stats, seeded by app/integration_test/year_profile.dart.
              Frames seeds it inside the test; start builds
              integration_test/perf_seed.dart as a release APK of its own,
              runs it once, and installs the app's APK over it (the same id
              and key, so user.db stays). Its metrics are `year.<metric>`,
              with their own baselines and the fresh ones' margins and
              budgets.

The app is uninstalled at the start and the end, so the next agent finds
neither a profile build nor a glass theme nor a studied day. Its data goes
with it, a downloaded voice model included: re-download it if a check needs
it.

    --update-baseline   write today's numbers into tools/perf_baseline.json

A metric fails when it grows past its baseline by more than its margin. The
emulator is not the mid-range phone the budgets are written for, so an
absolute budget is reported, not enforced (the owner checks start on a real
phone before a release) — except search's, which fails only when it is over
its 50 ms *and* over its baseline.

The owner's checkout takes no lock, but refuses to drive the emulator while
an agent holds it (#845).

Cold start ends at Android's `Fully drawn`, which the app reports once
Today shows its plan (#462), read from logcat. `am start -W`'s `TotalTime`
ends at Flutter's first frame, which is only S1: `main` runs `runApp` before
bootstrap. A warm start resumes on Today, so its `TotalTime` is Today's, and
Android reports fully drawn only once per Activity, so warm stays on it.
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
import team  # noqa: E402
from smoke import holds_device  # noqa: E402

APP = TOOLS.parent / "app"
BASELINE = TOOLS / "perf_baseline.json"
SPLITS = APP / "build" / "app" / "outputs" / "flutter-apk"
RESPONSE = APP / "build" / "integration_response_data.json"
SEED_APK = APP / "build" / "perf-seed.apk"
# #705: without app/android/key.properties a release build fails unless it opts
# in to the debug key; with the file, the upload key signs it all the same.
DEBUG_SIGNING = "allowDebugSigning=true"
YEAR = "year."
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
    `force-version-code-ignoring-abi` keeps each at pubspec's version code N:
    a split APK's is otherwise 1000 × its ABI's number + N (4000 + N for
    x86_64), and the next agent's plain release build, N, would be refused
    over it as a downgrade — should the uninstall at the end not have run."""
    run([flutter(), "build", "apk", "--release", "--split-per-abi",
         "--obfuscate", "--split-debug-info=build/perf-symbols",  # not the AAB's (#697 TL-9)
         "-P", "force-version-code-ignoring-abi=true", "-P", DEBUG_SIGNING])


def build_seed() -> None:
    """integration_test/perf_seed.dart as a release APK, kept aside from the
    splits: the app's own id, key and version code, so the measured APK
    installs over it and keeps what it seeded (#818)."""
    run([flutter(), "build", "apk", "--release", "--target-platform", "android-x64",
         "-t", "integration_test/perf_seed.dart", "-P", DEBUG_SIGNING])
    shutil.copyfile(SPLITS / "app-release.apk", SEED_APK)


def seed_outcome(logcat: str) -> bool | None:
    """Whether perf_seed.dart said it was done, or failed (which stops the
    run, saying why); None while it has said neither."""
    if "perf-seed: done" in logcat:
        return True
    failed = re.search(r"perf-seed: failed: (.*)", logcat)
    if failed:
        raise SystemExit(f"the year profile was not seeded: {failed.group(1)}")
    return None


def seed_year(dev: device.Device, seconds: float = 300) -> None:
    """A year of study in the app's user.db, before its own APK goes on (#818)."""
    if not dev.install(SEED_APK):
        raise SystemExit("the seed APK did not install")
    dev.sh("logcat", "-c")
    dev.launch()
    deadline = time.time() + seconds
    while not seed_outcome(dev.sh("logcat", "-d", "-s", "flutter")):
        if time.time() > deadline:
            raise SystemExit("perf_seed.dart never said it was done")
        time.sleep(1)
    dev.sh("am", "force-stop", device.PACKAGE)


def measure_size() -> dict[str, float]:
    build_splits()
    # ponytail: the arm64-v8a APK stands in for Play's one-ABI download. Play
    # serves compressed splits of the bundle, and this APK stores its native
    # libraries uncompressed, so a phone downloads well under this: good for
    # growth, not for the absolute number. `bundletool get-size total` on the
    # AAB is the upgrade (bundletool is not installed here).
    apk = SPLITS / "app-arm64-v8a-release.apk"
    return {"size.arm64_mb": round(apk.stat().st_size / 1e6, 2)}


def total_time(am_output: str, launch: str) -> int:
    """`am start -W`'s TotalTime in ms, when it answered `Status: ok` for a
    [launch] launch (COLD, HOT). A warm run that found no process is a cold
    one, and would read as a regression."""
    fields = dict(re.findall(r"^(\w+): (.*?)\s*$", am_output, re.MULTILINE))
    if fields.get("Status") != "ok" or fields.get("LaunchState") != launch or "TotalTime" not in fields:
        raise SystemExit(f"not a {launch} launch with `Status: ok` and a TotalTime:\n{am_output}")
    return int(fields["TotalTime"])


def fully_drawn(logcat: str) -> int | None:
    """The app's `Fully drawn` time in ms (#462), or None while logcat has
    none. Android prints `+1s234ms` or `+856ms`; another app's line is not
    this one's."""
    found = re.search(
        rf"Fully drawn {re.escape(ACTIVITY)}(?: for user \d+)?: \+(?:(\d+)s)?(\d+)ms", logcat
    )
    if found is None:
        return None
    return int(found.group(1) or 0) * 1000 + int(found.group(2))


def await_fully_drawn(read, seconds: float = 60, step: float = 0.5) -> int:
    """[fully_drawn] of what [read] gives, polled until it's there: a
    loaded host has taken 13 s to Today. A start that never gets there (a
    deep link, a crash) stops the run after [seconds], saying why."""
    deadline = time.time() + seconds
    while (ms := fully_drawn(read())) is None:
        if time.time() > deadline:
            raise SystemExit("no `Fully drawn` in logcat: the start never reached Today (#462)")
        time.sleep(step)
    return ms


def activity_state(dump: str, package: str) -> str:
    """The state `dumpsys activity activities` gives [package]'s activity
    (RESUMED, PAUSED, STOPPED...); empty when it lists none."""
    for record in re.split(r"\n\s*\* Hist\s+#\d+: ", dump)[1:]:
        if package in record.split("\n", 1)[0]:
            found = re.search(r"^\s*state=(\w+)", record, re.MULTILINE)
            return found.group(1) if found else ""
    return ""


def walk_setup(dev: device.Device) -> None:
    """Launches a fresh install and walks S2's five pages with their
    defaults to Today, tapping what app_en.arb calls each (English is the
    app's default language)."""
    arb = json.loads((APP / "lib" / "l10n" / "app_en.arb").read_text(encoding="utf-8"))
    dev.launch()
    dev.tap(arb["onboardingWelcomeStart"])
    for page in ("onboardingMeaningHeadline", "onboardingStartHeadline", "onboardingPaceHeadline"):
        dev.wait(arb[page], anywhere=True)
        dev.tap(arb["continueAction"])
    dev.wait(arb["onboardingVoiceHeadline"], anywhere=True)
    dev.tap(arb["onboardingStartLearning"])
    dev.wait(arb["todayCourseDay"].split("}")[-1], anywhere=True)  # "Day 1 of your course"


def measure_start(dev: device.Device, build: bool = True, year: bool = False) -> dict[str, float]:
    """The same state every run: a fresh install past S2, on Today; or, with
    [year], a year of study seeded first, which opens on Today (#818)."""
    if build:
        build_splits()
    dev.run("uninstall", device.PACKAGE)
    if year:
        seed_year(dev)
    if not dev.install(SPLITS / "app-x86_64-release.apk"):
        raise SystemExit("the release x86_64 APK did not install")
    if not year:
        walk_setup(dev)
    launcher = ["-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER"]

    firsts: list[int] = []

    def cold(measured: bool = True) -> int:
        dev.sh("logcat", "-c")
        # -S: force-stopped first. TotalTime is S1's first frame, kept to
        # show against Today's.
        am = dev.sh("am", "start", "-S", "-W", *launcher, "-n", ACTIVITY)
        if measured:
            firsts.append(total_time(am, "COLD"))
        return await_fully_drawn(lambda: dev.sh("logcat", "-d"))

    def warm() -> int:
        dev.sh("input", "keyevent", "3")  # HOME
        # Until the app has stopped, which a loaded host can take seconds
        # over: started before, it is not launched at all (LaunchState
        # UNKNOWN, no TotalTime).
        deadline = time.time() + 30
        while activity_state(dev.sh("dumpsys", "activity", "activities"), device.PACKAGE) != "STOPPED":
            if time.time() > deadline:
                raise SystemExit("HOME never stopped the app")
            time.sleep(0.5)
        time.sleep(1)
        ms = total_time(dev.sh("am", "start", "-W", *launcher, "-n", ACTIVITY), "HOT")
        time.sleep(2)
        return ms

    # The first run of a new APK: ART's work, not the app's, so not measured.
    # On a year it also plans the day over that history (#818), and took
    # 14.5 s to its first frame on emulator-5558, past what `am start -W`
    # waits for (`Status: timeout`): only its Fully drawn is read, and printed.
    first = cold(measured=False)
    colds = [cold() for _ in range(RUNS)]
    warms = [warm() for _ in range(RUNS)]
    print(f"cold {colds} ms (first frame {firsts} ms; the discarded first run {first} ms), warm {warms} ms")
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


def frames_from(data: dict) -> dict[str, float]:
    """What perf_test.dart reported → the metrics. A glass trace that ran
    without its BackdropFilter measured something else: it is never compared,
    and never written as the baseline."""
    glass = data["glass"]
    if not glass["blur"]:
        raise SystemExit(f"glass did not blur ({', '.join(glass['reasons'])}): the glass traces are not the budgeted ones")
    return {
        **frame_metrics("card", data["card"]),
        **frame_metrics("list", data["list"]),
        **frame_metrics("learn", data["learn"]),  # #1030: L1 and Today under glass
        **frame_metrics("today", data["today"]),
        **search_metrics(data["search"]["keystrokes"]),
    }


def measure_frames(dev: device.Device, year: bool = False) -> dict[str, float]:
    RESPONSE.unlink(missing_ok=True)
    dev.run("uninstall", device.PACKAGE)  # the test walks S2 on a fresh install
    dev.sh("pm", "trim-caches", "16G")
    # --no-dds: watchPerformance reads the timeline through the VM service
    # from inside the app. With DDS started, the VM service answers DDS alone,
    # and DDS listens on the host, where the app cannot reach it. Drive stops
    # and uninstalls the app when it is done.
    run([flutter(), "drive", "--profile", "--no-dds",
         "--driver=test_driver/perf_driver.dart",
         "--target=integration_test/perf_test.dart", "-d", dev.serial,
         *(["--dart-define=SG_PERF_PROFILE=year"] if year else [])])
    data = json.loads(RESPONSE.read_text(encoding="utf-8"))
    slowest = sorted(data["search"]["keystrokes"], key=lambda pair: -statistics.median(pair[1]))[:3]
    print("slowest keystrokes: " + ", ".join(f"{q!r} {runs} ms" for q, runs in slowest))
    return frames_from(data)


# --- Verdicts ----------------------------------------------------------------------------------

def lookup(table: dict, metric: str):
    """[metric]'s own entry, else its group's (`start` for `start.cold_ms`).
    Null is an answer (no margin: information only; no budget); no entry
    at all is a mistake in perf_baseline.json. A year-profile metric takes
    its fresh twin's (#818)."""
    metric = metric.removeprefix(YEAR)
    group = metric.split(".")[0]
    if metric in table:
        return table[metric]
    if group in table:
        return table[group]
    raise SystemExit(f"perf_baseline.json has no entry for {metric} or its group {group!r}")


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
                         metric.removeprefix(YEAR).split(".")[0] in BUDGET_GATES)
        passed &= result != "FAIL"
        print(f"{metric:<22}{cell(value):>10}{cell(baseline):>10}{cell(budget):>9}  {result}")
    return passed


def keep_device() -> None:
    """Refreshes the device lock before each long step, so `perf.py all`
    never outlives the lock's 45-minute stale window (#697 TL-5)."""
    try:
        team.cmd_device(team.team_root(), device.agent(), release=False, refresh=True)
    except team.Refused:
        pass  # main checked the holder already


def device_held_by() -> str | None:
    """Who holds `team.py device`, while their lock is fresh."""
    lock = team.team_root() / ".device.lock"
    try:
        if time.time() - lock.stat().st_mtime < team.DEVICE_LOCK_STALE_SECONDS:
            return (lock / "owner").read_text(encoding="utf-8").strip() or "?"
    except FileNotFoundError:
        pass
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("what", choices=["size", "frames", "start", "all"])
    parser.add_argument("--profile", choices=["fresh", "year"], default="fresh",
                        help="frames and start on a fresh install, or on a year of study (#818)")
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--device", help=f"the emulator (default: {device.DEV_SERIAL})")
    args = parser.parse_args(argv)
    # A keystroke may be Bangla; a Windows console is cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    # An APK build takes the lock too (CLAUDE.md), so size needs it as well.
    # The owner's own checkout has no agent and no lock to take (release step
    # 6), as release_android.py (#707).
    if not device.owner_checkout() and not holds_device(device.agent()):
        print("refused: hold the emulator first: `python tools/team.py device`", file=sys.stderr)
        return 2
    # The owner takes no lock, but must not uninstall the app from under an
    # agent's device check (#845).
    holder = device.owner_checkout() and args.what != "size" and device_held_by()
    if holder:
        print(f"refused: an agent is using the emulator ({holder}): "
              "try again once it is released", file=sys.stderr)
        return 2

    year = args.profile == "year"
    prefix = YEAR if year else ""
    measured: dict[str, float] = {}
    if year and args.what in ("start", "all"):
        keep_device()
        build_seed()  # before the splits: its build shares their folder
    if args.what in ("size", "all"):
        keep_device()
        measured.update(measure_size())
    if args.what != "size":
        dev = device.Device(args.device)
        try:
            if args.what in ("frames", "all"):
                keep_device()
                measured.update({prefix + k: v for k, v in measure_frames(dev, year).items()})
            if args.what in ("start", "all"):
                keep_device()
                start = measure_start(dev, build=args.what == "start", year=year)
                measured.update({prefix + k: v for k, v in start.items()})
        finally:
            print("perf: uninstalling the app (its data and any voice model go)")
            dev.run("uninstall", device.PACKAGE)

    doc = json.loads(BASELINE.read_text(encoding="utf-8"))
    passed = report(measured, doc)
    if args.update_baseline:
        if not passed:
            # Deliberate re-baselining (a feature that grows the app) is the
            # point of the flag; doing it over a regression by accident is not.
            print(
                "\nWARNING: this run FAILED against the old baseline, and "
                "becomes the new one. Check the table above first."
            )
        doc["metrics"].update(measured)
        BASELINE.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(f"\nbaseline written: {BASELINE}")
        return 0
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
