"""The Licences screen's texts (M8, #172): a release step, not a hand edit.

    python tools/licences.py check    # fails if anything below is off
    python tools/licences.py update   # fetches the bundled texts again

`check` fails when:
- a bundled model or font licence differs from what its maker publishes
  (line endings aside), is missing, or isn't listed here;
- a package the app resolves ships no LICENSE file. Flutter's LicenseRegistry,
  which M8 lists, is built from those files, so such a package would be left
  out of M8 without a word. Flutter's own packages are covered by the SDK's
  licence, and the app is ours.

Run `flutter pub get` in app/ first: the packages are read from
app/.dart_tool/package_config.json.
"""

from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
LICENCES = ROOT / "app" / "assets" / "licences"
PACKAGE_CONFIG = ROOT / "app" / ".dart_tool" / "package_config.json"

# Each bundled text, and where its maker publishes it.
SOURCES = {
    "Supertonic3-OpenRAIL-M.txt":
        "https://huggingface.co/Supertone/supertonic-3/resolve/main/LICENSE",
    # supertonic_text.dart ports the SDK's core.py (supertonic 1.3.1).
    "Supertonic-SDK-MIT.txt":
        "https://raw.githubusercontent.com/supertone-oss-archive/supertonic-py/main/LICENSE",
    "HY-MT1.5-Tencent-HY.txt":
        "https://huggingface.co/tencent/HY-MT1.5-1.8B/resolve/main/License.txt",
    "Inter-OFL.txt":
        "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/OFL.txt",
    "NotoSansBengali-OFL.txt":
        "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansbengali/OFL.txt",
}

LICENCE_FILES = ("LICENSE", "LICENCE", "COPYING")


def normalise(text: str) -> str:
    """[text] as compared: LF line ends, as git's autocrlf may change them,
    and no trailing blank lines."""
    return text.replace("\r\n", "\n").strip() + "\n"


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "deutschplan-licences"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def stale(folder: Path = LICENCES, get: Callable[[str], str] = fetch) -> list[str]:
    """What is off in [folder]: a text that isn't its source's, or missing,
    or a file no source is listed for."""
    problems = []
    for name, url in SOURCES.items():
        path = folder / name
        if not path.exists():
            problems.append(f"{name}: missing (update fetches it from {url})")
        elif normalise(path.read_text(encoding="utf-8")) != normalise(get(url)):
            problems.append(f"{name}: differs from {url}")
    for path in sorted(folder.glob("*.txt")):
        if path.name not in SOURCES:
            problems.append(f"{path.name}: no source in tools/licences.py")
    return problems


def _path(uri: str, base: Path) -> Path:
    if uri.startswith("file:"):
        return Path(urllib.request.url2pathname(urllib.parse.urlparse(uri).path)).resolve()
    return (base / uri).resolve()


def unlicensed(config: Path = PACKAGE_CONFIG) -> list[str]:
    """The packages in [config] that ship no licence file, but Flutter's
    own and the app itself."""
    data = json.loads(config.read_text(encoding="utf-8"))
    base = config.parent
    flutter = _path(data["flutterRoot"], base) if "flutterRoot" in data else None
    app = config.parent.parent.resolve()
    missing = []
    for package in data["packages"]:
        root = _path(package["rootUri"], base)
        if root == app or (flutter and flutter in root.parents):
            continue
        files = [f.name.upper() for f in root.iterdir() if f.is_file()] if root.is_dir() else []
        if not any(name.startswith(LICENCE_FILES) for name in files):
            missing.append(f"{package['name']}: no LICENSE in {root}")
    return missing


def update(folder: Path = LICENCES, get: Callable[[str], str] = fetch) -> None:
    """Writes each text as its maker publishes it, byte for byte."""
    for name, url in SOURCES.items():
        (folder / name).write_text(get(url), encoding="utf-8", newline="")
        print(f"{name} <- {url}")


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "check"
    if command == "update":
        update()
        return 0
    if command != "check":
        print(__doc__)
        return 2
    if not PACKAGE_CONFIG.exists():
        print("run `flutter pub get` in app/ first")
        return 1
    problems = stale() + unlicensed()
    for problem in problems:
        print(problem)
    print("licences: all current" if not problems else f"licences: {len(problems)} to fix")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
