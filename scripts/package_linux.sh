#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output_dir=""
if [[ -n "${OUTPUT_DIR:-}" ]]; then
  mkdir -p -- "$OUTPUT_DIR"
  output_dir="$(cd -- "$OUTPUT_DIR" && pwd)"
fi
cd -- "$repo_root"

pubspec_version="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
version="${pubspec_version%%+*}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version in pubspec.yaml: $pubspec_version" >&2
  exit 1
fi
release_tag="${RELEASE_TAG:-v${version}}"
if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release tag: $release_tag" >&2
  exit 1
fi
tag_version="${release_tag#v}"
tag_version="${tag_version%%-*}"
if [[ "$tag_version" != "$version" ]]; then
  echo "Release tag $release_tag does not match pubspec version $version" >&2
  exit 1
fi
deb_version="${release_tag#v}"
deb_version="${deb_version//-/\~}"

bundle="build/linux/x64/release/bundle"
if [ ! -d "$bundle" ] || [ ! -f "$bundle/morebettergakujo_flutter" ]; then
  echo "Linux release bundle or executable not found: $bundle" >&2
  echo "Run flutter build linux --release first." >&2
  exit 66
fi

if [[ -z "${output_dir:-}" ]]; then
  output_dir="dist"
  mkdir -p -- "$output_dir"
  output_dir="$(cd -- "$output_dir" && pwd)"
fi
name="MoreBetterGakujo-${release_tag}-linux-x64"
tar_path="$output_dir/$name.tar.gz"
deb_path="$output_dir/MoreBetterGakujo-${release_tag}-linux-amd64.deb"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/archive/$name" "$work_dir/deb/DEBIAN" \
  "$work_dir/deb/opt/morebettergakujo" "$work_dir/deb/usr/bin" \
  "$work_dir/deb/usr/share/applications" "$work_dir/deb/usr/share/dbus-1/services"
cp -a "$bundle/." "$work_dir/archive/$name/"
find "$work_dir/archive/$name" -type d -exec chmod 0755 {} +
find "$work_dir/archive/$name" -type f -exec chmod 0644 {} +
find "$work_dir/archive/$name" -type f -name '*.so*' -exec chmod 0755 {} +
chmod 0755 "$work_dir/archive/$name/morebettergakujo_flutter"
cp -a "$work_dir/archive/$name/." "$work_dir/deb/opt/morebettergakujo/"
ln -s /opt/morebettergakujo/morebettergakujo_flutter "$work_dir/deb/usr/bin/morebettergakujo"

mkdir -p "$work_dir/archive/$name/share"
cat > "$work_dir/archive/$name/share/net.yoshida.morebettergakujo.desktop.in" <<'EOF'
[Desktop Entry]
Type=Application
Name=More Better Gakujo
Exec=morebettergakujo_flutter
Icon=net.yoshida.morebettergakujo
Categories=Education;Network;
StartupWMClass=net.yoshida.morebettergakujo
DBusActivatable=true
X-GNOME-UsesNotifications=true
EOF
install -m 0755 scripts/install-desktop-entry.sh \
  "$work_dir/archive/$name/install-desktop-entry.sh"
sed 's/^Exec=.*/Exec=morebettergakujo/' \
  "$work_dir/archive/$name/share/net.yoshida.morebettergakujo.desktop.in" > \
  "$work_dir/deb/usr/share/applications/net.yoshida.morebettergakujo.desktop"
cat > "$work_dir/deb/usr/share/dbus-1/services/net.yoshida.morebettergakujo.service" <<'EOF'
[D-BUS Service]
Name=net.yoshida.morebettergakujo
Exec=/opt/morebettergakujo/morebettergakujo_flutter
EOF

for size in 16 32 64 128 256 512; do
  for root in "$work_dir/archive/$name" "$work_dir/deb/usr/share"; do
    icon_dir="$root/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    install -m 0644 "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${size}.png" \
      "$icon_dir/net.yoshida.morebettergakujo.png"
  done
done

tar -czf "$tar_path" -C "$work_dir/archive" "$name"

cat > "$work_dir/deb/DEBIAN/control" <<EOF
Package: morebettergakujo
Version: $deb_version
Architecture: amd64
Maintainer: Teruhiko Yoshida <gakujo@terudoru.com>
Section: education
Priority: optional
Depends: libgtk-3-0 | libgtk-3-0t64, libwebkit2gtk-4.1-0, libsecret-1-0, libglib2.0-0 | libglib2.0-0t64
Recommends: fonts-noto-cjk | fonts-ipafont-gothic | fonts-vlgothic
Homepage: https://github.com/terudoru/gakujo-chan-extender
Description: 学務情報システムを使うための非公式アプリ
 An unofficial desktop app for the Gakujo student information system.
EOF
chmod 0644 "$work_dir/deb/DEBIAN/control" \
  "$work_dir/deb/usr/share/applications/net.yoshida.morebettergakujo.desktop" \
  "$work_dir/deb/usr/share/dbus-1/services/net.yoshida.morebettergakujo.service"
find "$work_dir/deb" -type d -exec chmod 0755 {} +
dpkg-deb --root-owner-group --build "$work_dir/deb" "$deb_path"
echo "Wrote $tar_path"
echo "Wrote $deb_path"
