#!/usr/bin/env python3
"""Generate and verify a signed Sparkle feed for an immutable GitHub release."""
import argparse
import base64
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
def sparkle_tools():
    override = os.environ.get("SPARKLE_TOOLS_DIR")
    if override:
        candidates = [Path(override)]
    else:
        artifacts = ROOT / "build/SourcePackages/artifacts"
        candidates = [path.parent for path in artifacts.rglob("generate_appcast")] if artifacts.exists() else []
    candidates = [path for path in candidates if (path / "generate_appcast").is_file() and (path / "sign_update").is_file()]
    if len(candidates) != 1:
        raise ValueError("Sparkle tools not found unambiguously; resolve the Xcode package or set SPARKLE_TOOLS_DIR")
    return candidates[0]

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Release tag, e.g. v0.1.2")
    args = parser.parse_args()
    if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", args.tag):
        parser.error("Tag must use stable vX.Y.Z format")
    repository = os.environ.get("GITHUB_REPOSITORY", "csyasin/lunera")
    if repository != "csyasin/lunera":
        parser.error("Configure the application's feed URL before publishing from another repository")
    archive = ROOT / "dist/Lunera.dmg"
    info = plistlib.loads((ROOT / "dist/Lunera.app/Contents/Info.plist").read_bytes())
    enabled = str(info.get("LuneraUpdatesEnabled", "")).lower() in {"true", "yes", "1"}
    if not enabled or info["CFBundleShortVersionString"] != args.tag[1:]:
        raise ValueError("Build an update-enabled application matching the release tag first")
    if len(base64.b64decode(info["SUPublicEDKey"], validate=True)) != 32:
        raise ValueError("Configure LUNERA_SPARKLE_PUBLIC_KEY before building")
    tools = sparkle_tools()
    subprocess.run(["shasum", "-a", "256", "-c", "Lunera.dmg.sha256"], cwd=ROOT / "dist", check=True)
    secret = os.environ.get("SPARKLE_PRIVATE_KEY")
    child_env = {key: value for key, value in os.environ.items() if key != "SPARKLE_PRIVATE_KEY"}
    # Keep signing material on stdin; never put it in process arguments or logs.
    signing_args = ["--ed-key-file", "-"] if secret else ["--account", "dev.yasin.lunera"]
    download_prefix = f"https://github.com/{repository}/releases/download/{args.tag}/"
    with tempfile.TemporaryDirectory(prefix=".appcast-", dir=ROOT / "dist") as folder:
        staging = Path(folder)
        shutil.copyfile(archive, staging / archive.name)
        (staging / "Lunera.html").write_text(
            f"<p>Lunera {args.tag[1:]} 已发布。</p><p>安装完成后应用会重新启动，个人偏好保持不变。</p>"
            f'<p><a href="https://github.com/{repository}/releases/tag/{args.tag}">查看完整更新说明</a></p>', encoding="utf-8")
        command = [str(tools / "generate_appcast"), *signing_args, "--download-url-prefix", download_prefix,
                   "--maximum-deltas", "0", "--embed-release-notes", str(staging)]
        result = subprocess.run(command, input=secret, env=child_env, text=True, capture_output=True)
        if result.returncode:
            details = result.stderr + result.stdout
            if secret:
                details = details.replace(secret, "[redacted]")
            raise ValueError(f"Sparkle appcast generation failed: {details.strip()}")
        feed = staging / "appcast.xml"
        item = ET.parse(feed).find("./channel/item")
        if item is None:
            raise ValueError("Sparkle generated an empty update feed")
        enclosure = item.find("enclosure")
        if (enclosure is None or enclosure.get("url") != download_prefix + archive.name
                or enclosure.get("length") != str(archive.stat().st_size)
                or item.findtext(f"{{{SPARKLE}}}version") != info["CFBundleVersion"]
                or item.findtext(f"{{{SPARKLE}}}shortVersionString") != args.tag[1:]):
            raise ValueError("Generated feed does not match the release artifact")
        signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError("Generated update archive is not signed")
        subprocess.run(["xcrun", "swift", "-module-cache-path", str(Path(tempfile.gettempdir()) / "lunera-update-module-cache"),
                        str(ROOT / "Scripts/verify-update.swift"), info["SUPublicEDKey"], str(archive), signature], check=True, env=child_env)
        # SURequireSignedFeed makes generate_appcast sign the feed too. Verify it
        # with Sparkle before publishing; do not edit the XML after this point.
        check = subprocess.run([str(tools / "sign_update"), *signing_args, "--verify", str(feed)],
                               input=secret, env=child_env, text=True, capture_output=True)
        if check.returncode:
            raise ValueError("Sparkle could not verify the signed update feed")
        feed.replace(ROOT / "dist/appcast.xml")
    print(f"Signed update feed generated for {args.tag}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        raise SystemExit(f"Update feed failed: {error}")
