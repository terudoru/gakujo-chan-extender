import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "write_google_oauth_defines.py"
VALUES = {
    "GOOGLE_OAUTH_DESKTOP_CLIENT_ID": "123-desktop.apps.googleusercontent.com",
    "GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET": "desktop-secret",
    "GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID": "456-android.apps.googleusercontent.com",
    "GOOGLE_OAUTH_IOS_CLIENT_ID": "789-ios.apps.googleusercontent.com",
}


class WriteGoogleOAuthDefinesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items() if key not in VALUES}
        self.env.update(VALUES)

    def run_script(self, platform, *args):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--platform", platform,
             "--out", str(self.root / "nested" / "defines.json"), *args],
            env=self.env, capture_output=True, text=True,
        )
        for value in (*VALUES.values(), "bad-client-id"):
            self.assertNotIn(value, result.stdout + result.stderr)
        return result

    def test_missing_value_fails(self):
        self.env["GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET"] = "  "
        result = self.run_script("desktop")
        self.assertEqual(result.returncode, 1)
        self.assertIn("::error::GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET is not set", result.stdout)
        self.assertFalse((self.root / "nested" / "defines.json").exists())

    def test_malformed_id_fails(self):
        self.env["GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID"] = "bad-client-id"
        result = self.run_script("android")
        self.assertEqual(result.returncode, 1)
        self.assertIn("::error::GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID is not a Google OAuth client ID", result.stdout)

    def test_platform_values_are_trimmed_and_isolated(self):
        for platform, keys in (
            ("desktop", list(VALUES)[:2]),
            ("android", ["GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID"]),
            ("ios", ["GOOGLE_OAUTH_IOS_CLIENT_ID"]),
        ):
            with self.subTest(platform=platform):
                self.env.update({key: f"  {value}  " for key, value in VALUES.items()})
                self.assertEqual(self.run_script(platform).returncode, 0)
                output = json.loads((self.root / "nested" / "defines.json").read_text(encoding="utf-8"))
                self.assertEqual(output, {key: VALUES[key] for key in keys})

    def test_ios_xcconfig(self):
        path = self.root / "ios" / "GoogleOAuth.xcconfig"
        self.assertEqual(self.run_script("ios", "--ios-xcconfig", str(path)).returncode, 0)
        self.assertEqual(path.read_text(encoding="utf-8"),
                         "GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.789-ios\n")

    def test_xcconfig_rejected_for_other_platforms(self):
        result = self.run_script("desktop", "--ios-xcconfig", str(self.root / "config"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--ios-xcconfig is only valid for ios", result.stderr)


if __name__ == "__main__":
    unittest.main()
