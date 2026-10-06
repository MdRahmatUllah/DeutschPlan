"""The motion promo (#1422): stock footage, the app on stock green-screen
phones, and motion graphics, rendered per listing language.

    python tools/media/motion.py                    # every locale
    python tools/media/motion.py --locales en,bn    # some

`motion/promo.yaml` holds the cut, the stock (Pexels ids, fetched into
build/media/stock/, never committed: the licence forbids redistributing the
clips unaltered) and each scene's copy. The app on the green-screen phones
is each language's own take, `build/media/promo-<lang>.mp4`, which
`video.py promo --record --takes <lang>` makes on emulator-5556.

The base cut: each shot's stock clip at 30 fps, cropped to 1920 x 1080 with a
slow push-in, or with the app keyed onto its green screen (OpenCV: the
screen's quadrilateral each frame, the app warped into it, a finger kept on
top since it isn't green). Then `motion/motion.html`, whose `render(t)`
places every sticker, phone and wipe for time t, is screenshot frame by frame
(Playwright, transparent) and laid over the base cut by ffmpeg.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import html
import re
import shutil
import string
import subprocess
import sys
import urllib.request
from pathlib import Path

import cv2
import numpy as np
import yaml

sys.path.insert(0, str(Path(__file__).parent))
from brand import BRAND, ROOT, colour  # noqa: E402
from posts import fill  # noqa: E402

HERE = Path(__file__).parent
SPEC = HERE / "motion" / "promo.yaml"
TEMPLATE = HERE / "motion" / "motion.html"
BUILD = ROOT / "build" / "media"
STORE = ROOT / "docs" / "05-dev-guide" / "store"
W, H, FPS = 1920, 1080, 30
UA = {"User-Agent": "Mozilla/5.0"}
# own-letter's team-written note (#1236), its words marked as D2 marks them.
LETTER = [("Sehr", "A1"), (" geehrte ", None), ("Damen", "A1"), (" und ", None), ("Herren", "A1"), (",<br><br>hier ist die ", None),
          ("Nebenkostenabrechnung", "B1"), (" für 2025. ", None), ("Bitte", "A1"), (" ", None), ("überweisen", "A1"),
          (" Sie die ", None), ("Nachzahlung", "B1"), (" bis zum 15. ", None), ("November", "A1"), (" auf unser ", None),
          ("Konto", "A1"), (".", None)]


def load(path: Path = SPEC) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def stock_clip(clip_id: int) -> Path:
    """[clip_id]'s file in build/media/stock/, fetched from Pexels once (the HD
    rendition when there is one)."""
    out = BUILD / "stock" / f"{clip_id}.mp4"
    if out.exists():
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(f"https://www.pexels.com/download/video/{clip_id}/", headers=UA, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as r:
        url = r.url
    for cand in (re.sub(r"uhd_(\d+)_(\d+)", lambda m: "hd_1920_1080" if int(m[1]) > int(m[2]) else "hd_1080_1920", url), url):
        try:
            with urllib.request.urlopen(urllib.request.Request(cand, headers=UA), timeout=300) as r:
                out.write_bytes(r.read())
            return out
        except OSError:
            continue
    raise SystemExit(f"stock {clip_id}: no download")


def frames(path: Path, start: float, seconds: float, vf: str, size: tuple[int, int]):
    """[path]'s frames from [start] for [seconds], at 30 fps through [vf], as
    BGR arrays of [size]. fps comes first: a recording writes a frame only when
    the screen changes, and a seek would drop one resting from the start."""
    w, h = size
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-vf",
           f"fps={FPS},trim=start={start}:duration={seconds},setpts=PTS-STARTPTS,{vf}",
           "-f", "rawvideo", "-pix_fmt", "bgr24", "-"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = round(seconds * FPS)
    last = None
    for _ in range(n):
        buf = proc.stdout.read(w * h * 3)
        if len(buf) < w * h * 3:
            break
        last = np.frombuffer(buf, np.uint8).reshape(h, w, 3)
        yield last
        n -= 1
    proc.stdout.close()
    proc.wait()
    for _ in range(n):  # a clip shorter than the shot holds its last frame
        yield last


def replace_screen(frame: np.ndarray, app: np.ndarray) -> np.ndarray:
    """[frame] with [app] warped onto its green screen; a finger, not green, stays on top."""
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    mask = cv2.morphologyEx(cv2.inRange(hsv, (40, 150, 110), (80, 255, 255)), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    def solid(c):  # a screen is solid; leaves and grass are ragged
        hull = cv2.contourArea(cv2.convexHull(c)) or 1
        return cv2.contourArea(c) if cv2.contourArea(c) / hull > 0.75 else 0

    if not cnts or solid(max(cnts, key=solid)) < 0.005 * frame.shape[0] * frame.shape[1]:
        return frame
    hull = cv2.convexHull(max(cnts, key=solid))
    quad = cv2.approxPolyDP(hull, 0.02 * cv2.arcLength(hull, True), True)
    if len(quad) != 4:
        quad = cv2.boxPoints(cv2.minAreaRect(hull))
    pts = np.float32(quad).reshape(4, 2)
    s, d = pts.sum(1), np.diff(pts, axis=1).ravel()
    dst = np.float32([pts[s.argmin()], pts[d.argmin()], pts[s.argmax()], pts[d.argmax()]])
    dst = dst.mean(0) + (dst - dst.mean(0)) * 1.04  # up to the bezel's rounded corners
    h_app, w_app = app.shape[:2]
    m = cv2.getPerspectiveTransform(np.float32([[0, 0], [w_app, 0], [w_app, h_app], [0, h_app]]), dst)
    warped = cv2.warpPerspective(app, m, (frame.shape[1], frame.shape[0]))
    screen = np.zeros(mask.shape, np.uint8)
    cv2.fillConvexPoly(screen, dst.astype(np.int32), 255)
    key = cv2.GaussianBlur(cv2.bitwise_and(mask, screen), (5, 5), 0).astype(np.float32)[..., None] / 255
    out = (warped * key + frame * (1 - key)).astype(np.uint8)
    b, g, r = cv2.split(out)
    spill = ((g.astype(np.int16) - np.maximum(r, b)) > 40) & (cv2.dilate(screen, np.ones((25, 25), np.uint8)) > 0)
    g[spill] = np.maximum(r, b)[spill]
    return cv2.merge([b, g, r])


def base_cut(spec: dict, lang: str, out: Path) -> Path:
    """The footage under the graphics: every shot in turn, black where a motion scene covers it."""
    take = BUILD / f"promo-{lang}.mp4"
    if not take.exists():
        raise SystemExit(f"no {take.name}: run `python tools/media/video.py promo --record --serial emulator-5556 --takes {lang}`")
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "14", "-preset", "fast",
                            "-pix_fmt", "yuv420p", str(out)], stdin=subprocess.PIPE)
    black = np.zeros((H, W, 3), np.uint8)
    for shot in spec["shots"]:
        seconds = shot["to"] - shot["from"]
        if "stock" not in shot:
            for _ in range(round(seconds * FPS)):
                enc.stdin.write(black.tobytes())
            continue
        clip = stock_clip(spec["stock"][shot["stock"]]["id"])
        zoom, scale, x = shot.get("zoom", 0), shot.get("scale", 1), shot.get("x", 0.5)
        # cover the frame (bigger by [scale]), crop at [x] across (0 left, 1 right), then a slow push-in
        vf = (f"scale={round(W * scale)}:{round(H * scale)}:force_original_aspect_ratio=increase,"
              f"crop={W}:{H}:(iw-{W})*{x}:(ih-{H})/2")
        if zoom:
            vf += f",scale=w='trunc(iw*(1+{zoom}*t/{seconds})/2)*2':h=-2:eval=frame,crop={W}:{H}"
        footage = frames(clip, shot["at"], seconds, vf, (W, H))
        if "app_at" in shot:
            app = frames(take, shot["app_at"], seconds, "scale=1080:1920", (1080, 1920))
            for f, a in zip(footage, app):
                enc.stdin.write(replace_screen(f, a).tobytes())
        else:
            for f in footage:
                enc.stdin.write(f.tobytes())
    enc.stdin.close()
    if enc.wait():
        raise SystemExit("ffmpeg failed on the base cut")
    return out


def letter_html() -> str:
    return "".join(f'<span class="w" data-l="{lv}">{text}</span>' if lv else text for text, lv in LETTER)


def page_html(spec: dict, lang: str) -> str:
    kind = BRAND["type"]
    shots = STORE / spec["sets"][lang]
    lockup = (ROOT / BRAND["frame"]["logo"]["light"]).read_text(encoding="utf-8")
    values = {name: html.escape(fill(text[lang], lang)) for name, text in spec["copy"].items()}
    values.update({
        "lang": lang, "k": "0.84" if lang == "bn" else "1", "lh": kind["line_height"]["bengali" if lang == "bn" else "latin"],
        "inter": base64.b64encode((ROOT / kind["fonts"]["Inter"]).read_bytes()).decode(),
        "bengali": base64.b64encode((ROOT / kind["fonts"]["Noto Sans Bengali"]).read_bytes()).decode(),
        "logo": re.sub(r' width="[\d.]+" height="[\d.]+"', "", lockup, count=1),
        "letter_html": letter_html(),
        "shot_front": (shots / "02-card-front.png").as_uri(), "shot_back": (shots / "03-card-back.png").as_uri(),
        "shot_course": (shots / "04-course.png").as_uri(), "shot_step": (shots / "05-step.png").as_uri(),
        "shot_word": (shots / "06-word.png").as_uri(),
        **{name: colour(name) for name in ("lagoon", "sun", "ink", "paper", "night", "cobalt", "raspberry", "emerald")},
    })
    return string.Template(TEMPLATE.read_text(encoding="utf-8")).substitute(values)


def render(spec: dict, lang: str, out_dir: Path) -> Path:
    from playwright.sync_api import sync_playwright

    work = BUILD / "motion"
    work.mkdir(parents=True, exist_ok=True)
    base = base_cut(spec, lang, work / f"base-{lang}.mp4")
    page_file = work / f"{lang}.html"
    page_file.write_text(page_html(spec, lang), encoding="utf-8")
    seconds = spec["shots"][-1]["to"]
    out = out_dir / f"promo-motion-{lang}-landscape.mp4"
    enc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-i", str(base), "-f", "image2pipe", "-framerate", str(FPS), "-c:v", "png", "-i", "-",
         "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-filter_complex",
         "[0:v][1:v]overlay=0:0:format=auto,format=yuv420p[v]", "-map", "[v]", "-map", "2:a", "-t", str(seconds),
         "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-r", str(FPS), "-c:a", "aac", "-b:a", "64k",
         "-movflags", "+faststart", str(out)], stdin=subprocess.PIPE)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": W, "height": H})
        page.goto(page_file.as_uri())
        page.evaluate("document.fonts.ready.then(() => Promise.all([...document.images].map(i => i.decode())))")
        for n in range(round(seconds * FPS)):
            page.evaluate(f"render({n / FPS})")
            enc.stdin.write(page.screenshot(omit_background=True, type="png"))
        browser.close()
    enc.stdin.close()
    if enc.wait():
        raise SystemExit(f"ffmpeg failed on {out.name}")
    return out


def sources(spec: dict) -> str:
    rows = "\n".join(f"| {name} | {s['what']} | {s['page']} |" for name, s in spec["stock"].items())
    return (f"# The stock in #1422's promo\n\nEvery clip is from Pexels, under the Pexels License ({spec['license']}, read "
            f"2026-10-04): free to use and modify, no attribution required; not to imply that the people shown endorse "
            f"the product, and not to be redistributed unaltered. The app appears only on hands-only phones and in "
            f"Sogda's own frames.\n\n| Shot | Clip | Source |\n|---|---|---|\n{rows}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--locales", default=None)
    parser.add_argument("--out", type=Path, default=ROOT.parent / "dp-media" / f"{datetime.date.today():%Y-%m-%d}-1422-motion-promo")
    args = parser.parse_args(argv)
    spec = load()
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "SOURCES.md").write_text(sources(spec), encoding="utf-8")
    for lang in (args.locales.split(",") if args.locales else spec["locales"]):
        out = render(spec, lang, args.out)
        print(f"{out.parent.name}/{out.name} ({out.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
