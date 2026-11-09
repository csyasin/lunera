#!/usr/bin/env python3
"""Prepare and push a versioned release without staging application changes."""

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path

VERSION_PATTERN = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
PROJECT_DIR = Path(__file__).resolve().parent.parent


class ReleaseError(Exception):
    pass


def git(*arguments, check=True):
    result = subprocess.run(
        ["git", *arguments], cwd=PROJECT_DIR, text=True, capture_output=True
    )
    if check and result.returncode:
        raise ReleaseError(result.stderr.strip() or result.stdout.strip() or "Git command failed")
    return result


def parse_version(value):
    if not isinstance(value, str) or not VERSION_PATTERN.fullmatch(value):
        raise ReleaseError("Version must use X.Y.Z format without leading zeros.")
    return tuple(map(int, value.split(".")))


def next_version(current, selection):
    major, minor, patch = parse_version(current)
    if selection == "current":
        return current
    if selection == "patch":
        return f"{major}.{minor}.{patch + 1}"
    if selection == "minor":
        return f"{major}.{minor + 1}.0"
    if selection == "major":
        return f"{major + 1}.0.0"
    parse_version(selection)
    return selection


def release(selection, dry_run):
    info_path = PROJECT_DIR / "project.yml"
    original_info = info_path.read_bytes()
    version_matches = re.findall(rb"^\s*MARKETING_VERSION:\s*['\"]?([0-9]+\.[0-9]+\.[0-9]+)['\"]?\s*$", original_info, flags=re.MULTILINE)
    if len(version_matches) != 1:
        raise ReleaseError("Could not locate exactly one MARKETING_VERSION in project.yml.")
    current = version_matches[0].decode("ascii")
    version = next_version(current, selection)
    if parse_version(version) < parse_version(current):
        raise ReleaseError(f"Version {version} is older than the configured version {current}.")
    tag = f"v{version}"

    branch = git("symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip()
    git("remote", "get-url", "origin")
    dirty = bool(git("status", "--porcelain").stdout)
    if dirty and not dry_run:
        raise ReleaseError("Commit your application changes first; the working tree must be clean.")

    if not dry_run:
        git("fetch", "--tags", "origin")
        remote_branch = f"refs/remotes/origin/{branch}"
        if git("rev-parse", "--verify", "--quiet", remote_branch, check=False).returncode == 0:
            if git("merge-base", "--is-ancestor", remote_branch, "HEAD", check=False).returncode:
                raise ReleaseError(f"Your branch is behind or diverged from origin/{branch}. Run git pull --ff-only origin {branch} first.")
        if git("ls-remote", "--tags", "origin", f"refs/tags/{tag}").stdout.strip():
            raise ReleaseError(f"{tag} already exists on origin. Choose a new version.")

    local_tag = git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}", check=False)
    resuming = local_tag.returncode == 0
    if resuming:
        tagged_commit = git("rev-parse", f"refs/tags/{tag}^{{commit}}").stdout.strip()
        if tagged_commit != git("rev-parse", "HEAD").stdout.strip() or version != current:
            raise ReleaseError(f"Local tag {tag} points to another release; it will not be overwritten.")

    versions = []
    for existing in git("tag", "--list", "v*").stdout.splitlines():
        if VERSION_PATTERN.fullmatch(existing[1:]):
            versions.append(parse_version(existing[1:]))
    if versions:
        latest = max(versions)
        target = parse_version(version)
        if target < latest or (target == latest and not resuming):
            raise ReleaseError("The release version must be newer than the existing version tags.")

    print(f"Release: {current} -> {version} ({tag})", flush=True)
    if dry_run:
        print("Preview uses local tags; the real release also checks origin.")
        if dirty:
            print("Commit application changes before running without --dry-run.")
        print(f"Will update project.yml if needed, create {tag}, and atomically push {branch} and the tag.")
        return

    if version != current:
        updated, count = re.subn(
            rb"(^\s*MARKETING_VERSION:\s*[\"']?)[0-9]+\.[0-9]+\.[0-9]+([\"']?\s*$)",
            lambda match: match[1] + version.encode("ascii") + match[2],
            original_info,
            flags=re.MULTILINE,
        )
        if count != 1:
            raise ReleaseError("Could not locate exactly one MARKETING_VERSION entry in project.yml.")
        info_path.write_bytes(updated)
        try:
            git("add", "--", "project.yml")
            git("commit", "-m", f"chore: release {tag}")
        except ReleaseError:
            git("restore", "--staged", "--source=HEAD", "--", "project.yml", check=False)
            info_path.write_bytes(original_info)
            raise

    if not resuming:
        git("tag", "-a", tag, "-m", f"Release {tag}")
    try:
        git("push", "--atomic", "--no-follow-tags", "--set-upstream", "origin", f"HEAD:refs/heads/{branch}", f"refs/tags/{tag}")
    except ReleaseError as error:
        raise ReleaseError(
            f"{error}\nThe release commit/tag remain local. After fixing the push failure, retry: ./Scripts/release.py current"
        ) from error
    print(f"Pushed {tag}. Check GitHub Actions -> Release for the build and download.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="current (first release), patch, minor, major, or an explicit X.Y.Z")
    parser.add_argument("--dry-run", action="store_true", help="preview using local data; no changes or network requests")
    arguments = parser.parse_args()
    try:
        release(arguments.version, arguments.dry_run)
    except (ReleaseError, OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
