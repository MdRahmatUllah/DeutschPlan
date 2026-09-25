"""Render every artboard of deutsch-plan-design-html/ to docs/design/<canvas>/<Screen>.png
and rewrite the screen tables in README.md between the <!-- screens:start --> / <!-- screens:end --> markers.

Run:
    pip install playwright
    playwright install chromium
    python tools/render_design.py
"""
import html
import pathlib
import re

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESIGN = ROOT / "deutsch-plan-design-html"
OUT = ROOT / "docs" / "design"
README = ROOT / "README.md"
CANVASES = {
    "ios-light": "iOS · Light",
    "ios-dark": "iOS · Dark",
    "android-light": "Android · Light",
    "android-dark": "Android · Dark",
}
PHONE_W = 160


def base(name: str) -> str:
    """Today-android-dark.html -> Today"""
    return re.sub(r"(-ios|-android)?(-dark)?\.html$", "", name)


def manifest(canvas: str):
    """[(section title, [(caption, screen file)])] in canvas order."""
    s = (DESIGN / canvas / "index.html").read_text(encoding="utf-8")
    out = []
    for sec in re.split(r"(?=<section )", s)[1:]:
        title = html.unescape(re.search(r"<h2[^>]*>(.*?)</h2>", sec).group(1))
        shots = re.findall(r'<figcaption[^>]*>(.*?)</figcaption><a href="screens/([^"]+)"', sec)
        out.append((title, [(html.unescape(c), f) for c, f in shots]))
    return out


def render(pw, canvas, files):
    browser = pw.chromium.launch()
    page = browser.new_page(viewport={"width": 1400, "height": 1100}, device_scale_factor=1)
    (OUT / canvas).mkdir(parents=True, exist_ok=True)
    for f in files:
        page.goto((DESIGN / canvas / "screens" / f).as_uri(), wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        page.locator('div[style*="position:relative;overflow:hidden"]').first.screenshot(
            path=OUT / canvas / f"{base(f)}.png"
        )
    browser.close()
    print(f"{canvas}: {len(files)} artboards")


def cell(canvas, f, caption):
    return (
        f'<a href="deutsch-plan-design-html/{canvas}/screens/{f}">'
        f'<img src="docs/design/{canvas}/{base(f)}.png" width="{PHONE_W}" alt="{caption} — {CANVASES[canvas]}"></a>'
    )


def tables(sections, per_canvas):
    head = "| Screen | " + " | ".join(CANVASES.values()) + " |\n|---|---|---|---|---|\n"
    md = []
    for title, shots in sections:
        if title.startswith("Foundations"):
            continue  # the token sheets are shown in the design-system section
        rows = []
        for i, (caption, _) in enumerate(shots):
            cells = [cell(c, per_canvas[c][title][i], caption) for c in CANVASES]
            rows.append(f"| **{caption}** | " + " | ".join(cells) + " |")
        md.append(f"### {title}\n\n{head}" + "\n".join(rows) + "\n")
    return "\n".join(md)


def main():
    sections = manifest("ios-light")
    per_canvas = {}
    for canvas in CANVASES:
        m = manifest(canvas)
        assert [[base(f) for _, f in s] for _, s in m] == [[base(f) for _, f in s] for _, s in sections], canvas
        per_canvas[canvas] = {title: [f for _, f in shots] for title, shots in m}
    with sync_playwright() as pw:
        for canvas in CANVASES:
            render(pw, canvas, [f for shots in per_canvas[canvas].values() for f in shots])
    text = README.read_text(encoding="utf-8")
    start, end = "<!-- screens:start -->", "<!-- screens:end -->"
    a, b = text.index(start) + len(start), text.index(end)
    README.write_text(text[:a] + "\n" + tables(sections, per_canvas) + text[b:], encoding="utf-8", newline="\n")
    print("README.md screen tables updated")


if __name__ == "__main__":
    main()
