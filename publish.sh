#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="JavIt"
PUBSPEC="pubspec.yaml"
ENV_FILE=".env"
TARGET="${1:-auto}"

log() {
  echo "==> $1"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

require_command dart
require_command flutter
require_command git

[ -f "$PUBSPEC" ] || fail "$PUBSPEC not found"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE not found"

case "$TARGET" in
  auto|macos|windows) ;;
  *) fail "Usage: ./publish.sh [auto|macos|windows]" ;;
esac

current_version="$(awk '/^version:/ {print $2; exit}' "$PUBSPEC")"
[ -n "$current_version" ] || fail "Cannot read version from $PUBSPEC"

base_version="${current_version%%+*}"
app_version="${base_version} ($(date '+%Y-%m-%d'))"
build_number="$(date '+%Y%m%d').$(git rev-list --count HEAD)"
new_version="${base_version}+${build_number}"

log "Update version: $current_version -> $new_version"
tmp_pubspec="$(mktemp)"
awk -v current="$current_version" -v newver="$new_version" '
  $1 == "version:" && $2 == current {
    print "version: " newver
    done = 1
    next
  }
  { print }
  END {
    if (done != 1) exit 1
  }
' "$PUBSPEC" > "$tmp_pubspec" || {
  rm -f "$tmp_pubspec"
  fail "Failed to update version in $PUBSPEC"
}
mv "$tmp_pubspec" "$PUBSPEC"

log "Update APP_VER: $app_version"
tmp_env="$(mktemp)"
awk -v appver="$app_version" '
  /^APP_VER=/ {
    print "APP_VER='\''" appver "'\''"
    done = 1
    next
  }
  { print }
  END {
    if (done != 1) exit 1
  }
' "$ENV_FILE" > "$tmp_env" || {
  rm -f "$tmp_env"
  fail "Failed to update APP_VER in $ENV_FILE"
}
mv "$tmp_env" "$ENV_FILE"

log "Generate secure env"
dart run enven

log "Refresh dependencies"
flutter pub get

resolved_target="$TARGET"
if [ "$resolved_target" = "auto" ]; then
  case "$(uname -s)" in
    Darwin) resolved_target="macos" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) resolved_target="windows" ;;
    *) fail "Unsupported OS: $(uname -s). Run with explicit target if needed." ;;
  esac
fi

case "$resolved_target" in
  macos)
    log "Build $APP_NAME for macOS"
    flutter build macos --release --no-tree-shake-icons
    log "Output: build/macos/Build/Products/Release"
    ;;
  windows)
    log "Build $APP_NAME for Windows"
    flutter build windows --release --no-tree-shake-icons
    log "Output: build/windows/x64/runner/Release"
    ;;
esac

log "Clean compile cache"
find . -type d -name '__pycache__' -prune -exec rm -rf {} +

log "Done"
