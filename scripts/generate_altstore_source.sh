#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 path/to/MoreBetterGakujo-vX.Y.Z.ipa" >&2
  exit 64
fi

ipa_path="$1"

if [ ! -f "$ipa_path" ]; then
  echo "IPA not found: $ipa_path" >&2
  exit 66
fi

pubspec_version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
version="${pubspec_version%%+*}"
build_version="${pubspec_version##*+}"

if [ "$version" = "$pubspec_version" ]; then
  echo "pubspec.yaml version must include a build number, for example 0.66.0+66" >&2
  exit 65
fi

if size="$(stat -f '%z' "$ipa_path" 2>/dev/null)"; then
  :
else
  size="$(stat -c '%s' "$ipa_path")"
fi

release_tag="${RELEASE_TAG:-v$version}"
release_notes="${RELEASE_NOTES:-iOS/iPadOS self-signed build.}"
release_date="${RELEASE_DATE:-$(date +%Y-%m-%d)}"
download_url="${DOWNLOAD_URL:-https://github.com/terudoru/gakujo-chan-extender/releases/download/$release_tag/MoreBetterGakujo-$release_tag.ipa}"
output_path="${OUTPUT_PATH:-distribution/altstore-source.json}"

mkdir -p "$(dirname "$output_path")"

jq_escape() {
  printf '%s' "$1" | jq -Rs .
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to generate JSON safely." >&2
  exit 69
fi

cat > "$output_path" <<JSON
{
  "name": "More Better Gakujo",
  "subtitle": "Unofficial iOS/iPadOS builds for technical users.",
  "description": "More Better Gakujo is an unofficial Flutter app for opening Niigata University's Gakujo system with 2FA autofill and easier material downloads. This source is for self-signed SideStore/AltStore-style installation only.",
  "iconURL": "https://raw.githubusercontent.com/terudoru/gakujo-chan-extender/main/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png",
  "website": "https://github.com/terudoru/gakujo-chan-extender",
  "tintColor": "#2458A6",
  "featuredApps": [
    "net.yoshida.morebettergakujo"
  ],
  "apps": [
    {
      "name": "More Better Gakujo",
      "bundleIdentifier": "net.yoshida.morebettergakujo",
      "developerName": "Teruhiko Yoshida",
      "subtitle": "Unofficial Gakujo helper app.",
      "localizedDescription": "More Better Gakujo opens Niigata University's Gakujo system in an app WebView and helps with 2FA autofill and material downloads. This iOS/iPadOS build is distributed as an IPA for users who understand self-signing with SideStore or Sideloadly.",
      "iconURL": "https://raw.githubusercontent.com/terudoru/gakujo-chan-extender/main/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png",
      "tintColor": "#2458A6",
      "category": "utilities",
      "versions": [
        {
          "version": $(jq_escape "$version"),
          "buildVersion": $(jq_escape "$build_version"),
          "marketingVersion": $(jq_escape "$version ($build_version)"),
          "date": $(jq_escape "$release_date"),
          "localizedDescription": $(jq_escape "$release_notes"),
          "downloadURL": $(jq_escape "$download_url"),
          "size": $size,
          "minOSVersion": "14.0"
        }
      ],
      "appPermissions": {
        "entitlements": [],
        "privacy": {}
      }
    }
  ],
  "news": []
}
JSON

echo "Wrote $output_path"
