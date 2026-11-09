import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "Scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = load("release", "release.py")
verify = load("verify_release", "verify-release.py")
appcast = load("generate_appcast", "generate-appcast.py")


class VersionTests(unittest.TestCase):
    def test_version_choices_and_validation(self):
        self.assertEqual(release.next_version("1.2.3", "patch"), "1.2.4")
        self.assertEqual(release.next_version("1.2.3", "minor"), "1.3.0")
        self.assertEqual(release.next_version("1.2.3", "major"), "2.0.0")
        self.assertEqual(release.next_version("1.2.3", "current"), "1.2.3")
        for invalid in ("1.0", "01.0.0", "1.0.0-rc1", "v1.0.0"):
            with self.assertRaises(release.ReleaseError):
                release.parse_version(invalid)


class ReleaseVerificationTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.app = Path(self.folder.name) / "Lunera.app"
        (self.app / "Contents").mkdir(parents=True)
        self.public = base64.b64encode(bytes(32)).decode()
        self.info = {
            "CFBundleIdentifier": "com.yasin.lunera",
            "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "9.1",
            "SUFeedURL": verify.FEED, "SUPublicEDKey": self.public,
            "LuneraUpdatesEnabled": "YES", "SURequireSignedFeed": True,
            "SUVerifyUpdateBeforeExtraction": True, "SUEnableInstallerLauncherService": True,
        }
        self.entitlements = {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.network.client": True,
            "com.apple.security.cs.disable-library-validation": True,
            "com.apple.security.temporary-exception.mach-lookup.global-name": [
                "com.yasin.lunera-spks", "com.yasin.lunera-spki"],
        }

    def run_check(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))
        result = type("Result", (), {"stdout": plistlib.dumps(self.entitlements)})()
        with patch.object(verify, "APP", self.app), patch.object(verify.subprocess, "run", return_value=result), \
             patch.dict(os.environ, {"APP_VERSION": "1.2.3", "APP_BUILD_NUMBER": "9.1", "SPARKLE_PUBLIC_KEY": self.public}):
            verify.main()

    def test_valid_configuration(self):
        self.run_check()

    def test_update_disabled_fails_closed(self):
        self.info["LuneraUpdatesEnabled"] = "NO"
        with self.assertRaises(ValueError): self.run_check()

    def test_wrong_feed_or_key_fails_closed(self):
        for key in ("SUFeedURL", "SUPublicEDKey"):
            with self.subTest(key=key):
                old = self.info[key]
                self.info[key] = "unexpected"
                with self.assertRaises(ValueError): self.run_check()
                self.info[key] = old

    def test_missing_required_security_feature_fails_closed(self):
        for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableInstallerLauncherService"):
            with self.subTest(key=key):
                self.info[key] = False
                with self.assertRaises(ValueError): self.run_check()
                self.info[key] = True
        self.entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = []
        with self.assertRaises(ValueError): self.run_check()

    def test_get_task_allow_fails_closed(self):
        self.entitlements["com.apple.security.get-task-allow"] = True
        with self.assertRaises(ValueError): self.run_check()


class SparkleToolDiscoveryTests(unittest.TestCase):
    def test_override_requires_both_tools(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"SPARKLE_TOOLS_DIR": temp}):
            with self.assertRaises(ValueError): appcast.sparkle_tools()
            (Path(temp) / "generate_appcast").touch()
            (Path(temp) / "sign_update").touch()
            self.assertEqual(appcast.sparkle_tools(), Path(temp))


if __name__ == "__main__":
    unittest.main()
