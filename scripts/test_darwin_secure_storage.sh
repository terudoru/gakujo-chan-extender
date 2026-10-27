#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gakujo-darwin-tests.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT

xcrun swiftc \
  "$root/third_party/flutter_secure_storage_darwin/darwin/flutter_secure_storage_darwin/Sources/flutter_secure_storage_darwin/FlutterSecureStorage.swift" \
  "$root/test/darwin_secure_storage_test.swift" \
  -o "$work/darwin-secure-storage-tests"
"$work/darwin-secure-storage-tests"
