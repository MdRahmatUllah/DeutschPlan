"""tools/device.py: which emulator an agent drives (#310)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import device  # noqa: E402


def test_a_developer_gets_the_developers_emulator():
    assert device.pick_serial(None, "agent-0") == "emulator-5558"
    assert device.pick_serial(None, "") == "emulator-5558"


def test_agent_3_gets_the_sqa_emulator():
    assert device.pick_serial(None, "agent-3") == "emulator-5554"


def test_a_given_serial_is_used():
    assert device.pick_serial("emulator-5556", "agent-1") == "emulator-5556"


def test_the_sqa_emulator_is_refused_to_anyone_else():
    with pytest.raises(SystemExit, match="agent-3"):
        device.pick_serial("emulator-5554", "agent-1")
    with pytest.raises(SystemExit):
        device.pick_serial("emulator-5554", "")
