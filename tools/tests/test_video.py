"""#1206: the video tool's scripts, captions and ffmpeg graph (the recording
and the render need the emulator, ffmpeg and Chromium: the device check)."""

from __future__ import annotations

import sys
from types import SimpleNamespace
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "media"))

import video  # noqa: E402

GOOD = {
    "name": "t",
    "locales": ["en", "bn"],
    "steps": ["launch", "sleep2"],
    "cut": [1, 11],
    "captions": [
        {"from": 0, "to": 4, "text": {"en": "From A1 to C2.2", "bn": "A1 থেকে C2"}},
        {"from": 4.5, "to": 10, "text": {"en": "{totals.words} words", "bn": "{totals.words}টি শব্দ"}},
    ],
}


def with_(**change) -> dict:
    return {**GOOD, **change}


def test_the_committed_scripts_load_and_fill_their_facts():
    for name in ("study-day", "bangla-guide"):
        script = video.load(name)
        assert {"en", "bn"} <= set(script["locales"])
        for lang in script["locales"]:
            assert all(text for _, _, text in video.captions(script, lang))


def test_a_caption_takes_its_numbers_from_the_facts_each_languages_way():
    video.check(GOOD)
    words = video.fill("{totals.words}", "en")
    assert video.captions(GOOD, "en")[1][2] == f"{words} words"
    assert video.captions(GOOD, "bn")[1][2].startswith(words.translate(str.maketrans("0123456789", "০১২৩৪৫৬৭৮৯")))


@pytest.mark.parametrize("script, why", [
    (with_(captions=[{"from": 0, "to": 4, "text": {"en": "5142 words", "bn": "শব্দ"}}]), "types a number"),
    (with_(captions=[{"from": 0, "to": 4, "text": {"en": "Words"}}]), "has no bn"),
    (with_(captions=[{"from": 0, "to": 4, "text": {"en": "a", "bn": "b"}},
                     {"from": 3, "to": 6, "text": {"en": "a", "bn": "b"}}]), "must follow"),
    (with_(captions=[{"from": 8, "to": 12, "text": {"en": "a", "bn": "b"}}]), "stay in the cut"),
    (with_(cut=[5, 5]), "cut must be"),
    (with_(steps=[]), "steps must be"),
])
def test_a_broken_script_is_refused(script, why):
    with pytest.raises(video.ScriptError, match=why):
        video.check(script)


def test_the_graph_switches_the_frames_on_the_captions_and_trims_to_the_cut(tmp_path):
    frames = [tmp_path / f"{i}.png" for i in range(3)]
    box = {"x": 210, "y": 500, "w": 640, "h": 1436}
    args = video.ffmpeg_args(tmp_path / "raw.mp4", frames, box, [(0, 4), (4.5, 10)], [1, 11],
                             tmp_path / "out.mp4")
    graph = args[args.index("-filter_complex") + 1]
    assert "trim=duration=10" in graph
    assert "[1:v][2:v]overlay=enable='between(t,0,4)'" in graph
    assert "overlay=enable='between(t,4.5,10)'" in graph
    assert graph.endswith("overlay=210:500:shortest=1,format=yuv420p[out]")
    assert args[args.index("-map", args.index("[out]")) + 1] == "4:a", "the silent track"
    assert ["-ss", "1", "-to", "11"] == args[4:8]


def test_the_caption_block_is_the_same_size_whatever_the_caption():
    vertical, landscape = video.layout("vertical", "bn"), video.layout("landscape", "en")
    assert vertical["direction"] == "column" and landscape["direction"] == "row"
    assert vertical["caption_extent"] >= video.CAPTION_LINES * vertical["caption"] * vertical["line_height"]


def test_a_caption_with_a_dollar_or_markup_is_drawn_as_written():
    html = video.frame_html("vertical", "en", "Save $5 & ${totals} <b>", {"inter": "", "bengali": ""})
    assert "Save $5 &amp; ${totals} &lt;b>" in html


def test_shell_steps_run_between_device_steps_in_order(monkeypatch):
    calls: list[tuple] = []
    monkeypatch.setattr(video.device, "main", lambda argv: calls.append(("device", *argv[2:])) or 0)
    monkeypatch.setattr(video.subprocess, "run", lambda args, check: calls.append(("shell", args[-1])))
    script = {"name": "t", "steps": ["sleep2", "shell:am start -n x/.Main", "at:1,2", "sleep1"]}
    video.walk(script, ["adb", "shell"], "emulator-5558")
    assert calls == [("device", "sleep2"), ("shell", "am start -n x/.Main"),
                     ("device", "at:1,2", "sleep1")]


def test_before_and_after_are_shell_commands():
    video.check(with_(before=["cmd connectivity airplane-mode enable"], after=["x"]))
    with pytest.raises(video.ScriptError, match="before must be"):
        video.check(with_(before=[["not", "a", "string"]]))


def test_after_runs_however_the_recording_ends(monkeypatch):
    # The shared emulator is left as it was: flight mode off again (#1245).
    ran: list[str] = []
    monkeypatch.setattr(video.device, "adb_path", lambda: "adb")
    monkeypatch.setattr(video.subprocess, "run", lambda args, check: ran.append(args[-1]))
    monkeypatch.setattr(video.subprocess, "Popen", lambda args: SimpleNamespace(wait=lambda timeout: 0))
    monkeypatch.setattr(video.time, "sleep", lambda seconds: None)

    def broken(*_):
        raise SystemExit("a step failed")

    monkeypatch.setattr(video, "walk", broken)
    script = {"name": "t", "steps": ["sleep1"], "cut": [0, 1], "before": ["on"], "after": ["off"]}
    with pytest.raises(SystemExit):
        video.record(script)
    assert ran == ["on", "screenrecord", "off"]


@pytest.mark.parametrize("takes, why", [
    ({"en": {"locales": ["en", "pl"]}}, "some of the script's locales"),
    ({"en": {"locales": ["en"]}, "also": {"locales": ["en", "bn"]}}, "a locale is in two takes"),
    ({"bn": {"locales": ["bn"], "prepare": [["not", "a", "step"]]}}, "prepare must be device.py steps"),
])
def test_a_broken_take_is_refused(takes, why):
    with pytest.raises(video.ScriptError, match=why):
        video.check(with_(takes=takes))


def test_each_locale_is_cut_from_its_own_takes_recording_1355():
    script = with_(takes={"bn": {"locales": ["bn"], "prepare": ["launch"]}})
    video.check(script)
    assert video.raw_of(script, "bn").name == "t-bn.mp4"
    assert video.raw_of(script, "en").name == "t.mp4", "no take: the one recording"
    assert video.raw_of(script, take="bn") == video.raw_of(script, "bn")


def test_a_take_prepares_its_learner_unrecorded_before_flight_mode_goes_on(monkeypatch, tmp_path):
    ran: list[str] = []

    def run(args, check, **_):
        ran.append(args[-1])
        if "pull" in args:
            Path(args[-1]).write_bytes(b"mp4")

    monkeypatch.setattr(video, "RAW", tmp_path)
    monkeypatch.setattr(video.device, "adb_path", lambda: "adb")
    monkeypatch.setattr(video.subprocess, "run", run)
    monkeypatch.setattr(video.subprocess, "Popen", lambda args: ran.append("recording") or SimpleNamespace(wait=lambda timeout: 0))
    monkeypatch.setattr(video.time, "sleep", lambda seconds: None)
    monkeypatch.setattr(video, "walk", lambda script, shell, serial: ran.append(" ".join(script["steps"])))
    script = with_(takes={"bn": {"locales": ["bn"], "prepare": ["launch", "tap:শুরু করি"]}},
                   before=["on"], after=["off"])
    assert video.record(script, "emulator-5556", "bn").name == "t-bn.mp4"
    assert ran[:5] == ["launch tap:শুরু করি", "on", "recording", "launch sleep2", "screenrecord"]
    assert "off" in ran


def test_the_recording_never_reaches_sqas_emulator_whatever_the_lock_1372(monkeypatch):
    monkeypatch.setattr(video, "holds", lambda serial, agent: True)
    monkeypatch.setattr(video.device, "agent", lambda: "agent-2")
    monkeypatch.setattr(video, "record", lambda *_: pytest.fail("recorded on SQA's emulator"))
    with pytest.raises(SystemExit, match="emulator-5554 is agent-3's"):
        video.main(["flight-mode", "--record", "--serial", "emulator-5554"])


def test_an_unknown_take_is_named_not_a_key_error_1372(monkeypatch):
    monkeypatch.setattr(video, "holds", lambda serial, agent: True)
    monkeypatch.setattr(video, "record", lambda *_: pytest.fail("recorded"))
    with pytest.raises(SystemExit, match="has no take xx"):
        video.main(["flight-mode", "--record", "--serial", "emulator-5556", "--takes", "en,xx"])


def test_another_emulator_records_only_under_its_board_lock_1236(tmp_path, monkeypatch):
    # The media lane's emulator-5556 is held with `team.py lock emulator-5556`, not `team.py device`.
    # Every agent asked about gets this fixture board: a missing one would be
    # cloned from the real team branch, and the test would read live locks.
    board = (
        "## Tasks\n\n| # | MS | Lane | Pri | Size | Title | Status | Owner | Blocked by | PR |\n"
        "|---|---|---|---|---|---|---|---|---|---|\n\n"
        "## Locks\n\n| Resource | Owner | Since | Why |\n|---|---|---|---|\n"
        "| emulator-5556 | agent-5 | 2026-10-03 13:00 | #1236 |\n| pubspec |  |  |  |\n\n## Handoffs\n"
    )
    for agent in ("agent-5", "agent-2"):
        (tmp_path / agent).mkdir()
        (tmp_path / agent / "TASKS.md").write_text(board, encoding="utf-8")
    monkeypatch.setenv("DP_TEAM_ROOT", str(tmp_path))
    assert video.holds("emulator-5556", "agent-5")
    assert not video.holds("emulator-5556", "agent-2")
    assert not video.holds("emulator-5560", "agent-5")


def test_the_serial_reaches_the_recording_1236(monkeypatch):
    seen = {}
    monkeypatch.setattr(video, "holds", lambda serial, agent: True)
    monkeypatch.setattr(video, "record", lambda script, serial=None, take=None: seen.setdefault("serial", serial))
    assert video.main(["own-letter", "--record", "--serial", "emulator-5556"]) == 0
    assert seen["serial"] == "emulator-5556"


def test_a_lock_check_never_clones_the_live_board_1389(tmp_path, monkeypatch):
    monkeypatch.setenv("DP_TEAM_ROOT", str(tmp_path))
    assert not video.holds("emulator-5556", "agent-3")
    assert not (tmp_path / "agent-3").exists()
