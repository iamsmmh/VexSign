#!/usr/bin/env python3
"""Generates the deterministic test fixtures committed under VexSignTests/Fixtures/.

Run this script to regenerate every fixture byte-for-byte (outputs are stable:
fixed timestamps, no randomness):

    python3 tools/make_test_fixtures.py

What it builds (see docs/engineering/VEXSIGN_TESTING.md for the corpus map):

IPAs (zips with Payload/<App>.app):
  Minimal.ipa          one-bundle app, valid Info.plist + synthetic arm64 executable
  Frameworks.ipa       Frameworks/Alpha.framework + Frameworks/Beta.framework
  Appex.ipa            PlugIns/Share.appex (share-services extension point)
  Nested.ipa           frameworks + appex + Watch app + root dylib
  MalformedPlist.ipa   Info.plist is garbage bytes (signing must fail cleanly)
  WrongBundleID.ipa    bundle id differs from the app's "expected" id
  InjectedDylib.ipa    main binary already carries an LC_LOAD_DYLIB
  NoPayload.ipa        zip without a Payload/ folder (import must fail at move)

Tweaks:
  plain.dylib          arm64 dylib, links only libSystem
  substrate.dylib      links CydiaSubstrate (substrate-hook detection)
  rpath.dylib          links @rpath/... libraries (rpath recommendation)
  Sample.framework/    framework bundle with a readable executable
  Resource.bundle/     resource-only bundle (not injectable)
  Share.appex/         app extension with NSExtensionPointIdentifier
  substrate-tweak.deb  ar archive: control depends on mobilesubstrate,
                       data installs into MobileSubstrate/DynamicLibraries
  plain-tweak.deb      dylib deb without substrate markers
  empty.deb            control only, no data payload
  garbage.dylib        random non-Mach-O bytes

Sources:
  sample-repo.json     trimmed AltStore-format repository (deterministic decode)

The Mach-O files are *synthetic*: just enough header + LC_LOAD_DYLIB commands
for VexSign's MachOReader/TweakAnalyzer to characterize. They are NOT used as
evidence that real signing/injection works, and never as signing inputs for
crypto tests (see the Phase 1 mandate). The layout mirrors the minimal ZIP and
Mach-O writers used by VexSignTests/Fixtures/FixtureSupport.swift, which
generates the adversarial archives (traversal/symlink/bombs) at test runtime.
"""

from __future__ import annotations

import gzip
import io
import json
import plistlib
import shutil
import struct
import tarfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "VexSignTests" / "Fixtures"

# ---------------------------------------------------------------------------
# Minimal ZIP writer (STORE method). Mirrors FixtureSupport.MiniZipWriter.
# ---------------------------------------------------------------------------

def _dos_datetime() -> tuple[int, int]:
    # Fixed date (2024-01-02 03:04:06) → deterministic archives.
    return (0x60 << 9) | (3 << 11) | (4 << 5) | (6 // 2), ((2024 - 1980) << 9) | (1 << 5) | 2


def zip_store(entries: list[tuple[str, bytes]], symlinks: dict[str, str] | None = None) -> bytes:
    """Builds a minimal ZIP (STORE only) with the given entry names/contents.

    `symlinks` maps entry name -> link target (stored as content, type flagged
    via external attributes). Deliberately allows unsafe names so security
    fixtures can exercise the validator.
    """
    symlinks = symlinks or {}
    dos_time, dos_date = _dos_datetime()
    local_parts: list[bytes] = []
    central_parts: list[bytes] = []
    offset = 0

    for name, content in entries:
        name_bytes = name.encode("utf-8", "surrogateescape")
        crc = zlib.crc32(content) & 0xFFFFFFFF
        is_link = name in symlinks
        external = 0xA0000000 if is_link else 0x81A40000  # symlink / 0644 file

        local_parts.append(struct.pack(
            "<4sHHHHHIIIHH",
            b"PK\x03\x04", 20, 0, 0, dos_time, dos_date,
            crc, len(content), len(content), len(name_bytes), 0,
        ))
        local_parts.append(name_bytes)
        local_parts.append(content)

        central_parts.append(struct.pack(
            "<4sHHHHHHIIIHHHHHII",
            b"PK\x01\x02", 20, 20, 0, 0, dos_time, dos_date,
            crc, len(content), len(content), len(name_bytes), 0, 0, 0, 0,
            external, offset,
        ))
        central_parts.append(name_bytes)
        offset += 30 + len(name_bytes) + len(content)

    central = b"".join(central_parts)
    eocd = struct.pack(
        "<4sHHHHIIH",
        b"PK\x05\x06", 0, 0, len(entries), len(entries),
        len(central), offset, 0,
    )
    return b"".join(local_parts) + central + eocd


# ---------------------------------------------------------------------------
# Synthetic Mach-O (arm64, little-endian) — header + LC_LOAD_DYLIB commands.
# ---------------------------------------------------------------------------

MH_EXECUTE, MH_DYLIB = 0x2, 0x6
CPU_TYPE_ARM64 = 0x0100000C
LC_LOAD_DYLIB = 0x0C


def macho(filetype: int, dylibs: list[str]) -> bytes:
    load_commands = b""
    for path in dylibs:
        name = path.encode() + b"\x00"
        # dylib struct: name offset (24), timestamp, current, compat versions.
        body = struct.pack("<IIII", 24, 0, 0x10000, 0x10000) + name
        while len(body) % 8:
            body += b"\x00"
        load_commands += struct.pack("<II", LC_LOAD_DYLIB, 8 + len(body)) + body

    header = struct.pack(
        "<IiiIIIII",
        0xFEEDFACF, CPU_TYPE_ARM64, 0, filetype,
        len(dylibs), len(load_commands), 0, 0,
    )
    assert len(header) == 32, "mach_header_64 must be exactly 32 bytes"
    # Pad to a page-ish size so tools that expect a non-trivial file are happy.
    return header + load_commands + b"\x00" * 64


# ---------------------------------------------------------------------------
# App / IPA builders
# ---------------------------------------------------------------------------

def info_plist(**overrides) -> bytes:
    base = {
        "CFBundleIdentifier": "com.vexsign.fixture.minimal",
        "CFBundleName": "Minimal",
        "CFBundleDisplayName": "Minimal Fixture",
        "CFBundleExecutable": "Minimal",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "CFBundlePackageType": "APPL",
        "MinimumOSVersion": "15.0",
        "UISupportedDevices": ["iPhone14,2"],
        "CFBundleURLTypes": [{"CFBundleURLName": "minimal", "CFBundleURLSchemes": ["minimal"]}],
    }
    base.update(overrides)
    return plistlib.dumps(base, fmt=plistlib.FMT_BINARY)


def app_bundle(name: str, plist: bytes, executable: bytes, extra: dict[str, bytes] | None = None) -> list[tuple[str, bytes]]:
    prefix = f"Payload/{name}.app/"
    entries = [
        (prefix + "Info.plist", plist),
        (prefix + name, executable),
        (prefix + "PkgInfo", b"APPL????"),
    ]
    for path, data in (extra or {}).items():
        entries.append((prefix + path, data))
    return entries


def write_ipa(path: Path, entries: list[tuple[str, bytes]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(zip_store(entries))


# ---------------------------------------------------------------------------
# .deb (ar + tar.gz) builders
# ---------------------------------------------------------------------------

def tar_gz(files: dict[str, bytes]) -> bytes:
    tar_buf = io.BytesIO()
    with tarfile.open(fileobj=tar_buf, mode="w") as tar:
        for name, content in files.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            info.mtime = 0
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(content))
    gz_buf = io.BytesIO()
    with gzip.GzipFile(fileobj=gz_buf, mode="wb", mtime=0) as gz:
        gz.write(tar_buf.getvalue())
    return gz_buf.getvalue()


def ar_archive(members: list[tuple[str, bytes]]) -> bytes:
    out = bytearray(b"!<arch>\n")
    for name, content in members:
        header = f"{name:<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(content):<10}`\n"
        out += header.encode()
        out += content
        if len(content) % 2:
            out += b"\n"
    return bytes(out)


def deb(control: str, data_files: dict[str, bytes] | None) -> bytes:
    members = [("debian-binary", b"2.0\n")]
    members.append(("control.tar.gz", tar_gz({"./control": control.encode()})))
    if data_files:
        members.append(("data.tar.gz", tar_gz(data_files)))
    return ar_archive(members)


# ---------------------------------------------------------------------------
# Fixture corpus
# ---------------------------------------------------------------------------

def build_ipas() -> None:
    exe = lambda loads: macho(MH_EXECUTE, loads)
    dylib = lambda loads: macho(MH_DYLIB, loads)
    libsystem = ["/usr/lib/libSystem.B.dylib"]

    write_ipa(OUT / "IPAs/Minimal.ipa", app_bundle(
        "Minimal", info_plist(), exe(libsystem)))

    alpha_fw = [
        ("Payload/Frameworks.app/Frameworks/Alpha.framework/Alpha", dylib(libsystem)),
        ("Payload/Frameworks.app/Frameworks/Alpha.framework/Info.plist",
         plistlib.dumps({"CFBundleExecutable": "Alpha", "CFBundleIdentifier": "com.fixture.alpha",
                         "CFBundlePackageType": "FMWK"}, fmt=plistlib.FMT_BINARY)),
        ("Payload/Frameworks.app/Frameworks/Beta.framework/Beta", dylib(libsystem)),
        ("Payload/Frameworks.app/Frameworks/Beta.framework/Info.plist",
         plistlib.dumps({"CFBundleExecutable": "Beta", "CFBundleIdentifier": "com.fixture.beta",
                         "CFBundlePackageType": "FMWK"}, fmt=plistlib.FMT_BINARY)),
    ]
    write_ipa(OUT / "IPAs/Frameworks.ipa", app_bundle(
        "Frameworks",
        info_plist(CFBundleIdentifier="com.vexsign.fixture.frameworks",
                   CFBundleName="Frameworks", CFBundleExecutable="Frameworks"),
        exe(libsystem + ["@rpath/Alpha.framework/Alpha"]),
    ) + alpha_fw)

    appex = [
        ("Payload/Appex.app/PlugIns/Share.appex/Share", dylib(libsystem)),
        ("Payload/Appex.app/PlugIns/Share.appex/Info.plist",
         plistlib.dumps({
             "CFBundleExecutable": "Share", "CFBundleIdentifier": "com.vexsign.fixture.appex.share",
             "CFBundlePackageType": "XPC!",
             "NSExtension": {"NSExtensionPointIdentifier": "com.apple.share-services"},
         }, fmt=plistlib.FMT_BINARY)),
    ]
    write_ipa(OUT / "IPAs/Appex.ipa", app_bundle(
        "Appex",
        info_plist(CFBundleIdentifier="com.vexsign.fixture.appex",
                   CFBundleName="Appex", CFBundleExecutable="Appex"),
        exe(libsystem),
    ) + appex)

    nested = [
        ("Payload/Nested.app/Frameworks/Alpha.framework/Alpha", dylib(libsystem)),
        ("Payload/Nested.app/Frameworks/Alpha.framework/Info.plist",
         plistlib.dumps({"CFBundleExecutable": "Alpha", "CFBundleIdentifier": "com.fixture.alpha",
                         "CFBundlePackageType": "FMWK"}, fmt=plistlib.FMT_BINARY)),
        ("Payload/Nested.app/PlugIns/Widget.appex/Widget", dylib(libsystem)),
        ("Payload/Nested.app/PlugIns/Widget.appex/Info.plist",
         plistlib.dumps({
             "CFBundleExecutable": "Widget", "CFBundleIdentifier": "com.vexsign.fixture.nested.widget",
             "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
         }, fmt=plistlib.FMT_BINARY)),
        ("Payload/Nested.app/Watch/Companion.app/Companion", exe(libsystem)),
        ("Payload/Nested.app/Watch/Companion.app/Info.plist",
         plistlib.dumps({
             "CFBundleExecutable": "Companion", "CFBundleIdentifier": "com.vexsign.fixture.nested.watchapp",
             "WKCompanionAppBundleIdentifier": "com.vexsign.fixture.nested",
         }, fmt=plistlib.FMT_BINARY)),
        ("Payload/Nested.app/Extra.dylib", dylib(libsystem)),
    ]
    write_ipa(OUT / "IPAs/Nested.ipa", app_bundle(
        "Nested",
        info_plist(CFBundleIdentifier="com.vexsign.fixture.nested",
                   CFBundleName="Nested", CFBundleExecutable="Nested"),
        exe(libsystem),
    ) + nested)

    write_ipa(OUT / "IPAs/MalformedPlist.ipa", app_bundle(
        "Broken", b"this is not a property list at all", exe(libsystem)))

    write_ipa(OUT / "IPAs/WrongBundleID.ipa", app_bundle(
        "Other",
        info_plist(CFBundleIdentifier="com.othercompany.otherapp",
                   CFBundleName="Other", CFBundleDisplayName="Other App",
                   CFBundleExecutable="Other"),
        exe(libsystem)))

    write_ipa(OUT / "IPAs/InjectedDylib.ipa", app_bundle(
        "Injected",
        info_plist(CFBundleIdentifier="com.vexsign.fixture.injected",
                   CFBundleName="Injected", CFBundleExecutable="Injected"),
        exe(libsystem + ["@rpath/Existing.dylib"]),
        {"Frameworks/Existing.dylib": dylib(libsystem)},
    ))

    write_ipa(OUT / "IPAs/NoPayload.ipa", [("README.txt", b"no payload here")])


def build_tweaks() -> None:
    t = OUT / "Tweaks"
    t.mkdir(parents=True, exist_ok=True)
    libsystem = ["/usr/lib/libSystem.B.dylib"]

    (t / "plain.dylib").write_bytes(macho(MH_DYLIB, libsystem))
    (t / "substrate.dylib").write_bytes(macho(
        MH_DYLIB, libsystem + ["/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
                               "/usr/lib/libsubstrate.dylib"]))
    (t / "rpath.dylib").write_bytes(macho(
        MH_DYLIB, libsystem + ["@rpath/Orion.framework/Orion", "@rpath/Sample.dylib"]))
    (t / "garbage.dylib").write_bytes(b"\xde\xad\xbe\xef not a mach-o " * 8)

    fw = t / "Sample.framework"
    if fw.exists():
        shutil.rmtree(fw)
    fw.mkdir(parents=True)
    (fw / "Sample").write_bytes(macho(MH_DYLIB, libsystem))
    (fw / "Info.plist").write_bytes(plistlib.dumps(
        {"CFBundleExecutable": "Sample", "CFBundleIdentifier": "com.fixture.sample",
         "CFBundlePackageType": "FMWK"}, fmt=plistlib.FMT_BINARY))

    rb = t / "Resource.bundle"
    if rb.exists():
        shutil.rmtree(rb)
    rb.mkdir(parents=True)
    (rb / "Info.plist").write_bytes(plistlib.dumps(
        {"CFBundleIdentifier": "com.fixture.resource"}, fmt=plistlib.FMT_BINARY))
    (rb / "Assets.bin").write_bytes(b"\x00\x01\x02resource-bytes")

    ap = t / "Share.appex"
    if ap.exists():
        shutil.rmtree(ap)
    ap.mkdir(parents=True)
    (ap / "Share").write_bytes(macho(MH_DYLIB, libsystem))
    (ap / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "Share", "CFBundleIdentifier": "com.fixture.share",
        "NSExtension": {"NSExtensionPointIdentifier": "com.apple.share-services"},
    }, fmt=plistlib.FMT_BINARY))

    (t / "substrate-tweak.deb").write_bytes(deb(
        "Package: com.fixture.substrate-tweak\n"
        "Version: 1.0\n"
        "Depends: mobilesubstrate, firmware (>= 15.0)\n"
        "Description: Test tweak that hooks via substrate.\n",
        {
            "./Library/MobileSubstrate/DynamicLibraries/tweak.dylib": macho(MH_DYLIB, libsystem),
            "./Library/MobileSubstrate/DynamicLibraries/tweak.plist": b"<plist><dict/></plist>",
        },
    ))
    (t / "plain-tweak.deb").write_bytes(deb(
        "Package: com.fixture.plain-tweak\n"
        "Version: 1.0\n"
        "Depends: preferenceloader\n"
        "Description: Test tweak without substrate markers.\n",
        {"./Library/TweakLoader/plain.dylib": macho(MH_DYLIB, libsystem)},
    ))
    (t / "empty.deb").write_bytes(deb(
        "Package: com.fixture.empty\nVersion: 1.0\nDescription: No payload.\n", None))


def build_sources() -> None:
    repo = json.loads((ROOT / "app-repo.json").read_text())
    trimmed = {
        "name": repo["name"],
        "subtitle": repo.get("subtitle"),
        "website": repo.get("website"),
        "sourceURL": "https://example.com/sample-repo.json",
        "apps": repo["apps"],
    }
    s = OUT / "Sources"
    s.mkdir(parents=True, exist_ok=True)
    (s / "sample-repo.json").write_text(json.dumps(trimmed, indent=2) + "\n")


# ---------------------------------------------------------------------------
# Self-checks: the fixtures must satisfy the same invariants the Swift tests
# assert, so a bad generator fails here instead of in CI.
# ---------------------------------------------------------------------------

def verify() -> None:
    import zipfile

    def rules_ok(name: str) -> bool:
        if not name or name.startswith("/") or name.startswith("~") or "\x00" in name or "\\" in name:
            return False
        parts = [p for p in name.split("/") if p]
        return all(p != ".." for p in parts)

    for ipa in (OUT / "IPAs").glob("*.ipa"):
        with zipfile.ZipFile(ipa) as zf:
            assert zf.testzip() is None, f"{ipa}: corrupt"
            for info in zf.infolist():
                assert rules_ok(info.filename), f"{ipa}: unsafe entry {info.filename}"
        if ipa.name != "NoPayload.ipa":
            with zipfile.ZipFile(ipa) as zf:
                payload = [n for n in zf.namelist() if n.startswith("Payload/") and n.endswith(".app/Info.plist")]
                assert payload, f"{ipa}: missing Payload/*.app/Info.plist"

    from struct import unpack_from
    for dylib in list((OUT / "Tweaks").glob("*.dylib")):
        if dylib.name == "garbage.dylib":
            continue
        data = dylib.read_bytes()
        magic, _, _, filetype, ncmds = unpack_from("<IiiII", data, 0)
        assert magic == 0xFEEDFACF and filetype == MH_DYLIB and ncmds > 0, dylib

    for d in (OUT / "Tweaks").glob("*.deb"):
        assert d.read_bytes().startswith(b"!<arch>\n"), d

    repo = json.loads((OUT / "Sources/sample-repo.json").read_text())
    assert repo["apps"] and repo["apps"][0]["versions"], "repo fixture lost its versions"

    print(f"fixtures OK: {sum(1 for _ in OUT.rglob('*') if _.is_file())} files under {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    build_ipas()
    build_tweaks()
    build_sources()
    verify()
