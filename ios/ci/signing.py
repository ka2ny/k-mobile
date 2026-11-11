#!/usr/bin/env python3
"""Install signing secrets into a disposable macOS CI keychain, then clean up.

Only run on an ephemeral GitHub-hosted macOS runner. No Apple account mutations.
"""
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def validate_profile(profile, team, bundle_id, method, now=None):
    if method not in ("ad-hoc", "app-store"):
        raise ValueError("Choose ad-hoc or app-store export.")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("IOS_TEAM_ID must be the ten-character Apple team ID.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id):
        raise ValueError("IOS_BUNDLE_ID must be an explicit app bundle identifier.")
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Provisioning profile belongs to a different team.")
    entitlements = profile.get("Entitlements", {})
    allowed_ids = [f"{prefix}.{bundle_id}" for prefix in profile.get("ApplicationIdentifierPrefix", [])]
    if entitlements.get("application-identifier") not in allowed_ids:
        raise ValueError("Provisioning profile does not match the explicit bundle ID.")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise ValueError("Provisioning profile team entitlement does not match.")
    expiry = profile.get("ExpirationDate")
    now = now or dt.datetime.now(dt.timezone.utc)
    if not isinstance(expiry, dt.datetime) or expiry.replace(tzinfo=dt.timezone.utc) <= now:
        raise ValueError("Provisioning profile is expired or has no expiration date.")
    if entitlements.get("get-task-allow", False) or profile.get("ProvisionsAllDevices", False):
        raise ValueError("Use an Apple Distribution profile, not a development or enterprise profile.")
    devices = profile.get("ProvisionedDevices", [])
    if (method == "ad-hoc") != bool(devices):
        raise ValueError("Profile type does not match the selected export method.")
    uuid = profile.get("UUID", "")
    if not re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", uuid):
        raise ValueError("Invalid provisioning profile UUID.")
    certificates = profile.get("DeveloperCertificates", [])
    if not certificates or not all(isinstance(cert, bytes) for cert in certificates):
        raise ValueError("Provisioning profile has no signing certificates.")
    return {"uuid": uuid, "team": team, "bundle_id": bundle_id, "method": method,
            "certificate_hashes": [hashlib.sha1(cert).hexdigest().upper() for cert in certificates]}


def security(*args):
    result = subprocess.run(["/usr/bin/security", *map(str, args)], capture_output=True)
    if result.returncode:
        # Do not print command arguments or decoded signing material.
        raise RuntimeError(f"macOS security failed during {args[0]}; check signing credentials.")
    return result.stdout


def state_path():
    return Path(os.environ["RUNNER_TEMP"]) / "k-mobile-signing-state.json"


def save(state):
    path = state_path()
    path.write_text(json.dumps(state))
    path.chmod(0o600)


def install():
    required = ("IOS_CERTIFICATE_P12_BASE64", "IOS_CERTIFICATE_PASSWORD", "IOS_PROFILE_BASE64",
                "IOS_TEAM_ID", "IOS_BUNDLE_ID", "IOS_EXPORT_METHOD", "GITHUB_ENV")
    for name in required:
        if not os.environ.get(name):
            raise ValueError(f"Configure {name} before requesting an IPA.")
    if state_path().exists():
        raise ValueError("Signing state already exists; clean it before retrying.")
    directory = Path(tempfile.mkdtemp(prefix="k-mobile-signing-", dir=os.environ["RUNNER_TEMP"]))
    keychain = directory / "build.keychain-db"
    state = {"directory": str(directory), "keychain": str(keychain), "profiles": [], "search_list": None}
    save(state)
    p12, mobileprovision = directory / "certificate.p12", directory / "profile.mobileprovision"
    for name, destination in (("IOS_CERTIFICATE_P12_BASE64", p12), ("IOS_PROFILE_BASE64", mobileprovision)):
        try:
            decoded = base64.b64decode("".join(os.environ[name].split()), validate=True)
        except ValueError:
            raise ValueError(f"{name} must contain valid Base64.") from None
        destination.write_bytes(decoded)
        destination.chmod(0o600)
    profile = plistlib.loads(security("cms", "-D", "-i", mobileprovision))
    metadata = validate_profile(profile, os.environ["IOS_TEAM_ID"], os.environ["IOS_BUNDLE_ID"], os.environ["IOS_EXPORT_METHOD"])
    state["search_list"] = shlex.split(security("list-keychains", "-d", "user").decode())
    save(state)
    password = secrets.token_urlsafe(32)
    security("create-keychain", "-p", password, keychain)
    security("set-keychain-settings", "-lut", "3600", keychain)
    security("unlock-keychain", "-p", password, keychain)
    security("import", p12, "-P", os.environ["IOS_CERTIFICATE_PASSWORD"], "-f", "pkcs12", "-k", keychain,
             "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    security("list-keychains", "-d", "user", "-s", keychain, *state["search_list"])
    identities = security("find-identity", "-v", "-p", "codesigning", keychain).decode()
    matches = [digest for digest in metadata.pop("certificate_hashes") if re.search(r"\b" + digest + r"\b", identities, re.I)]
    if not matches:
        raise ValueError("The P12 private key/certificate does not match a valid signing identity in the profile.")
    metadata["identity"] = matches[0]
    # Xcode 16+ uses Developer/Xcode; retain the legacy location for tool compatibility.
    for folder in ("Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"):
        target = Path.home() / folder / f"{metadata['uuid']}.mobileprovision"
        if target.exists():
            raise ValueError("A matching profile is already installed; use a fresh hosted runner.")
        target.parent.mkdir(parents=True, exist_ok=True)
        state["profiles"].append(str(target))
        save(state)
        shutil.copyfile(mobileprovision, target)
        target.chmod(0o600)
    metadata_path = directory / "metadata.json"
    metadata_path.write_text(json.dumps(metadata))
    metadata_path.chmod(0o600)
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        stream.write(f"IOS_SIGNING_METADATA={metadata_path}\n")
    print("Signing identity and provisioning profile validated and installed.")


def cleanup():
    path = state_path()
    if not path.exists():
        return
    state = json.loads(path.read_text())
    errors = []
    if state["search_list"] is not None:
        try:
            security("list-keychains", "-d", "user", "-s", *state["search_list"])
        except RuntimeError as error:
            errors.append(str(error))
    if Path(state["keychain"]).exists():
        try:
            security("delete-keychain", state["keychain"])
        except RuntimeError as error:
            errors.append(str(error))
    for profile in state["profiles"]:
        Path(profile).unlink(missing_ok=True)
    shutil.rmtree(state["directory"], ignore_errors=False)
    path.unlink()
    if errors:
        raise RuntimeError("; ".join(errors))
    print("Temporary signing files and keychain removed.")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["install"]:
            install()
        elif sys.argv[1:] == ["cleanup"]:
            cleanup()
        else:
            raise ValueError("Usage: signing.py install|cleanup")
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
