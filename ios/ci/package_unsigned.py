#!/usr/bin/env python3
"""Package an unsigned arm64 iPhoneOS archive as Payload/KMobile.app.

This does not sign, provision, export through Apple, or create a simulator IPA.
"""
import argparse
import os
import plistlib
import stat
import struct
import zipfile
from pathlib import Path


def validate_app(app):
    if not app.is_dir() or app.is_symlink():
        raise ValueError("Archive does not contain KMobile.app")
    with (app / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("DTPlatformName") != "iphoneos" or "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Expected an iPhoneOS device app, not a simulator build")
    name = info.get("CFBundleExecutable", "")
    if not name or Path(name).name != name or name in (".", ".."):
        raise ValueError("Invalid executable name")
    executable = app / name
    if executable.is_symlink() or not executable.is_file() or not executable.stat().st_mode & 0o111:
        raise ValueError("App executable is missing or has lost its executable permission")
    with executable.open("rb") as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError("Truncated Mach-O header")
        magic, cpu, _, kind, count, size, _, _ = struct.unpack("<8I", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 2 or count > 1024 or size > 1024 * 1024:
            raise ValueError("Expected a thin arm64 Mach-O executable")
        commands = stream.read(size)
    if len(commands) != size:
        raise ValueError("Truncated Mach-O load commands")
    offset, device_platform = 0, False
    for _ in range(count):
        if offset + 8 > len(commands):
            raise ValueError("Invalid Mach-O load commands")
        command, length = struct.unpack_from("<2I", commands, offset)
        if length < 8 or offset + length > len(commands):
            raise ValueError("Invalid Mach-O load command length")
        if command == 0x32:  # LC_BUILD_VERSION; PLATFORM_IOS = 2, IOS_SIMULATOR = 7
            if length < 24 or struct.unpack_from("<I", commands, offset + 8)[0] != 2:
                raise ValueError("Executable was not built for a physical iOS device")
            device_platform = True
        offset += length
    if offset != size or not device_platform:
        raise ValueError("Missing or malformed iOS platform load command")
    return name


def pack(archive, output):
    app = archive / "Products/Applications/KMobile.app"
    executable = validate_app(app)
    root = app.resolve()
    entries = []
    # Preflight the entire bundle before writing any output.
    for directory, dirs, files in os.walk(app, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if path.is_symlink():
                if Path(os.readlink(path)).is_absolute() or not path.resolve().is_relative_to(root):
                    raise ValueError("App contains a symlink outside its bundle")
            elif not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError("App contains an unsupported filesystem entry")
            entries.append(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".ipa.partial")
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in entries:
                name = "Payload/KMobile.app/" + path.relative_to(app).as_posix()
                if path.is_symlink():
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    info.external_attr = path.lstat().st_mode << 16
                    bundle.writestr(info, os.readlink(path))
                else:
                    # ZipFile.write preserves Unix file mode, including executable bits.
                    bundle.write(path, name)
        with zipfile.ZipFile(temporary) as bundle:
            if bundle.testzip() is not None or f"Payload/KMobile.app/{executable}" not in bundle.namelist():
                raise ValueError("IPA integrity check failed")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    pack(args.archive, args.output)
    print(f"Unsigned device IPA packaged: {args.output}")


if __name__ == "__main__":
    main()
