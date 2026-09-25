"""tools/perf.py: #167's parsing and verdicts. No device, no build."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import perf  # noqa: E402

AM_START = """Starting: Intent { cmp=com.example.deutschplan/.MainActivity }
Status: ok
LaunchState: COLD
Activity: com.example.deutschplan/.MainActivity
TotalTime: 812
WaitTime: 830
Complete
"""

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


def test_total_time_is_read_from_am_start():
    assert perf.total_time(AM_START) == 812


def test_waittime_is_not_mistaken_for_totaltime():
    assert perf.total_time("WaitTime: 99\nTotalTime: 40\n") == 40


def test_no_total_time_stops_the_run():
    try:
        perf.total_time("Error: Activity class does not exist.")
    except SystemExit as stop:
        assert "TotalTime" in str(stop)
    else:
        raise AssertionError("a missing TotalTime must stop the run")


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
    # Each keystroke's own median first: one slow run is not its time.
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
    assert perf.lookup(margins, "size.arm64_mb") is None


def test_the_baseline_has_a_margin_for_every_group_and_the_budgets():
    doc = json.loads(perf.BASELINE.read_text(encoding="utf-8"))
    for group in ("size", "start", "card", "list", "search"):
        assert doc["margins"][group] > 0
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
