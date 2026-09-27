"""#170: release_android.py's 16 KB check, over ELF files made here."""

import struct
import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_android as release  # noqa: E402

PT_LOAD, PT_DYNAMIC = 1, 2


def elf64(alignments: list[tuple[int, int]]) -> bytes:
    """A little-endian ELF64 header and its program headers: (type, align)."""
    phoff, phentsize = 64, 56
    header = b"\x7fELF" + bytes([2, 1, 1]) + bytes(9)
    header += struct.pack("<HHIQQQIHHHHHH", 3, 183, 1, 0, phoff, 0, 0, 64, phentsize, len(alignments), 0, 0, 0)
    for p_type, p_align in alignments:
        header += struct.pack("<IIQQQQQQ", p_type, 5, 0, 0, 0, 0, 0, p_align)
    return header


def elf32(alignments: list[tuple[int, int]]) -> bytes:
    phoff, phentsize = 52, 32
    header = b"\x7fELF" + bytes([1, 1, 1]) + bytes(9)
    header += struct.pack("<HHIIIIIHHHHHH", 3, 40, 1, 0, phoff, 0, 0, 52, phentsize, len(alignments), 0, 0, 0)
    for p_type, p_align in alignments:
        header += struct.pack("<IIIIIIII", p_type, 0, 0, 0, 0, 0, 5, p_align)
    return header


def test_the_loadable_segments_alignments_64_bit():
    elf = elf64([(PT_LOAD, 0x4000), (PT_DYNAMIC, 8), (PT_LOAD, 0x1000)])
    assert release.load_alignments(elf) == [0x4000, 0x1000]


def test_the_loadable_segments_alignments_32_bit():
    assert release.load_alignments(elf32([(PT_LOAD, 0x1000), (PT_LOAD, 0x1000)])) == [0x1000, 0x1000]


def test_not_an_elf_file_says_so():
    with pytest.raises(ValueError):
        release.load_alignments(b"PK\x03\x04")


def test_a_bundle_names_its_64_bit_libraries_under_16_kb_only(tmp_path):
    aab = tmp_path / "app-release.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        bundle.writestr("base/lib/arm64-v8a/libok.so", elf64([(PT_LOAD, 0x4000), (PT_LOAD, 0x4000)]))
        bundle.writestr("base/lib/x86_64/libbad.so", elf64([(PT_LOAD, 0x4000), (PT_LOAD, 0x1000)]))
        # 32-bit: no 16 KB device runs it, so it's exempt.
        bundle.writestr("base/lib/armeabi-v7a/libold.so", elf32([(PT_LOAD, 0x1000)]))
        bundle.writestr("base/dex/classes.dex", b"dex\n")
    assert release.misaligned(aab) == ["base/lib/x86_64/libbad.so: segments aligned to 4096 bytes"]


def test_check_without_a_bundle_asks_for_a_build(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(release, "BUNDLE", tmp_path / "none.aab")
    assert release.main(["--check"]) == 2
    assert "build it first" in capsys.readouterr().err


def test_a_misaligned_bundle_fails_the_check(tmp_path, monkeypatch):
    aab = tmp_path / "app-release.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        bundle.writestr("base/lib/arm64-v8a/libbad.so", elf64([(PT_LOAD, 0x1000)]))
    monkeypatch.setattr(release, "BUNDLE", aab)
    assert release.main(["--check"]) == 1


def test_the_key_is_read_from_the_bundles_certificate(tmp_path, monkeypatch):
    monkeypatch.setattr(release, "keytool", lambda: "keytool")

    def printcert(output):
        return lambda *args, **kwargs: type("Done", (), {"stdout": output})()

    monkeypatch.setattr(release.subprocess, "run", printcert(
        "Signer #1:\n\nCertificate #1:\nOwner: C=US, O=Android, CN=Android Debug\n"))
    assert "DEBUG" in release.signed_by(release.signer(tmp_path / "app.aab"))

    monkeypatch.setattr(release.subprocess, "run", printcert(
        "Certificate #1:\nOwner: CN=Rahmat Ullah, O=Sogda\nIssuer: CN=Rahmat Ullah\n"))
    assert release.signed_by(release.signer(tmp_path / "app.aab")) == "CN=Rahmat Ullah, O=Sogda"

    monkeypatch.setattr(release.subprocess, "run", printcert("Not a signed jar file\n"))
    assert "UNKNOWN" in release.signed_by(release.signer(tmp_path / "app.aab"))


def test_without_keytool_the_key_is_unknown(tmp_path, monkeypatch):
    monkeypatch.setattr(release, "keytool", lambda: None)
    assert release.signer(tmp_path / "app.aab") is None


def test_the_owners_checkout_builds_without_the_lock(monkeypatch):
    built = []
    monkeypatch.setattr(release.device, "agent", lambda: "")
    monkeypatch.setattr(release, "build", lambda: built.append(True))
    monkeypatch.setattr(release, "BUNDLE", Path("no-such.aab"))
    release.main([])
    assert built == [True]


def test_an_agent_without_the_lock_is_refused(monkeypatch):
    monkeypatch.setattr(release.device, "agent", lambda: "agent-2")
    monkeypatch.setattr(release, "holds_device", lambda who: False)
    monkeypatch.setattr(release, "build", lambda: pytest.fail("built without the lock"))
    assert release.main([]) == 2


MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="de.sogda.app">
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.WAKE_LOCK" />
  <uses-permission android:name="de.sogda.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" />
  <application>
    <service android:name="androidx.work.impl.foreground.SystemForegroundService" />
    {service}
  </application>
</manifest>
"""
RELEASE_MD = """  - **Permissions**, as the merged manifest has them:
    - `INTERNET`: model downloads.
    - `WAKE_LOCK`: WorkManager.

  - **Foreground services:** none (`FOREGROUND_SERVICE` is removed).
"""


def test_611_the_merged_permissions_are_the_documented_ones(tmp_path):
    manifest, docs = tmp_path / "AndroidManifest.xml", tmp_path / "release.md"
    manifest.write_text(MANIFEST.format(service=""), encoding="utf-8")
    docs.write_text(RELEASE_MD, encoding="utf-8")
    assert release.permission_problems(manifest, docs) == []

    docs.write_text(RELEASE_MD.replace("    - `WAKE_LOCK`: WorkManager.\n", "    - `VIBRATE`: the reminder.\n"),
                    encoding="utf-8")
    assert release.permission_problems(manifest, docs) == [
        "WAKE_LOCK: asked for, but not in release.md's list",
        "VIBRATE: in release.md's list, but not asked for",
    ]


def test_611_a_plugins_own_or_sdk23_permission_is_checked_too(tmp_path):
    # Only the app's own permission is left out: a plugin's AD_ID (Play asks
    # about the advertising ID) or a <uses-permission-sdk-23> must be listed.
    manifest, docs = tmp_path / "AndroidManifest.xml", tmp_path / "release.md"
    manifest.write_text(MANIFEST.format(service="").replace(
        "  <application>",
        '  <uses-permission android:name="com.google.android.gms.permission.AD_ID" />\n'
        '  <uses-permission-sdk-23 android:name="android.permission.READ_CONTACTS" />\n  <application>'),
        encoding="utf-8")
    docs.write_text(RELEASE_MD, encoding="utf-8")
    assert release.permission_problems(manifest, docs) == [
        "READ_CONTACTS: asked for, but not in release.md's list",
        "com.google.android.gms.permission.AD_ID: asked for, but not in release.md's list",
    ]
    docs.write_text(RELEASE_MD.replace(
        "    - `WAKE_LOCK`: WorkManager.\n",
        "    - `WAKE_LOCK`: WorkManager.\n    - `READ_CONTACTS`: x.\n"
        "    - `com.google.android.gms.permission.AD_ID`: x.\n"), encoding="utf-8")
    assert release.permission_problems(manifest, docs) == []


def test_611_a_foreground_service_type_fails_the_check(tmp_path):
    manifest, docs = tmp_path / "AndroidManifest.xml", tmp_path / "release.md"
    manifest.write_text(MANIFEST.format(service='<service android:name="x.Job" android:foregroundServiceType="dataSync" />'),
                        encoding="utf-8")
    docs.write_text(RELEASE_MD, encoding="utf-8")
    assert release.permission_problems(manifest, docs) == [
        "x.Job: a foreground-service type, which Play asks to declare"]
    assert "build it first" in release.permission_problems(tmp_path / "none.xml", docs)[0]


def test_611_the_real_release_md_lists_permissions():
    # The list the check reads is where it expects it, and not empty.
    listed = release.RELEASE_MD.read_text(encoding="utf-8").split("**Permissions**", 1)[1].split("\n\n", 1)[0]
    assert "`RECORD_AUDIO`" in listed and "FOREGROUND_SERVICE" not in listed


def whole_bundle(tmp_path: Path) -> Path:
    """A bundle with the engine and the app's code for every ABI, the
    64-bit ones aligned to 16 KB."""
    aab = tmp_path / "app-release.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        for lib in ("libflutter.so", "libapp.so"):
            bundle.writestr(f"base/lib/armeabi-v7a/{lib}", elf32([(PT_LOAD, 0x1000)]))
        for abi in ("arm64-v8a", "x86_64"):
            for lib in ("libflutter.so", "libapp.so"):
                bundle.writestr(f"base/lib/{abi}/{lib}", elf64([(PT_LOAD, 0x4000)]))
    return aab


@pytest.fixture()
def passing(tmp_path, monkeypatch):
    """Everything but what a test sets otherwise passes."""
    monkeypatch.setattr(release, "BUNDLE", whole_bundle(tmp_path))
    monkeypatch.setattr(release, "keytool", lambda: None)
    monkeypatch.setattr(release, "permission_problems", lambda: [])
    monkeypatch.setattr(release, "missing_symbols", lambda: [])
    monkeypatch.setattr(release, "keep_symbols", lambda version: tmp_path / "kept")


def test_611_permissions_that_differ_fail_the_check(passing, monkeypatch):
    assert release.main(["--check"]) == 0
    monkeypatch.setattr(release, "permission_problems", lambda: ["WAKE_LOCK: asked for, but not in release.md's list"])
    assert release.main(["--check"]) == 1


def test_611_the_app_manifest_removes_the_foreground_services():
    # What the merged manifest loses; the release check proves the result.
    import xml.etree.ElementTree as ET
    tools = "{http://schemas.android.com/tools}"
    root = ET.parse(release.APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml").getroot()
    removed = {e.get(release.ANDROID + "name") for e in root.iter("uses-permission") if e.get(tools + "node") == "remove"}
    assert removed == {"android.permission.FOREGROUND_SERVICE", "android.permission.FOREGROUND_SERVICE_SHORT_SERVICE"}
    untyped = {e.get(release.ANDROID + "name") for e in root.iter("service")
               if e.get(tools + "remove") == "android:foregroundServiceType"}
    assert untyped == {"androidx.work.impl.foreground.SystemForegroundService",
                       "com.bbflight.background_downloader.UIDTJobService"}


def test_697_a_bundle_without_the_engine_or_the_app_fails(tmp_path, passing, monkeypatch):
    # TL-9: with no library at all, the 16 KB check passed on nothing.
    aab = tmp_path / "half.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        bundle.writestr("base/lib/arm64-v8a/libflutter.so", elf64([(PT_LOAD, 0x4000)]))
        bundle.writestr("base/dex/classes.dex", b"dex\n")
    assert release.missing_libs(aab) == [
        "base/lib/armeabi-v7a/libflutter.so: missing",
        "base/lib/armeabi-v7a/libapp.so: missing",
        "base/lib/arm64-v8a/libapp.so: missing",
        "base/lib/x86_64/libflutter.so: missing",
        "base/lib/x86_64/libapp.so: missing",
    ]
    assert release.missing_libs(release.BUNDLE) == []
    monkeypatch.setattr(release, "BUNDLE", aab)
    assert release.main(["--check"]) == 1


def test_697_the_symbols_are_checked_and_kept_under_the_version(tmp_path):
    symbols = tmp_path / "symbols"
    symbols.mkdir()
    (symbols / "app.android-arm.symbols").write_bytes(b"dwarf")
    (symbols / "app.android-arm64.symbols").write_bytes(b"dwarf")
    assert release.missing_symbols(symbols) == [f"{symbols / 'app.android-x64.symbols'}: missing"]
    (symbols / "app.android-x64.symbols").write_bytes(b"")
    assert release.missing_symbols(symbols) == [f"{symbols / 'app.android-x64.symbols'}: missing"]
    (symbols / "app.android-x64.symbols").write_bytes(b"dwarf")
    assert release.missing_symbols(symbols) == []

    kept = release.keep_symbols("1.0.1+2", symbols, tmp_path / "kept")
    assert kept == tmp_path / "kept" / "1.0.1-2"
    assert (kept / "app.android-arm64.symbols").read_bytes() == b"dwarf"


def test_697_missing_symbols_fail_the_check(passing, monkeypatch):
    monkeypatch.setattr(release, "missing_symbols", lambda: ["app.android-x64.symbols: missing"])
    monkeypatch.setattr(release, "keep_symbols", lambda version: pytest.fail("kept symbols that aren't there"))
    assert release.main(["--check"]) == 1


def test_697_the_app_version_names_the_kept_folder(tmp_path):
    pubspec = tmp_path / "pubspec.yaml"
    pubspec.write_text("name: sogda\nversion: 1.0.2+3\n", encoding="utf-8")
    assert release.app_version(pubspec) == "1.0.2+3"


def test_697_require_upload_key_fails_a_debug_or_unsigned_bundle(passing, monkeypatch):
    assert release.main(["--check"]) == 0
    monkeypatch.setattr(release, "signer", lambda bundle: "C=US, O=Android, CN=Android Debug")
    assert release.main(["--check"]) == 0, "reported, not failed, without the flag"
    assert release.main(["--check", "--require-upload-key"]) == 1
    monkeypatch.setattr(release, "signer", lambda bundle: None)
    assert release.main(["--check", "--require-upload-key"]) == 1
    monkeypatch.setattr(release, "signer", lambda bundle: "CN=Sogda Upload, O=Sogda")
    assert release.main(["--check", "--require-upload-key"]) == 0


def test_858_32_bit_arm_ships_so_its_libraries_and_symbols_are_checked(tmp_path):
    # No ABI filter: armeabi-v7a is in the bundle, and its crashes need
    # app.android-arm.symbols to be read.
    aab = tmp_path / "no-arm.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        for abi in ("arm64-v8a", "x86_64"):
            for lib in ("libflutter.so", "libapp.so"):
                bundle.writestr(f"base/lib/{abi}/{lib}", elf64([(PT_LOAD, 0x4000)]))
    assert release.missing_libs(aab) == [
        "base/lib/armeabi-v7a/libflutter.so: missing",
        "base/lib/armeabi-v7a/libapp.so: missing",
    ]
    symbols = tmp_path / "symbols"
    symbols.mkdir()
    for name in ("app.android-arm64.symbols", "app.android-x64.symbols"):
        (symbols / name).write_bytes(b"dwarf")
    assert release.missing_symbols(symbols) == [f"{symbols / 'app.android-arm.symbols'}: missing"]


def test_858_the_symbols_are_kept_only_when_every_check_passes(passing, monkeypatch):
    kept = []
    monkeypatch.setattr(release, "keep_symbols", lambda version: kept.append(version))
    monkeypatch.setattr(release, "permission_problems", lambda: ["WAKE_LOCK: asked for, but not in release.md's list"])
    assert release.main(["--check"]) == 1
    assert kept == []
    monkeypatch.setattr(release, "permission_problems", lambda: [])
    assert release.main(["--check"]) == 0
    assert len(kept) == 1


def test_845_the_assets_db_readme_stays_out_of_the_bundle():
    # #707 names the two files: declaring the folder ships its README too.
    import yaml
    pubspec = yaml.safe_load((release.APP / "pubspec.yaml").read_text(encoding="utf-8"))
    assets = pubspec["flutter"]["assets"]
    assert "assets/db/" not in assets and "assets/db" not in assets
    assert {"assets/db/content.db", "assets/db/content_manifest.json"} <= set(assets)
