"""tools/perf.py: #167's parsing and verdicts. No device, no build."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import perf  # noqa: E402

AM_START = """Starting: Intent { cmp=de.sogda.app/.MainActivity }
Status: ok
LaunchState: COLD
Activity: de.sogda.app/.MainActivity
TotalTime: 812
WaitTime: 830
Complete
"""

# The app's own lines name perf.ACTIVITY, whatever the app id is (#170).
LOGCAT = f"""09-26 05:03:15.234   718   749 I ActivityTaskManager: Displayed {perf.ACTIVITY} for user 0: +1s12ms
09-26 05:03:15.901   718   749 I ActivityTaskManager: Fully drawn com.example.other/.MainActivity: +3s1ms
09-26 05:03:16.234   718   749 I ActivityTaskManager: Fully drawn {perf.ACTIVITY}: +1s634ms
"""


def test_the_cold_start_is_read_from_fully_drawn_462():
    assert perf.fully_drawn(LOGCAT) == 1634
    # Under a second Android prints no seconds; Windows' adb ends in \r\n.
    assert perf.fully_drawn(LOGCAT.replace("+1s634ms", "+856ms").replace("\n", "\r\n")) == 856
    # A version that names the user, as Displayed does.
    assert perf.fully_drawn(LOGCAT.replace("MainActivity: +1s634", "MainActivity for user 0: +1s634")) == 1634


def test_another_apps_line_and_none_are_not_a_start_462():
    only_other = "\n".join(line for line in LOGCAT.splitlines() if f"{perf.ACTIVITY}: +1s634" not in line)
    assert perf.fully_drawn(only_other) is None
    assert perf.fully_drawn("") is None


def test_a_start_with_no_fully_drawn_stops_the_run_462():
    with pytest.raises(SystemExit, match="Fully drawn"):
        perf.await_fully_drawn(lambda: "", seconds=0, step=0)
    # One that arrives on a later read is waited for.
    reads = iter(["", LOGCAT])
    assert perf.await_fully_drawn(lambda: next(reads), seconds=5, step=0) == 1634


# What FrameTimingSummarizer.summary reports, trimmed to the keys perf reads
# and two it does not.
SUMMARY = {
    "average_frame_build_time_millis": 3.1,
    "90th_percentile_frame_build_time_millis": 5.2,
    "99th_percentile_frame_build_time_millis": 9.9,
    "worst_frame_build_time_millis": 14.0,
    "missed_frame_build_budget_count": 0,
    "average_frame_rasterizer_time_millis": 6.4,
    "90th_percentile_frame_rasterizer_time_millis": 11.0,
    "99th_percentile_frame_rasterizer_time_millis": 21.5,
    "missed_frame_rasterizer_budget_count": 3,
    "frame_count": 240,
}


def response(blur: bool) -> dict:
    """What perf_test.dart reports, as the driver writes it."""
    return {
        "card": SUMMARY,
        "list": SUMMARY,
        "learn": SUMMARY,
        "today": SUMMARY,
        "docwords": SUMMARY,
        "glass": {"blur": blur, "reasons": [] if blur else ["frameBudget"]},
        "search": {"keystrokes": [["H", [20.0, 10.0, 12.0]], ["Ha", [9.0, 8.0, 30.0]]]},
    }


def test_total_time_is_read_from_am_start_not_wait_time():
    assert perf.total_time(AM_START, "COLD") == 812
    # Windows' adb ends its lines in \r\n.
    assert perf.total_time(AM_START.replace("\n", "\r\n"), "COLD") == 812


def test_a_launch_of_the_wrong_kind_stops_the_run():
    # A "warm" start that found no process was a cold one.
    with pytest.raises(SystemExit, match="HOT"):
        perf.total_time(AM_START, "HOT")
    with pytest.raises(SystemExit):
        perf.total_time(AM_START.replace("COLD", "WARM"), "COLD")


def test_a_failed_start_stops_the_run():
    with pytest.raises(SystemExit):
        perf.total_time(AM_START.replace("Status: ok", "Status: timeout"), "COLD")
    with pytest.raises(SystemExit, match="TotalTime"):
        perf.total_time("Error: Activity class does not exist.", "COLD")


ACTIVITIES = """ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)
  Task display areas in top down Z order:
      * Hist  #1: ActivityRecord{141786944 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t5}
        packageName=com.google.android.apps.nexuslauncher processName=com.google.android.apps.nexuslauncher
        state=RESUMED delayedResume=false finishing=false
      * Hist  #0: ActivityRecord{77 u0 de.sogda.app/.MainActivity t9}
        packageName=de.sogda.app processName=de.sogda.app
        state=STOPPED delayedResume=false finishing=false
    Resumed: ActivityRecord{141786944 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t5}
"""


def test_an_activity_state_is_read_from_its_own_record():
    assert perf.activity_state(ACTIVITIES, "de.sogda.app") == "STOPPED"
    assert perf.activity_state(ACTIVITIES, "com.google.android.apps.nexuslauncher") == "RESUMED"
    # Not running at all.
    assert perf.activity_state(ACTIVITIES, "com.example.other") == ""


def test_a_frame_summary_becomes_the_eight_metrics():
    assert perf.frame_metrics("card", SUMMARY) == {
        "card.build_avg_ms": 3.1,
        "card.build_p90_ms": 5.2,
        "card.build_p99_ms": 9.9,
        "card.raster_avg_ms": 6.4,
        "card.raster_p90_ms": 11.0,
        "card.raster_p99_ms": 21.5,
        "card.missed_build": 0,
        "card.missed_raster": 3,
    }


def test_search_is_the_median_and_the_slowest_keystroke():
    # Each keystroke's own median over the three passes first: one slow run
    # is not its time.
    keystrokes = [
        ["H", [300.0, 30.0, 29.0]],
        ["Ha", [10.0, 90.0, 10.0]],
        ["Hau", [12.0, 12.0, 13.0]],
        ["Haus", [8.0, 7.0, 8.0]],
        ["s", [41.5, 41.5, 40.0]],
    ]
    assert perf.search_metrics(keystrokes) == {
        "search.median_ms": 12.0,
        "search.max_ms": 41.5,
        "search.first_ms": 300.0,
    }


def test_the_response_becomes_the_card_list_and_search_metrics():
    metrics = perf.frames_from(response(blur=True))
    assert metrics["card.raster_p90_ms"] == 11.0
    assert metrics["list.build_avg_ms"] == 3.1
    assert metrics["search.max_ms"] == 12.0
    assert len(metrics) == 5 * 8 + 3


def test_1030_l1_and_today_are_flung_under_glass_with_baselines_of_their_own():
    metrics = perf.frames_from(response(blur=True))
    doc = json.loads(perf.BASELINE.read_text(encoding="utf-8"))
    for screen in ("learn", "today", "docwords"):
        assert metrics[f"{screen}.raster_avg_ms"] == 6.4
        assert perf.lookup(doc["margins"], f"{screen}.raster_avg_ms") == 0.5
        assert perf.lookup(doc["budgets"], f"{screen}.raster_avg_ms") == 16
        assert perf.lookup(doc["margins"], f"year.{screen}.missed_raster") is None
    # Every frame metric perf_test reports is compared, the new ones included,
    # and on the year profile too (#818).
    assert [m for m in metrics if m not in doc["metrics"]] == []
    assert [m for m in metrics if "year." + m not in doc["metrics"]] == []


def test_a_list_trace_without_blur_is_never_measured():
    with pytest.raises(SystemExit, match="frameBudget"):
        perf.frames_from(response(blur=False))


def test_within_the_margin_passes_past_it_fails():
    assert perf.verdict(124, 100, 0.25, None, budget_gates=False) == "ok"
    assert perf.verdict(125, 100, 0.25, None, budget_gates=False) == "ok"
    assert perf.verdict(126, 100, 0.25, None, budget_gates=False) == "FAIL"
    assert perf.verdict(61.0, 60.0, 0.03, None, budget_gates=False) == "ok"
    assert perf.verdict(62.0, 60.0, 0.03, None, budget_gates=False) == "FAIL"


def test_an_absolute_budget_is_information_on_the_emulator():
    # Start at 1.9 s against a 1.5 s budget: the phone is the owner's check.
    assert perf.verdict(1900, 1800, 0.25, 1500, budget_gates=False) == "ok, over budget (info)"
    # Under budget does not excuse a regression either.
    assert perf.verdict(400, 200, 0.25, 500, budget_gates=False) == "FAIL"


def test_search_fails_only_over_its_budget_and_its_baseline():
    assert perf.verdict(40, 20, 0.25, 50, budget_gates=True) == "ok"
    assert perf.verdict(60, 55, 0.25, 50, budget_gates=True) == "ok, over budget (info)"
    assert perf.verdict(80, 55, 0.25, 50, budget_gates=True) == "FAIL"


def test_no_baseline_yet_is_new_and_no_margin_is_information():
    assert perf.verdict(900, None, 0.25, 1500, budget_gates=False) == "new"
    assert perf.verdict(7, 0, None, 0, budget_gates=False) == "info"


def test_a_metric_takes_its_own_margin_before_its_groups():
    margins = {"card": 0.25, "card.missed_build": None}
    assert perf.lookup(margins, "card.build_p90_ms") == 0.25
    assert perf.lookup(margins, "card.missed_build") is None


def test_a_group_with_no_entry_is_an_error_not_information():
    with pytest.raises(SystemExit, match="size"):
        perf.lookup({"card": 0.25}, "size.arm64_mb")


def test_the_baseline_has_a_margin_for_every_group_and_the_budgets():
    doc = json.loads(perf.BASELINE.read_text(encoding="utf-8"))
    for group in ("size", "start", "card", "list", "learn", "today", "docwords", "search"):
        assert doc["margins"][group] > 0
        assert group in doc["budgets"] or any(k.startswith(group + ".") for k in doc["budgets"])
    assert doc["budgets"]["start.cold_ms"] == 1500
    assert doc["budgets"]["start.warm_ms"] == 500
    assert doc["budgets"]["search"] == 50


def test_the_table_fails_on_one_regression(capsys):
    doc = {
        "margins": {"start": 0.25, "search": 0.25},
        "budgets": {"start.cold_ms": 1500, "search": 50},
        "metrics": {"start.cold_ms": 800, "search.max_ms": 20},
    }
    assert perf.report({"start.cold_ms": 900, "search.max_ms": 45}, doc)
    assert not perf.report({"start.cold_ms": 1100, "search.max_ms": 45}, doc)
    assert "FAIL" in capsys.readouterr().out


@pytest.fixture
def baseline(monkeypatch, tmp_path):
    """perf.main over a copy of the real baseline, holding the lock, with a
    size that needs no build."""
    path = tmp_path / "perf_baseline.json"
    path.write_text(perf.BASELINE.read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setattr(perf, "BASELINE", path)
    monkeypatch.setattr(perf, "holds_device", lambda agent: True)
    monkeypatch.setattr(perf, "measure_size", lambda: {"size.arm64_mb": 1.5})
    # Never the real, shared device lock (#697 TL-5).
    monkeypatch.setattr(perf, "keep_device", lambda: None)
    return path


def test_update_baseline_writes_the_numbers_and_keeps_the_rest(baseline):
    before = json.loads(baseline.read_text(encoding="utf-8"))
    assert perf.main(["size", "--update-baseline"]) == 0
    after = json.loads(baseline.read_text(encoding="utf-8"))
    assert after["metrics"]["size.arm64_mb"] == 1.5
    # Margins, budgets and their nulls as they were; other metrics untouched.
    assert after["margins"] == before["margins"]
    assert after["budgets"] == before["budgets"]
    assert after["margins"]["card.missed_build"] is None
    assert {k: v for k, v in after["metrics"].items() if k != "size.arm64_mb"} == {
        k: v for k, v in before["metrics"].items() if k != "size.arm64_mb"
    }


def test_without_the_update_the_baseline_is_left_alone(baseline):
    before = baseline.read_text(encoding="utf-8")
    assert perf.main(["size"]) == 0  # 1.5 MB: far under the baseline
    assert baseline.read_text(encoding="utf-8") == before


def test_even_size_needs_the_device_lock(baseline, monkeypatch):
    monkeypatch.setattr(perf.device, "agent", lambda: "agent-2")
    monkeypatch.setattr(perf, "holds_device", lambda agent: False)
    monkeypatch.setattr(perf, "measure_size", lambda: pytest.fail("built without the lock"))
    assert perf.main(["size"]) == 2


def test_707_the_owners_checkout_measures_without_the_lock(baseline, monkeypatch):
    # Release step 6 runs in the owner's checkout, which has no agent and so
    # no lock to hold, as release_android.py.
    monkeypatch.setattr(perf.device, "owner_checkout", lambda: True)
    monkeypatch.setattr(perf, "holds_device", lambda agent: pytest.fail("asked for a lock"))
    assert perf.main(["size"]) == 0


def test_707_a_worktree_without_its_marker_still_needs_the_lock(baseline, monkeypatch):
    # No agent is not the owner: a helper's worktree that `join` never
    # marked must not drive the shared emulator unlocked.
    monkeypatch.setattr(perf.device, "agent", lambda: "")
    monkeypatch.setattr(perf.device, "owner_checkout", lambda: False)
    monkeypatch.setattr(perf, "holds_device", lambda agent: bool(agent))
    monkeypatch.setattr(perf, "measure_size", lambda: pytest.fail("built without the lock"))
    assert perf.main(["size"]) == 2


def test_707_only_the_main_checkout_is_the_owners(monkeypatch, tmp_path):
    (tmp_path / "main" / ".git").mkdir(parents=True)
    (tmp_path / "worktree").mkdir()
    (tmp_path / "worktree" / ".git").write_text("gitdir: elsewhere", encoding="utf-8")
    monkeypatch.setattr(perf.device, "agent", lambda: "")
    assert perf.device.owner_checkout(tmp_path / "main")
    assert not perf.device.owner_checkout(tmp_path / "worktree")
    monkeypatch.setattr(perf.device, "agent", lambda: "agent-2")
    assert not perf.device.owner_checkout(tmp_path / "main")


def test_697_each_step_refreshes_the_device_lock(baseline, monkeypatch):
    # TL-5: `perf.py all` can outlast the lock's stale window.
    calls = []
    monkeypatch.setattr(perf, "keep_device", lambda: calls.append(1))
    assert perf.main(["size"]) == 0
    assert calls == [1]


def test_818_the_seed_is_done_failed_or_pending_by_what_it_logged():
    assert perf.seed_outcome("I flutter : perf-seed: done\n") is True
    assert perf.seed_outcome("I flutter : starting\n") is None
    with pytest.raises(SystemExit, match="no such table: c.words"):
        perf.seed_outcome("I flutter : perf-seed: failed: no such table: c.words\n")


def test_818_a_year_metric_takes_its_fresh_twins_margin_and_budget():
    doc = json.loads(perf.BASELINE.read_text(encoding="utf-8"))
    assert perf.lookup(doc["margins"], "year.start.cold_ms") == doc["margins"]["start"]
    assert perf.lookup(doc["budgets"], "year.start.cold_ms") == 1500
    assert perf.lookup(doc["margins"], "year.card.missed_build") is None
    # Its own baseline: a year's start is not a fresh one's. A year metric
    # with no baseline yet is new, not a failure.
    doc["metrics"] = {k: v for k, v in doc["metrics"].items() if not k.startswith(perf.YEAR)}
    doc["metrics"]["year.start.cold_ms"] = 900
    assert perf.report({"year.start.cold_ms": 1000, "year.search.max_ms": 60}, doc)
    assert not perf.report({"year.start.cold_ms": 1400}, doc)


def test_818_the_discarded_first_start_may_outlast_am_start(monkeypatch):
    """After the seed, the first launch took 14.5 s to its first frame and
    `am start -W` stopped waiting. It is not measured, so it doesn't stop the run."""
    timeout = AM_START.replace("Status: ok", "Status: timeout").replace("COLD", "UNKNOWN (-1)").replace("TotalTime: 812\n", "")
    colds = [timeout]

    class Dev:
        def run(self, *args):
            pass

        def install(self, apk):
            return True

        def sh(self, *args):
            if args[:2] == ("am", "start"):
                return (colds.pop() if colds else AM_START) if "-S" in args else AM_START.replace("COLD", "HOT")
            return {"dumpsys": ACTIVITIES, "logcat": LOGCAT if "-d" in args else ""}.get(args[0], "")

    monkeypatch.setattr(perf, "seed_year", lambda dev: None)
    monkeypatch.setattr(perf.time, "sleep", lambda seconds: None)
    assert perf.measure_start(Dev(), build=False, year=True) == {"start.cold_ms": 1634, "start.warm_ms": 812}
    assert not colds


@pytest.fixture
def measured(baseline, monkeypatch):
    """Which measurements ran, and with which profile; no device, no build."""
    calls = []

    class Dev:
        def __init__(self, serial=None):
            pass

        def run(self, *args):
            calls.append(("run", *args))

        def sh(self, *args):
            return {"ro.boot.qemu.avd_name": "Pixel_9\r\n", "ro.build.version.sdk": "36\r\n"}[args[-1]]

    monkeypatch.setattr(perf.device, "Device", Dev)
    monkeypatch.setattr(perf, "build_seed", lambda: calls.append("build_seed"))
    monkeypatch.setattr(perf, "measure_frames", lambda dev, year=False: calls.append(("frames", year)) or {"card.build_avg_ms": 4.0})
    monkeypatch.setattr(perf, "measure_start", lambda dev, build=True, year=False: calls.append(("start", year)) or {"start.cold_ms": 900})
    return calls


def test_818_the_year_profile_seeds_first_and_reports_year_metrics(measured, baseline):
    fresh_before = json.loads(baseline.read_text(encoding="utf-8"))["metrics"]["start.cold_ms"]
    assert perf.main(["start", "--profile", "year", "--update-baseline"]) == 0
    assert measured[:2] == ["build_seed", ("start", True)]
    metrics = json.loads(baseline.read_text(encoding="utf-8"))["metrics"]
    assert metrics["year.start.cold_ms"] == 900
    assert metrics["start.cold_ms"] == fresh_before, "the fresh baseline is left alone"


def test_818_a_fresh_run_neither_seeds_nor_prefixes(measured, baseline):
    year_before = json.loads(baseline.read_text(encoding="utf-8"))["metrics"].get("year.card.build_avg_ms")
    assert perf.main(["frames", "--update-baseline"]) == 0
    assert "build_seed" not in measured and ("frames", False) in measured
    metrics = json.loads(baseline.read_text(encoding="utf-8"))["metrics"]
    assert metrics["card.build_avg_ms"] == 4.0 and metrics.get("year.card.build_avg_ms") == year_before


def test_1095_the_baselines_name_their_avd_and_a_run_on_another_says_so(measured, baseline, capsys):
    def avd():
        return json.loads(baseline.read_text(encoding="utf-8"))["avd"]

    doc = json.loads(baseline.read_text(encoding="utf-8"))
    baseline.write_text(json.dumps({**doc, "avd": "Pixel_6 (API 34)"}), encoding="utf-8")
    perf.main(["frames"])  # its verdict is the fake's 4 ms against the real baseline
    assert "recorded on Pixel_6 (API 34), this run is on Pixel_9 (API 36)" in capsys.readouterr().out
    assert avd() == "Pixel_6 (API 34)", "only --update-baseline writes it"

    assert perf.main(["frames", "--update-baseline"]) == 0
    assert avd() == "Pixel_9 (API 36)"
    capsys.readouterr()
    assert perf.main(["frames"]) == 0
    assert "NOTE" not in capsys.readouterr().out, "the same AVD says nothing"
    assert perf.main(["size", "--update-baseline"]) == 0
    assert avd() == "Pixel_9 (API 36)", "a size run has no device and keeps it"


def test_845_the_owners_checkout_refuses_the_emulator_an_agent_holds(measured, monkeypatch, tmp_path):
    monkeypatch.setattr(perf.device, "owner_checkout", lambda: True)
    monkeypatch.setattr(perf.team, "team_root", lambda: tmp_path)
    assert perf.device_held_by() is None
    assert perf.main(["start"]) == 0

    (tmp_path / ".device.lock").mkdir()
    (tmp_path / ".device.lock" / "owner").write_text("agent-2 2026-09-27 10:00\n", encoding="utf-8")
    measured.clear()
    assert perf.main(["start"]) == 2
    assert measured == [], "nothing uninstalled or measured"
    assert perf.main(["size"]) == 0, "a build doesn't touch the emulator"

    # A stale lock is nobody's.
    import os
    old = perf.time.time() - perf.team.DEVICE_LOCK_STALE_SECONDS - 60
    os.utime(tmp_path / ".device.lock", (old, old))
    assert perf.main(["start"]) == 0


def test_705_both_release_builds_opt_in_to_the_debug_key(monkeypatch):
    commands = []
    monkeypatch.setattr(perf, "run", commands.append)
    monkeypatch.setattr(perf.shutil, "copyfile", lambda *args: None)
    perf.build_splits()
    perf.build_seed()
    assert len(commands) == 2
    for command in commands:
        assert command[command.index("allowDebugSigning=true") - 1] == "-P"
