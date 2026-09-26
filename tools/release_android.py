"""#170: the Android release bundle, and the checks Play makes of it.

    python tools/team.py device               # an app build holds the lock
    python tools/release_android.py           # build, then check
    python tools/release_android.py --check   # check the last build only
    python tools/team.py device --release

The bundle is `flutter build appbundle --release --obfuscate
--split-debug-info=build/symbols` (`docs/05-dev-guide/release.md`), at
`app/build/app/outputs/bundle/release/app-release.aab`. Then:

    16 KB   every 64-bit native library in it has its loadable segments
            aligned to 16 KB, as Play requires of apps targeting Android 15+
            (32-bit ones are exempt: no 16 KB device runs them)
    key     which key signed it: the owner's upload key, from
            `app/android/key.properties`, or the debug key, which Play refuses
    symbols Dart's, in `app/build/symbols`, kept with the release (see
            release.md); the plugins' native ones ride in the bundle

Exit 1 when a library isn't aligned. A debug-signed bundle is reported, not
failed: it is what every build before the owner's keystore is.
"""

from __future__ import annotations

import argparse
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import device  # noqa: E402
from smoke import holds_device  # noqa: E402

APP = TOOLS.parent / "app"
BUNDLE = APP / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
SYMBOLS = APP / "build" / "symbols"
KEY_PROPERTIES = APP / "android" / "key.properties"
PAGE = 16 * 1024
PT_LOAD = 1


def load_alignments(elf: bytes) -> list[int]:
    """The `p_align` of each loadable segment of an ELF file."""
    if elf[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    wide = elf[4] == 2  # ELFCLASS64
    order = "<" if elf[5] == 1 else ">"  # ELFDATA2LSB
    if wide:
        phoff, = struct.unpack_from(order + "Q", elf, 0x20)
        phentsize, phnum = struct.unpack_from(order + "HH", elf, 0x36)
    else:
        phoff, = struct.unpack_from(order + "I", elf, 0x1C)
        phentsize, phnum = struct.unpack_from(order + "HH", elf, 0x2A)
    alignments = []
    for i in range(phnum):
        at = phoff + i * phentsize
        p_type, = struct.unpack_from(order + "I", elf, at)
        if p_type != PT_LOAD:
            continue
        # p_align is the header's last field: 8 bytes at 0x30 (64-bit), 4 at
        # 0x1C (32-bit).
        p_align, = struct.unpack_from(order + ("Q" if wide else "I"), elf, at + (0x30 if wide else 0x1C))
        alignments.append(p_align)
    return alignments


def misaligned(bundle: Path) -> list[str]:
    """The 64-bit libraries in [bundle] with a loadable segment under 16 KB."""
    found = []
    with zipfile.ZipFile(bundle) as aab:
        for name in aab.namelist():
            if not name.endswith(".so") or "/lib/" not in f"/{name}":
                continue
            abi = name.split("/")[-2]
            if abi not in ("arm64-v8a", "x86_64"):
                continue
            under = [a for a in load_alignments(aab.read(name)) if a < PAGE]
            if under:
                found.append(f"{name}: segments aligned to {min(under)} bytes")
    return found


def signed_by() -> str:
    return ("the upload key (app/android/key.properties)" if KEY_PROPERTIES.exists()
            else "the DEBUG key: Play refuses it; add app/android/key.properties (release.md)")


def build() -> None:
    flutter = shutil.which("flutter") or "flutter"
    command = [flutter, "build", "appbundle", "--release", "--obfuscate",
               f"--split-debug-info={SYMBOLS.relative_to(APP).as_posix()}"]
    if subprocess.run(command, cwd=APP).returncode:
        raise SystemExit(f"failed: {' '.join(command)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="check the last build, don't build")
    args = parser.parse_args(argv)
    if not args.check:
        # An app build takes the lock (CLAUDE.md), as perf.py's does.
        if not holds_device(device.agent()):
            print("refused: hold the emulator first: `python tools/team.py device`", file=sys.stderr)
            return 2
        build()
    if not BUNDLE.exists():
        print(f"no bundle at {BUNDLE}: build it first", file=sys.stderr)
        return 2

    bad = misaligned(BUNDLE)
    print(f"bundle:  {BUNDLE} ({BUNDLE.stat().st_size / 1e6:.1f} MB)")
    print(f"16 KB:   {'ok' if not bad else 'FAIL'}")
    for line in bad:
        print(f"         {line}")
    print(f"key:     {signed_by()}")
    print(f"symbols: {SYMBOLS} (keep with the release)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
