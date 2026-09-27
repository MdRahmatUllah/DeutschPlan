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


def test_611_permissions_that_differ_fail_the_check(tmp_path, monkeypatch):
    aab = tmp_path / "app-release.aab"
    with zipfile.ZipFile(aab, "w") as bundle:
        bundle.writestr("base/lib/arm64-v8a/libgood.so", elf64([(PT_LOAD, 0x4000)]))
    monkeypatch.setattr(release, "BUNDLE", aab)
    monkeypatch.setattr(release, "keytool", lambda: None)
    monkeypatch.setattr(release, "permission_problems", lambda: [])
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
