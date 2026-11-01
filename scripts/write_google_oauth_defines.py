import argparse
import json
import os
from pathlib import Path
import re
import sys


PLATFORM_KEYS = {
    "desktop": ("GOOGLE_OAUTH_DESKTOP_CLIENT_ID", "GOOGLE_OAUTH_DESKTOP_CLIENT_SECRET"),
    "android": ("GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID",),
    "ios": ("GOOGLE_OAUTH_IOS_CLIENT_ID",),
}
CLIENT_ID = re.compile(r"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True, choices=PLATFORM_KEYS)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--ios-xcconfig", type=Path)
    args = parser.parse_args()
    if args.ios_xcconfig and args.platform != "ios":
        parser.error("--ios-xcconfig is only valid for ios")

    values = {}
    for name in PLATFORM_KEYS[args.platform]:
        value = os.environ.get(name, "").strip()
        if not value:
            print(f"::error::{name} is not set")
            return 1
        if name.endswith("CLIENT_ID") and not CLIENT_ID.fullmatch(value):
            print(f"::error::{name} is not a Google OAuth client ID")
            return 1
        values[name] = value

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(values, indent=2) + "\n", encoding="utf-8")
    if args.ios_xcconfig:
        client_id = values["GOOGLE_OAUTH_IOS_CLIENT_ID"]
        reversed_id = client_id.removesuffix(".apps.googleusercontent.com")
        args.ios_xcconfig.parent.mkdir(parents=True, exist_ok=True)
        args.ios_xcconfig.write_text(
            f"GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.{reversed_id}\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
