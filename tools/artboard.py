"""Put an artboard beside a golden, to compare them by eye.

    python tools/artboard.py out.png ARTBOARD [ARTBOARD|GOLDEN ...] [--height 844]

Each input is an artboard `.html` (rendered to PNG with headless Edge or
Chrome), or any `.png` — a golden, or a Paper & Ink artboard already rendered
under `docs/design/`. They are scaled to one height and tiled left to right
into `out.png`; open it and look. For example, L6 in light and glass:

    python tools/artboard.py $TEMP/l6.png \\
      docs/design/android-light/CategoryWords.png \\
      app/test/golden/goldens/category_words_light_phone.png \\
      deutsch-plan-v2-aurora-glass-html/android-light/screens/CategoryWords-android.html \\
      app/test/golden/goldens/category_words_glass_phone.png

The Aurora Glass set has no rendered PNGs, which is what the `.html` path is
for. Artboards load Inter from Google Fonts, so render them online. Needs
Pillow (`pip install pillow`); it is not in `tools/requirements.txt` because
CI never runs this.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BROWSERS = (
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
)


def browser() -> str:
    for candidate in (*BROWSERS, shutil.which("msedge"), shutil.which("google-chrome"), shutil.which("chromium")):
        if candidate and Path(candidate).exists():
            return candidate
    raise SystemExit("no Edge or Chrome found to render the artboard")


def render(html: Path, out: Path) -> Path:
    # The artboards draw a 390x844 phone inside a slightly larger stage.
    subprocess.run(
        [browser(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
         f"--screenshot={out}", "--window-size=440,900", html.resolve().as_uri()],
        capture_output=True, timeout=120, check=False,
    )
    if not out.exists():
        raise SystemExit(f"could not render {html}")
    return out


def tile(images: list, height: int):
    from PIL import Image

    scaled = [im.convert("RGB").resize((max(1, im.width * height // im.height), height)) for im in images]
    sheet = Image.new("RGB", (sum(im.width for im in scaled), height), "white")
    x = 0
    for im in scaled:
        sheet.paste(im, (x, 0))
        x += im.width
    return sheet


def main(argv: list[str]) -> int:
    from PIL import Image

    height = 844
    if "--height" in argv:
        i = argv.index("--height")
        height = int(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 2:
        print(__doc__)
        return 2
    out, inputs = Path(argv[0]), [Path(p) for p in argv[1:]]
    with tempfile.TemporaryDirectory() as tmp:
        images = []
        for k, path in enumerate(inputs):
            png = render(path, Path(tmp) / f"{k}.png") if path.suffix == ".html" else path
            images.append(Image.open(png))
        tile(images, height).save(out)
    print(f"{out} — {len(inputs)} images at {height} px high")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
