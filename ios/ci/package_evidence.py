#!/usr/bin/env python3
"""Record the exact source and toolchain beside the signed build artifact."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = root / "build/ipa"
ipa = output / "KMobile.ipa"
if not ipa.is_file() or not ipa.stat().st_size:
    raise SystemExit("Fastlane did not produce KMobile.ipa")
def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


metadata = {
    "commit": os.environ["GITHUB_SHA"],
    "run_id": os.environ["GITHUB_RUN_ID"],
    "run_attempt": os.environ["GITHUB_RUN_ATTEMPT"],
    "export_method": os.environ["IOS_EXPORT_METHOD"],
    "bundle_id": os.environ["IOS_BUNDLE_ID"],
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "sha256": {file.name: digest(file)
               for file in sorted(output.iterdir()) if file.suffix in (".ipa", ".zip")},
}
(output / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
