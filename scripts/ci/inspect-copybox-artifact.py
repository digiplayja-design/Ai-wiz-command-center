#!/usr/bin/env python3
"""Inspect COPY Box native dependencies without an SDK or signing credentials.

Android checks ELF load segments and, for APKs, uncompressed-library ZIP offsets.
An AAB's generated APK layout still needs bundletool/Play verification. iOS checks
the compiled app for unused legacy media/location dependencies; it does not
replace device testing or codesign verification.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile

PACKAGE = "com.korlixdeveloper.copybox"
PAGE_SIZE = 16384
MACHO_MAGIC = {
    bytes.fromhex(value) for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}
UNUSED_IOS_REFERENCES = (
    b"DKImagePickerController", b"DKPhotoGallery", b"DKCamera",
    b"CLLocationManager", b"requestWhenInUseAuthorization",
    b"requestAlwaysAuthorization",
)


def elf_load_segments(stream, file_size):
    header = stream.read(64)
    if len(header) < 52 or header[:4] != b"\x7fELF":
        raise ValueError("Native library is not an ELF binary")
    kind, byte_order = header[4:6]
    if kind not in (1, 2) or byte_order not in (1, 2):
        raise ValueError("Unsupported ELF class or byte order")
    endian = "<" if byte_order == 1 else ">"
    if kind == 2:
        if len(header) < 64:
            raise ValueError("Truncated ELF64 header")
        offset = struct.unpack_from(endian + "Q", header, 32)[0]
        entry_size, count = struct.unpack_from(endian + "HH", header, 54)
        entry_format = endian + "IIQQQQQQ"
    else:
        offset = struct.unpack_from(endian + "I", header, 28)[0]
        entry_size, count = struct.unpack_from(endian + "HH", header, 42)
        entry_format = endian + "IIIIIIII"
    if (entry_size < struct.calcsize(entry_format) or count == 0
            or offset + entry_size * count > file_size):
        raise ValueError("Invalid ELF program header table")
    stream.seek(offset)
    table = stream.read(entry_size * count)
    segments = []
    for index in range(count):
        entry = struct.unpack_from(entry_format, table, index * entry_size)
        if entry[0] != 1:  # PT_LOAD
            continue
        file_offset, address = (entry[2], entry[3]) if kind == 2 else (entry[1], entry[2])
        segments.append({
            "alignment": entry[-1],
            "offset": file_offset,
            "virtual_address": address,
        })
    if not segments:
        raise ValueError("ELF binary contains no load segments")
    return kind, segments


def inspect_android(path):
    if path.suffix not in (".apk", ".aab"):
        raise ValueError("Choose an Android APK or AAB")
    is_apk = path.suffix == ".apk"
    errors, libraries = [], []
    with zipfile.ZipFile(path) as archive, path.open("rb") as raw:
        for entry in archive.infolist():
            if not re.fullmatch(r"(?:[^/]+/)?lib/[^/]+/[^/]+\.so", entry.filename):
                continue
            with archive.open(entry) as stream:
                kind, segments = elf_load_segments(stream, entry.file_size)
            aligned = all(
                segment["alignment"] >= PAGE_SIZE
                and (segment["alignment"] & (segment["alignment"] - 1)) == 0
                and (segment["virtual_address"] - segment["offset"]) % PAGE_SIZE == 0
                for segment in segments
            )
            item = {
                "library": entry.filename,
                "elf_class": 64 if kind == 2 else 32,
                "load_segment_alignments": [segment["alignment"] for segment in segments],
                "elf_load_16k_aligned": aligned,
                "zip_compressed": entry.compress_type != zipfile.ZIP_STORED,
            }
            if kind == 2 and not aligned:
                errors.append(f"64-bit ELF is not 16KB aligned: {entry.filename}")
            if is_apk and entry.compress_type == zipfile.ZIP_STORED:
                raw.seek(entry.header_offset)
                local_header = raw.read(30)
                if local_header[:4] != b"PK\x03\x04":
                    raise ValueError("Invalid local ZIP header")
                name_length, extra_length = struct.unpack_from("<HH", local_header, 26)
                data_offset = entry.header_offset + 30 + name_length + extra_length
                item["zip_data_offset_mod_16k"] = data_offset % PAGE_SIZE
                if data_offset % PAGE_SIZE:
                    errors.append(f"Uncompressed APK library is not ZIP-aligned: {entry.filename}")
            libraries.append(item)
    if not any("/arm64-v8a/" in item["library"] for item in libraries):
        errors.append("The Flutter artifact contains no arm64-v8a native libraries")
    return {
        "artifact_type": "APK" if is_apk else "AAB",
        "libraries": libraries,
        "apk_zip_layout_checked": is_apk,
        "additional_check": (
            "Run on a 16KB-page Android device; this check does not verify runtime behavior or signing."
            if is_apk else
            "Check bundletool dump config for PAGE_ALIGNMENT_16K and verify a generated APK; AAB ZIP offsets are not APK offsets."
        ),
        "validation_errors": errors,
    }


def inspect_ios(path):
    archive = None
    if path.is_dir() and path.suffix == ".app":
        names = [item.relative_to(path).as_posix() for item in path.rglob("*") if item.is_file()]
        open_file = lambda name: (path / name).open("rb")
        info_name = "Info.plist"
        prefix = ""
    else:
        archive = zipfile.ZipFile(path)
        names = archive.namelist()
        open_file = archive.open
        infos = [name for name in names if re.fullmatch(r"(?:Payload/)?[^/]+\.app/Info\.plist", name)]
        if len(infos) != 1:
            archive.close()
            raise ValueError("Expected one top-level application in the iOS archive")
        info_name = infos[0]
        prefix = info_name.removesuffix("Info.plist")
    try:
        with open_file(info_name) as stream:
            info = plistlib.load(stream)
        errors, binaries, references = [], [], []
        if info.get("CFBundleIdentifier") != PACKAGE:
            errors.append("Compiled iOS application has the wrong bundle identifier")
        protected_access = sorted(
            key for key in info if key.startswith("NS") and key.endswith("UsageDescription")
        )
        # Flutter's debug simulator injects the VM-service local-network prompt.
        # It is unrelated to the media/location APIs this release must exclude.
        allowed_debug_access = (
            {"NSLocalNetworkUsageDescription"}
            if info.get("CFBundleSupportedPlatforms") == ["iPhoneSimulator"] else set()
        )
        if set(protected_access) - allowed_debug_access:
            errors.append("COPY Box must not declare unused protected device access")
        for name in names:
            if not name.startswith(prefix) or name.endswith("/") or name.startswith("__MACOSX/"):
                continue
            with open_file(name) as stream:
                magic = stream.read(4)
                if magic not in MACHO_MAGIC:
                    continue
                binary = magic + stream.read()
            binaries.append(name)
            matches = [needle.decode() for needle in UNUSED_IOS_REFERENCES if needle in binary]
            if matches:
                references.append({"binary": name, "references": matches})
        if references:
            errors.append("Unused legacy media or location references remain in the compiled iOS app")
        if not binaries:
            errors.append("No Mach-O application binaries were inspected")
        return {
            "bundle_identifier": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"),
            "platforms": info.get("CFBundleSupportedPlatforms", []),
            "protected_access_purpose_strings": protected_access,
            "mach_o_binaries_inspected": len(binaries),
            "unused_native_references": references,
            "privacy_manifests": sorted(name for name in names if name.endswith("PrivacyInfo.xcprivacy") and not name.startswith("__MACOSX/")),
            "validation_errors": errors,
        }
    finally:
        if archive is not None:
            archive.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("android", "ios"))
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = {"artifact": args.artifact.name}
    try:
        result.update((inspect_android if args.platform == "android" else inspect_ios)(args.artifact))
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile) as error:
        result["validation_errors"] = [str(error)]
    encoded = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    print(encoded, end="")
    raise SystemExit(1 if result["validation_errors"] else 0)


if __name__ == "__main__":
    main()
