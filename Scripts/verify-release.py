#!/usr/bin/env python3
"""Fail closed if the release app and its signed updater configuration disagree."""
import base64
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "dist/Lunera.app"
FEED = "https://github.com/csyasin/lunera/releases/latest/download/appcast.xml"


def enabled(value):
    return value is True or (isinstance(value, str) and value.upper() in {"YES", "TRUE", "1"})


def main():
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    version, build = os.environ["APP_VERSION"], os.environ["APP_BUILD_NUMBER"]
    public = os.environ["SPARKLE_PUBLIC_KEY"]
    if info.get("CFBundleIdentifier") != "com.yasin.lunera":
        raise ValueError("Unexpected application bundle identifier")
    if info.get("CFBundleShortVersionString") != version or info.get("CFBundleVersion") != build:
        raise ValueError("Application version or build number differs from release")
    if info.get("SUFeedURL") != FEED or info.get("SUPublicEDKey") != public:
        raise ValueError("Sparkle feed or public key does not match the release")
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError("Invalid Sparkle public key")
    for key in ("LuneraUpdatesEnabled", "SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableInstallerLauncherService"):
        if not enabled(info.get(key)):
            raise ValueError(f"Missing required updater setting: {key}")
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(APP)], check=True, capture_output=True)
    entitlements = plistlib.loads(result.stdout)
    if enabled(entitlements.get("com.apple.security.get-task-allow")):
        raise ValueError("Release applications must not allow debugger attachment")
    for key in ("com.apple.security.app-sandbox", "com.apple.security.network.client",
                "com.apple.security.cs.disable-library-validation"):
        if not enabled(entitlements.get(key)):
            raise ValueError(f"Missing sandbox entitlement: {key}")
    allowed = entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name", [])
    for name in ("com.yasin.lunera-spks", "com.yasin.lunera-spki"):
        if name not in allowed:
            raise ValueError(f"Missing Sparkle sandbox service entitlement: {name}")
    print("Release version, updater feed, public key and sandbox entitlements verified.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Release verification failed: {error}")
