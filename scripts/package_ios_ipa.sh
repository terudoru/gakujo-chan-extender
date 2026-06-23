#!/usr/bin/env bash
set -euo pipefail

app_path="${APP_PATH:-build/ios/iphoneos/Runner.app}"
output_path="${OUTPUT_PATH:-dist/morebettergakujo-ios.ipa}"

case "$output_path" in
  /*) output_abs="$output_path" ;;
  *) output_abs="$(pwd)/$output_path" ;;
esac

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  flutter pub get
  flutter build ios --release --no-codesign
fi

if [ ! -d "$app_path" ]; then
  echo "iOS app bundle not found: $app_path" >&2
  echo "Run flutter build ios --release --no-codesign first, or set APP_PATH." >&2
  exit 66
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/Payload" "$(dirname "$output_path")"

if command -v ditto >/dev/null 2>&1; then
  ditto "$app_path" "$work_dir/Payload/Runner.app"
  COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent "$work_dir/Payload" "$output_abs"
else
  cp -R "$app_path" "$work_dir/Payload/Runner.app"
  (cd "$work_dir" && COPYFILE_DISABLE=1 zip -Xqry "$output_abs" Payload)
fi

echo "Wrote $output_path"
