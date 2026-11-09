#!/usr/bin/env python3
"""Configure Lunera's independent Sparkle key for the release workflow.

Run with --create only on the first setup. The private key stays in Keychain;
--github explicitly uploads a temporary export to the repository secret.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "csyasin/lunera"
ACCOUNT = "dev.yasin.lunera"
PUBLIC_VARIABLE = "LUNERA_SPARKLE_PUBLIC_KEY"


def key_tool():
    override = os.environ.get("SPARKLE_TOOLS_DIR")
    if override:
        candidates = [Path(override) / "generate_keys"]
    else:
        artifacts = ROOT / "build/SourcePackages/artifacts"
        candidates = list(artifacts.rglob("generate_keys")) if artifacts.exists() else []
    candidates = [p for p in candidates if p.is_file()]
    if len(candidates) != 1:
        raise ValueError("Sparkle generate_keys not found uniquely. Resolve the Xcode package first, or set SPARKLE_TOOLS_DIR.")
    return candidates[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--create", action="store_true", help="Generate a key only if this is the initial Lunera setup")
    parser.add_argument("--github", action="store_true", help="Upload the public variable and private secret to csyasin/lunera")
    args = parser.parse_args()
    remote_public = None
    if args.github:
        subprocess.run(["gh", "auth", "status"], check=True)
        variables = json.loads(subprocess.check_output(
            ["gh", "variable", "list", "--repo", REPOSITORY, "--json", "name,value"], text=True))
        remote_public = next((v["value"] for v in variables if v["name"] == PUBLIC_VARIABLE), None)
    tool = str(key_tool())
    result = subprocess.run([tool, "--account", ACCOUNT, "-p"], capture_output=True, text=True)
    if result.returncode:
        if not args.create:
            raise ValueError("Lunera key not found or Keychain access denied. Restore the original key; only initial setup may use --create.")
        if remote_public:
            raise ValueError("A public key is already configured on GitHub. Restore its matching private key; do not create a replacement.")
        subprocess.run([tool, "--account", ACCOUNT], check=True)
        result = subprocess.run([tool, "--account", ACCOUNT, "-p"], capture_output=True, text=True, check=True)
    public = result.stdout.strip()
    if len(base64.b64decode(public, validate=True)) != 32:
        raise ValueError("Sparkle returned an invalid public key")
    if remote_public and remote_public != public:
        raise ValueError("Keychain key differs from the GitHub public key. Restore the original key; do not replace it.")
    print(f"Lunera update public key: {public}")
    if args.github:
        # Keep exported material private, pass via stdin, and always remove it.
        old_mask = os.umask(0o077)
        try:
            with tempfile.TemporaryDirectory(prefix="lunera-update-key-") as folder:
                key_file = Path(folder) / "private-key"
                subprocess.run([tool, "--account", ACCOUNT, "-x", str(key_file)], check=True)
                with key_file.open("rb") as secret:
                    subprocess.run(["gh", "secret", "set", "SPARKLE_PRIVATE_KEY", "--repo", REPOSITORY], stdin=secret, check=True)
                subprocess.run(["gh", "variable", "set", PUBLIC_VARIABLE, "--repo", REPOSITORY, "--body", public], check=True)
        finally:
            os.umask(old_mask)
        print("GitHub Actions key configured; temporary private-key export removed.")
    else:
        print("The private key remains in Keychain. Use --github to configure the release workflow.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Update setup failed: {error}")
