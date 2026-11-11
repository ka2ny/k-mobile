#!/usr/bin/env python3
"""Record the exact source and toolchain beside the build artifact."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = root / "build/ipa"
ipa = output / os.environ.get("IOS_IPA_NAME", "KMobile.ipa")
if not ipa.is_file() or not ipa.stat().st_size:
    raise SystemExit("Fastlane did not produce the requested IPA")
def digest(path):
    # Chunked by hand: hashlib.file_digest needs Python 3.11, and the runner's python3 is not pinned.
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            value.update(chunk)
    return value.hexdigest()


codemagic = bool(os.environ.get("CM_BUILD_ID"))
metadata = {
    "provider": "codemagic" if codemagic else "github",
    "commit": os.environ["CM_COMMIT" if codemagic else "GITHUB_SHA"],
    "run_id": os.environ["CM_BUILD_ID" if codemagic else "GITHUB_RUN_ID"],
    "run_attempt": "1" if codemagic else os.environ["GITHUB_RUN_ATTEMPT"],
    "requires_external_signing": os.environ["IOS_EXPORT_METHOD"] == "unsigned",
    "export_method": os.environ["IOS_EXPORT_METHOD"],
    "bundle_id": os.environ["IOS_BUNDLE_ID"],
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "sha256": {file.name: digest(file)
               for file in sorted(output.iterdir()) if file.suffix in (".ipa", ".zip")},
}
(output / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
