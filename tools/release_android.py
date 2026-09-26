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
    key     the certificate that signed it (`keytool -printcert -jarfile`):
            the owner's upload key, from `app/android/key.properties`, or the
            debug key, which Play refuses
    symbols Dart's, in `app/build/symbols`, kept with the release (see
            release.md); the plugins' native ones ride in the bundle

Exit 1 when a library isn't aligned. A debug-signed bundle is reported, not
failed: it is what every build before the owner's keystore is.
"""

from __future__ import annotations

import argparse
import os
import re
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
ANDROID_STUDIO_KEYTOOL = Path("C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe")
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


def keytool() -> str | None:
    """The JDK's keytool: on PATH, under JAVA_HOME, or Android Studio's."""
    java_home = os.environ.get("JAVA_HOME")
    for candidate in (
        shutil.which("keytool"),
        java_home and str(Path(java_home) / "bin" / "keytool"),
        str(ANDROID_STUDIO_KEYTOOL) if ANDROID_STUDIO_KEYTOOL.exists() else None,
    ):
        if candidate and (Path(candidate).exists() or shutil.which(candidate)):
            return candidate
    return None


def signer(bundle: Path) -> str | None:
    """The owner of the certificate that signed [bundle], as keytool prints
    it ("CN=Android Debug, O=Android, C=US"); None without keytool, or when
    the bundle isn't signed."""
    tool = keytool()
    if tool is None:
        return None
    out = subprocess.run([tool, "-printcert", "-jarfile", str(bundle)],
                         capture_output=True, text=True).stdout
    found = re.search(r"^Owner: (.+)$", out, re.MULTILINE)
    return found.group(1).strip() if found else None


def signed_by(owner: str | None) -> str:
    """What [signer] found, said for the release checklist."""
    if owner is None:
        return "UNKNOWN: no keytool, or the bundle isn't signed"
    if "CN=Android Debug" in owner:
        return "the DEBUG key: Play refuses it; add app/android/key.properties (release.md)"
    return f"{owner}"


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
        # An agent's app build takes the lock (CLAUDE.md), as perf.py's does.
        # The owner's own checkout has no agent, and builds when it likes.
        who = device.agent()
        if who and not holds_device(who):
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
    print(f"key:     {signed_by(signer(BUNDLE))}")
    print(f"symbols: {SYMBOLS} (keep with the release)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
