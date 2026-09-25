"""tools/smoke.py: #169's driver — the lock, the order, the stop. No device."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import smoke  # noqa: E402


@pytest.fixture
def run(monkeypatch, tmp_path):
    """Every command smoke.py runs, answered from `codes` (a token in the
    command → its exit code); 0 otherwise, and 1 for pidof — no process."""
    monkeypatch.setenv("DP_TEAM_ROOT", str(tmp_path))
    monkeypatch.setattr(smoke.device, "agent", lambda: "agent-0")
    monkeypatch.setattr(smoke.device, "adb_path", lambda: "adb")
    monkeypatch.setattr(smoke.shutil, "which", lambda _: "flutter")
    calls: list[list[str]] = []
    codes: dict[str, int] = {"pidof": 1}

    def fake(command, cwd=None):
        calls.append(command)
        code = next((c for token, c in codes.items() if token in " ".join(command)), 0)
        return subprocess.CompletedProcess(command, code)

    monkeypatch.setattr(smoke.subprocess, "run", fake)
    return tmp_path, calls, codes


def hold(root: Path, agent: str) -> None:
    (root / ".device.lock").mkdir()
    (root / ".device.lock" / "owner").write_text(f"{agent} 2026-09-25 10:00\n", encoding="utf-8")


def test_refused_without_the_device_lock(run):
    _, calls, _ = run
    assert smoke.main([]) == 2
    assert calls == []


def test_refused_while_another_agent_holds_it(run):
    root, calls, _ = run
    hold(root, "agent-1")
    assert smoke.main([]) == 2
    assert calls == []


def test_fresh_install_first_day_exam_start_kill_then_resume(run):
    root, calls, _ = run
    hold(root, "agent-0")
    assert smoke.main([]) == 0
    assert calls[0] == ["adb", "-s", "emulator-5558", "uninstall", "com.example.deutschplan"]
    tests = [c[-1] for c in calls if c[:2] == ["flutter", "test"]]
    assert tests == [
        "integration_test/first_day_test.dart",
        "integration_test/exam_start_test.dart",
        "integration_test/exam_resume_test.dart",
    ]
    # Kept installed between runs, or user.db goes with the app.
    assert all("--no-uninstall" in c and "emulator-5558" in c for c in calls if c[0] == "flutter")
    joined = [" ".join(c) for c in calls]
    start = joined.index(next(j for j in joined if "exam_start" in j))
    assert "am force-stop com.example.deutschplan" in joined[start + 1]
    assert "pidof" in joined[start + 2]
    assert "exam_resume" in joined[start + 3]


def test_stops_at_the_first_failure(run):
    root, calls, codes = run
    hold(root, "agent-0")
    codes["exam_start"] = 1
    assert smoke.main(["--device", "emulator-5556"]) == 1
    assert "exam_start" in calls[-1][-1]
    assert "-d" in calls[-1] and "emulator-5556" in calls[-1]


def test_a_process_left_running_after_the_kill_fails(run):
    root, calls, codes = run
    hold(root, "agent-0")
    codes["pidof"] = 0
    assert smoke.main([]) == 1
    assert not any("exam_resume" in " ".join(c) for c in calls)
