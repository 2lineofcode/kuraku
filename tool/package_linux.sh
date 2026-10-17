#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

version="${1:-$(awk '/^version:/ {print $2; exit}' pubspec.yaml)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+(\.[0-9]+)?)?$ ]] || { echo 'Invalid version' >&2; exit 1; }
bundle=build/linux/x64/release/bundle
[ -x "$bundle/kuraku" ] || { echo 'Build the Linux release first' >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo 'Linux x64 only' >&2; exit 1; }
package="$(mktemp -d)"
trap 'rm -rf "$package"' EXIT
mkdir -p "$package/DEBIAN" "$package/opt/kuraku" "$package/usr/bin" \
  "$package/usr/share/applications" "$package/usr/share/icons/hicolor/256x256/apps" dist
cp -a "$bundle/." "$package/opt/kuraku/"
# Flutter's asset copier does not preserve executable permissions.
chmod 755 "$package/opt/kuraku/data/flutter_assets/assets/linux-x64/kuraku"
rm -f "$package/opt/kuraku/data/flutter_assets/assets/kuraku"
ln -s /opt/kuraku/kuraku "$package/usr/bin/kuraku"
cp assets/app_icon.png "$package/usr/share/icons/hicolor/256x256/apps/app.kuraku.kuraku.png"
cat > "$package/DEBIAN/control" <<EOF
Package: kuraku
Version: $version
Architecture: amd64
Maintainer: KuraKu contributors
Depends: libgtk-3-0 | libgtk-3-0t64, libmpv2 | libmpv1, libkeybinder-3.0-0, libjson-glib-1.0-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-good, libwebkit2gtk-4.1-0, python3, python3-venv, ffmpeg, curl, libopencore-amrnb0, libvo-amrwbenc0, libvpx7, libx265-199, libicu70, xdg-utils
Recommends: yt-dlp, chromium | chromium-browser | google-chrome-stable
Description: Personal video library manager and desktop player
EOF
cat > "$package/usr/share/applications/app.kuraku.kuraku.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=KuraKu
Exec=/opt/kuraku/kuraku
Icon=app.kuraku.kuraku
Terminal=false
Categories=AudioVideo;Video;
StartupWMClass=app.kuraku.kuraku
EOF
dpkg-deb --root-owner-group --build "$package" "dist/KuraKu-${version}-linux-x64.deb"
(cd dist && sha256sum "KuraKu-${version}-linux-x64.deb" > "KuraKu-${version}-linux-x64.deb.sha256")
