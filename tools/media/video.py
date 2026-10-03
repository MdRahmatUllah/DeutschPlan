"""Short app videos from an emulator recording, framed and captioned in each
language, by one command (#1206).

    python tools/media/video.py study-day                       # record, then render
    python tools/media/video.py study-day --record              # the recording alone
    python tools/media/video.py study-day --render --locales en,bn --formats vertical

A script is `tools/media/videos/<name>.yaml`: the `tools/device.py` steps the
recording runs, the seconds of it kept (`cut`: start it after screenrecord's
first ~1.5 s, its warm-up, which may be black or frozen), and timed captions in each of
its `locales`. A caption's numbers come from `site-facts.json` as `{tokens}`
(`{totals.words}`), each language's way (posts.py's `fill`): a digit typed in a
caption stops the run, as the marketing rules ask.

**Recording** needs the emulator held (`python tools/team.py device`): it runs
`screenrecord` on emulator-5558 while device.py walks the steps, and keeps
the recording in `build/media/` (git-ignored: a raw recording is too big for
the media branch).

**Rendering** draws each caption's frame (`videos/frame.html`, every
value from brand.json through brand.py) with Playwright, and ffmpeg puts the
recording into the frame's screen and switches the frames on the captions'
times: H.264 and a silent AAC track, MP4, 30 fps. The files go to the media
worktree, `<yyyy-mm-dd>-1206-videos/<script>-<locale>-<format>.mp4`, or
`--out`; one over 20 MB is said to belong on the owner's drive (media README).
"""

from __future__ import annotations

import argparse
import base64
import datetime
import json
import math
import re
import shutil
import string
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import yaml

from brand import BRAND, ROOT, colour, safe_box, size
from posts import TOKEN, fill

sys.path.insert(0, str(ROOT / "tools"))
import device  # noqa: E402

SCRIPTS = Path(__file__).parent / "videos"
#: Not a stills template (templates/): a video's frame, its screen left
#: for the recording.
TEMPLATE = SCRIPTS / "frame.html"
RAW = ROOT / "build" / "media"
FORMATS = ("vertical", "landscape")
FPS = 30
MAX_MB = 20

#: A CEFR level or step, A1 to C2.2.
CEFR = re.compile(r"\b[ABC][12](\.[12])?\b")

#: The caption block, in lines of caption text: a longer caption stops the run.
CAPTION_LINES = 3


class ScriptError(ValueError):
    pass


def load(name: str, scripts: Path = SCRIPTS) -> dict:
    script = yaml.safe_load((scripts / f"{name}.yaml").read_text(encoding="utf-8"))
    script["name"] = name
    check(script)
    return script


def check(script: dict) -> None:
    """What stops a script: no steps, a cut that isn't one, a caption out of
    the cut, overlapping or missing a locale, and a digit typed in one."""
    name = script.get("name", "?")
    steps, cut, locales = script.get("steps"), script.get("cut"), script.get("locales")
    if not steps or not all(isinstance(s, str) for s in steps):
        raise ScriptError(f"{name}: steps must be device.py steps")
    for part in ("before", "after"):
        if not all(isinstance(c, str) for c in script.get(part) or []):
            raise ScriptError(f"{name}: {part} must be adb shell commands")
    if not (isinstance(cut, list) and len(cut) == 2 and 0 <= cut[0] < cut[1]):
        raise ScriptError(f"{name}: cut must be [from, to] seconds, from < to")
    if not locales:
        raise ScriptError(f"{name}: no locales")
    length = cut[1] - cut[0]
    end = 0.0
    for i, caption in enumerate(script.get("captions") or []):
        start, stop = caption.get("from"), caption.get("to")
        if not (isinstance(start, (int, float)) and isinstance(stop, (int, float))
                and end <= start < stop <= length):
            raise ScriptError(f"{name}: caption {i + 1}: from {start} to {stop} must follow the one "
                              f"before and stay in the cut's {length:g} s")
        end = stop
        text = caption.get("text") or {}
        missing = [lang for lang in locales if not text.get(lang)]
        if missing:
            raise ScriptError(f"{name}: caption {i + 1} has no {', '.join(missing)}")
        for lang, line in text.items():
            # A level's code (A1, B2.1) is a name, not a number.
            if re.search(r"\d", CEFR.sub("", TOKEN.sub("", line))):
                raise ScriptError(f"{name}: caption {i + 1} ({lang}) types a number: "
                                  "take it from site-facts.json as a {token}")


def captions(script: dict, lang: str) -> list[tuple[float, float, str]]:
    """Each caption's times and its text in [lang], the facts filled in."""
    return [(c["from"], c["to"], fill(c["text"][lang], lang)) for c in script.get("captions") or []]


# ---------------------------------------------------------------------------
# Recording


def walk(script: dict, shell: list[str], serial: str) -> None:
    """The steps in order: device.py's, and a `shell:` step as an adb shell
    command between them (`shell:am start -n …`: Sogda brought back warm,
    #1245)."""
    batch: list[str] = []

    def flush() -> None:
        if batch and device.main(["--serial", serial, *batch]):
            raise SystemExit(f"{script['name']}: a step failed: no recording kept")
        batch.clear()

    for step in script["steps"]:
        if step.startswith("shell:"):
            flush()
            subprocess.run([*shell, step.removeprefix("shell:")], check=True)
        else:
            batch.append(step)
    flush()


def record(script: dict, serial: str = device.DEV_SERIAL) -> Path:
    """`screenrecord` while device.py walks the steps; the file in build/media/.
    The script's `before` adb shell commands run first (flight mode on, #1245)
    and its `after` ones last, however the recording ends, so the shared
    emulator is left as it was."""
    adb = device.adb_path()
    remote = f"/sdcard/sogda-{script['name']}.mp4"
    limit = math.ceil(script["cut"][1]) + 30
    shell = [adb, "-s", serial, "shell"]
    try:
        for command in script.get("before") or []:
            subprocess.run([*shell, command], check=True)
        recorder = subprocess.Popen(
            [*shell, "screenrecord", "--bit-rate", "8000000",
             "--time-limit", str(min(limit, 180)), remote])
        time.sleep(1.5)  # screenrecord's first frame
        try:
            walk(script, shell, serial)
        finally:
            subprocess.run([*shell, "pkill", "-INT", "screenrecord"], check=False)
            recorder.wait(timeout=30)
    finally:
        for command in script.get("after") or []:
            subprocess.run([*shell, command], check=False)
    time.sleep(1)  # the file closes on the device
    RAW.mkdir(parents=True, exist_ok=True)
    local = RAW / f"{script['name']}.mp4"
    subprocess.run([adb, "-s", serial, "pull", remote, str(local)], check=True, capture_output=True)
    subprocess.run([adb, "-s", serial, "shell", "rm", remote], check=False)
    print(f"recorded {local} ({local.stat().st_size / 1e6:.1f} MB)")
    return local


# ---------------------------------------------------------------------------
# Rendering


def video_size(path: Path) -> tuple[int, int]:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height", "-of", "json", str(path)],
        check=True, capture_output=True, text=True).stdout
    stream = json.loads(out)["streams"][0]
    return stream["width"], stream["height"]


def layout(fmt: str, lang: str) -> dict:
    """The frame's values for videos/frame.html."""
    width, height = size(fmt)
    left, top, right, bottom = safe_box(fmt)
    type_ = BRAND["type"]
    caption = type_["sizes"][fmt]["body"]
    line_height = type_["line_height"]["bengali" if lang == "bn" else "latin"]
    if fmt == "vertical":
        # The screen may run into the bottom band the app's overlay covers;
        # the caption stays in the safe area, above it.
        frame = dict(direction="column", frame_height=round(height * 0.96) - top,
                     caption_extent=math.ceil(CAPTION_LINES * caption * line_height))
    else:
        frame = dict(direction="row", frame_height=bottom - top,
                     caption_extent=round((right - left) * 0.45))
    return dict(
        width=width, height=height, left=left, top=top, frame_width=right - left,
        gap=round(caption * 0.6), caption=caption,
        caption_weight=type_["weights"]["title"], line_height=line_height,
        tracking=type_["tracking"]["title"], ground=colour("paper"), ink=colour("ink"),
        border=BRAND["frame"]["border"], radius=BRAND["frame"]["radius"],
        shadow=BRAND["frame"]["shadow"], **frame)


def frame_html(fmt: str, lang: str, text: str, fonts: dict[str, str]) -> str:
    values = {**layout(fmt, lang), **fonts, "lang": lang,
              "caption_text": text.replace("&", "&amp;").replace("<", "&lt;")}
    # A value isn't read for $ again: a caption's «$» needs no escape.
    return string.Template(TEMPLATE.read_text(encoding="utf-8")).substitute(values)


#: Sizes the screen to the recording, inside the hole with its border and
#: shadow, and answers the recording's place: x, y, w, h, in pixels.
FIT = """([w, h]) => {
  const hole = document.querySelector('.hole').getBoundingClientRect();
  const screen = document.querySelector('.screen');
  const s = getComputedStyle(screen);
  const border = parseFloat(s.borderTopWidth);
  const shadow = parseFloat(s.boxShadow.split('px')[1]) || 0;
  const scale = Math.min((hole.width - 2 * border - shadow) / w,
                         (hole.height - 2 * border - shadow) / h);
  const iw = 2 * Math.floor(w * scale / 2), ih = 2 * Math.floor(h * scale / 2);
  screen.style.width = (iw + 2 * border) + 'px';
  screen.style.height = (ih + 2 * border) + 'px';
  const r = screen.getBoundingClientRect();
  const p = document.querySelector('.caption p');
  return {x: Math.round(r.left + border), y: Math.round(r.top + border), w: iw, h: ih,
          overflow: p.scrollHeight > p.parentElement.clientHeight + 1};
}"""


def frames(script: dict, lang: str, fmt: str, recording: tuple[int, int],
           folder: Path) -> tuple[list[Path], dict]:
    """The frame with no caption, then one per caption; the recording's box."""
    from playwright.sync_api import sync_playwright

    fonts = {key: base64.b64encode((ROOT / BRAND["type"]["fonts"][family]).read_bytes()).decode()
             for key, family in (("inter", "Inter"), ("bengali", "Noto Sans Bengali"))}
    texts = ["", *[text for _, _, text in captions(script, lang)]]
    width, height = size(fmt)
    paths: list[Path] = []
    box: dict | None = None
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=1)
        for i, text in enumerate(texts):
            page.set_content(frame_html(fmt, lang, text, fonts))
            page.evaluate("document.fonts.ready")
            here = page.evaluate(FIT, list(recording))
            if here.pop("overflow"):
                raise ScriptError(f"{script['name']}: caption {i} ({lang}, {fmt}) is longer than "
                                  f"{CAPTION_LINES} lines")
            box = box or here
            path = folder / f"{lang}-{fmt}-{i}.png"
            page.screenshot(path=str(path))
            paths.append(path)
        browser.close()
    return paths, box


def ffmpeg_args(raw: Path, frames_: list[Path], box: dict, times: list[tuple[float, float]],
                cut: list[float], out: Path) -> list[str]:
    """The frames in turn (the captionless one under the others), the
    recording scaled into its box on top, a silent track under it all."""
    args = ["ffmpeg", "-y", "-v", "error", "-ss", f"{cut[0]}", "-to", f"{cut[1]}", "-i", str(raw)]
    for path in frames_:
        args += ["-loop", "1", "-framerate", str(FPS), "-i", str(path)]
    silence = len(frames_) + 1
    args += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
    # screenrecord writes a frame only when the screen changes: the last one
    # before the cut would last past it, so the cut's length is trimmed too.
    graph = [f"[0:v]fps={FPS},trim=duration={cut[1] - cut[0]},setpts=PTS-STARTPTS,"
             f"scale={box['w']}:{box['h']},setsar=1[rec]"]
    base = "[1:v]"
    for i, (start, stop) in enumerate(times, start=2):
        graph.append(f"{base}[{i}:v]overlay=enable='between(t,{start},{stop})'[f{i}]")
        base = f"[f{i}]"
    graph.append(f"{base}[rec]overlay={box['x']}:{box['y']}:shortest=1,format=yuv420p[out]")
    return args + [
        "-filter_complex", ";".join(graph), "-map", "[out]", "-map", f"{silence}:a",
        "-shortest", "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-r", str(FPS),
        "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", str(out)]


def render(script: dict, locales: list[str], formats: list[str], out: Path) -> list[Path]:
    raw = RAW / f"{script['name']}.mp4"
    if not raw.exists():
        raise SystemExit(f"{raw} isn't there: record it first (--record, under the device lock)")
    recording = video_size(raw)
    out.mkdir(parents=True, exist_ok=True)
    made: list[Path] = []
    with tempfile.TemporaryDirectory() as tmp:
        for lang in locales:
            for fmt in formats:
                frames_, box = frames(script, lang, fmt, recording, Path(tmp))
                target = out / f"{script['name']}-{lang}-{fmt}.mp4"
                times = [(start, stop) for start, stop, _ in captions(script, lang)]
                subprocess.run(ffmpeg_args(raw, frames_, box, times, script["cut"], target), check=True)
                mb = target.stat().st_size / 1e6
                print(f"{target.parent.name}/{target.name} ({mb:.1f} MB)"
                      + (f": over {MAX_MB} MB, for the owner's drive, not the media branch" if mb > MAX_MB else ""))
                made.append(target)
    return made


def media_root() -> Path:
    """The `media` branch's worktree, wherever this checkout's is."""
    listing = subprocess.run(["git", "-C", str(ROOT), "worktree", "list", "--porcelain"],
                             capture_output=True, text=True).stdout
    for block in listing.split("\n\n"):
        if "branch refs/heads/media" in block:
            return Path(block.splitlines()[0].removeprefix("worktree "))
    return ROOT.parent / "dp-media"


def holds(serial: str, agent: str) -> bool:
    """Whether [agent] may record on [serial]: emulator-5558 under `team.py device`,
    any other under the board's lock named after it (`team.py lock emulator-5556`,
    the media lane's, #1236)."""
    if serial == device.DEV_SERIAL:
        from smoke import holds_device
        return holds_device(agent)
    import team
    board = team.Board((team.board_checkout(agent) / "TASKS.md").read_text(encoding="utf-8"))
    return any(lock.resource == serial and lock.owner == agent for lock in board.locks)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("script", help="a name in tools/media/videos/")
    parser.add_argument("--record", action="store_true", help="the recording alone")
    parser.add_argument("--render", action="store_true", help="the videos alone, from the last recording")
    parser.add_argument("--locales", help="default: the script's")
    parser.add_argument("--formats", default=",".join(FORMATS))
    parser.add_argument("--out", type=Path, help="default: the media worktree's dated folder")
    parser.add_argument("--serial", default=device.DEV_SERIAL,
                        help="the emulator to record on: emulator-5558 under `team.py device` (the default), "
                             "or another under `team.py lock <serial>`")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    script = load(args.script)
    both = not args.record and not args.render
    if args.record or both:
        if not device.owner_checkout() and not holds(args.serial, device.agent()):
            how = "team.py device" if args.serial == device.DEV_SERIAL else f"team.py lock {args.serial} -m why"
            print(f"refused: hold {args.serial} first: `python tools/{how}`", file=sys.stderr)
            return 2
        record(script, args.serial)
    if args.render or both:
        if not shutil.which("ffmpeg"):
            raise SystemExit("ffmpeg isn't on the PATH")
        out = args.out or media_root() / f"{datetime.date.today():%Y-%m-%d}-1206-videos"
        locales = args.locales.split(",") if args.locales else script["locales"]
        render(script, locales, args.formats.split(","), out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
