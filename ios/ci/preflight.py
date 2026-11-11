#!/usr/bin/env python3
"""Select an available iPhone simulator for the project's required iOS SDK."""
import json
import os
import re
import subprocess
from pathlib import Path


def select_device(devices):
    candidates = []
    for runtime, rows in devices.items():
        match = re.fullmatch(r"com.apple.CoreSimulator.SimRuntime.iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
        if not match or int(match[1]) < 27:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        for device in rows:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        raise ValueError("No available iOS 27+ iPhone simulator. Select an Xcode 27 runner with its iOS runtime installed.")
    return sorted(candidates)[-1][2]


def main():
    subprocess.run(["xcodebuild", "-version"], check=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True).strip()
    if int(sdk.split(".")[0]) < 27:
        raise ValueError("This project requires iOS SDK 27+. Configure IOS_DEVELOPER_DIR for an installed Xcode 27.")
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    udid = select_device(devices["devices"])
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
        raise ValueError("Invalid simulator identifier")
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        stream.write(f"SIMULATOR_UDID={udid}\n")
    print(f"Selected iPhone simulator {udid}; device SDK {sdk}")


if __name__ == "__main__":
    main()
