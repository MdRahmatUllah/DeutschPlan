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


class _Adb:
    """Stands in for adb: answers each `install` with the next reply."""

    def __init__(self, *replies: tuple[bytes, bytes]):
        self.replies = list(replies)
        self.calls: list[tuple[str, ...]] = []

    def __call__(self, *args: str, check: bool = False):
        self.calls.append(args)
        out, err = self.replies.pop(0) if args[0] == "install" else (b"", b"")
        return type("Done", (), {"stdout": out, "stderr": err})()


def _device(tmp_path, monkeypatch, adb):
    monkeypatch.setattr(device, "adb_path", lambda: "adb")
    dev = device.Device("emulator-5558", tmp_path)
    monkeypatch.setattr(dev, "run", adb)
    apk = tmp_path / "app.apk"
    apk.write_bytes(b"apk")
    return dev, apk


def test_697_an_install_refused_on_stderr_is_a_failure(tmp_path, monkeypatch, capsys):
    # TL-4: adb says `Failure [...]` on stderr, and nothing useful on stdout.
    dev, apk = _device(tmp_path, monkeypatch, _Adb(
        (b"Performing Streamed Install\n", b"adb: failed to install app.apk: Failure [INSTALL_FAILED_VERSION_DOWNGRADE]\n")))
    assert dev.install(apk) is False
    # The refusal is what it prints, not stdout's "Performing Streamed Install".
    assert "INSTALL_FAILED_VERSION_DOWNGRADE" in capsys.readouterr().out
    dev, apk = _device(tmp_path, monkeypatch, _Adb((b"Performing Streamed Install\nSuccess\n", b"")))
    assert dev.install(apk) is True


def test_697_insufficient_storage_on_stderr_trims_and_retries(tmp_path, monkeypatch):
    adb = _Adb((b"", b"Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]\n"), (b"Success\n", b""))
    dev, apk = _device(tmp_path, monkeypatch, adb)
    assert dev.install(apk) is True
    assert ("shell", "pm", "trim-caches", "16G") in adb.calls


def test_697_a_failed_install_stops_the_steps(tmp_path, monkeypatch):
    monkeypatch.setattr(device, "adb_path", lambda: "adb")
    monkeypatch.setattr(device.Device, "install", lambda self, apk=None: False)
    monkeypatch.setattr(device.Device, "launch", lambda self: pytest.fail("launched the old app"))
    assert device.main(["--serial", "emulator-5558", "install", "launch"]) == 1
