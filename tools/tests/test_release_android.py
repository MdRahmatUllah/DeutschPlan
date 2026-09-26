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


def test_the_key_is_named(tmp_path, monkeypatch):
    monkeypatch.setattr(release, "KEY_PROPERTIES", tmp_path / "key.properties")
    assert "DEBUG" in release.signed_by()
    (tmp_path / "key.properties").write_text("keyAlias=upload\n", encoding="utf-8")
    assert "upload key" in release.signed_by()
