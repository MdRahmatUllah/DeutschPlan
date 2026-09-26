"""tools/perf.py: #167's parsing and verdicts. No device, no build."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import perf  # noqa: E402

AM_START = """Starting: Intent { cmp=io.github.rahmatullah.deutschplan/.MainActivity }
Status: ok
LaunchState: COLD
Activity: io.github.rahmatullah.deutschplan/.MainActivity
TotalTime: 812
WaitTime: 830
Complete
"""

LOGCAT = """09-26 05:03:15.234   718   749 I ActivityTaskManager: Displayed com.example.deutschplan/.MainActivity for user 0: +1s12ms
09-26 05:03:15.901   718   749 I ActivityTaskManager: Fully drawn com.example.other/.MainActivity: +3s1ms
09-26 05:03:16.234   718   749 I ActivityTaskManager: Fully drawn com.example.deutschplan/.MainActivity: +1s634ms
"""


def test_the_cold_start_is_read_from_fully_drawn_462():
    assert perf.fully_drawn(LOGCAT) == 1634
    # Under a second Android prints no seconds; Windows' adb ends in \r\n.
    assert perf.fully_drawn(LOGCAT.replace("+1s634ms", "+856ms").replace("\n", "\r\n")) == 856
    # A version that names the user, as Displayed does.
    assert perf.fully_drawn(LOGCAT.replace("MainActivity: +1s634", "MainActivity for user 0: +1s634")) == 1634


def test_another_apps_line_and_none_are_not_a_start_462():
    only_other = "\n".join(line for line in LOGCAT.splitlines() if "deutschplan/.MainActivity: +1s634" not in line)
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
      * Hist  #0: ActivityRecord{77 u0 io.github.rahmatullah.deutschplan/.MainActivity t9}
        packageName=io.github.rahmatullah.deutschplan processName=io.github.rahmatullah.deutschplan
        state=STOPPED delayedResume=false finishing=false
    Resumed: ActivityRecord{141786944 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t5}
"""


def test_an_activity_state_is_read_from_its_own_record():
    assert perf.activity_state(ACTIVITIES, "io.github.rahmatullah.deutschplan") == "STOPPED"
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
    assert len(metrics) == 8 + 8 + 3


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
    for group in ("size", "start", "card", "list", "search"):
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
    monkeypatch.setattr(perf, "holds_device", lambda agent: False)
    monkeypatch.setattr(perf, "measure_size", lambda: pytest.fail("built without the lock"))
    assert perf.main(["size"]) == 2
