#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="kuraku"
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

resolved_target="$TARGET"
if [ "$resolved_target" = "auto" ]; then
  case "$(uname -s)" in
    Darwin) resolved_target="macos" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) resolved_target="windows" ;;
    *) fail "Unsupported OS: $(uname -s). Run with explicit target if needed." ;;
  esac
fi

current_version="$(awk '/^version:/ {print $2; exit}' "$PUBSPEC")"
[ -n "$current_version" ] || fail "Cannot read version from $PUBSPEC"

[[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+(\.[0-9]+)?)?$ ]] || fail "Invalid version: $current_version"
base_version="${current_version%%+*}"
build_date="$(date '+%Y%m%d')"
build_sequence="$(git rev-list --count HEAD)"
[[ "$build_sequence" =~ ^[0-9]+$ ]] || fail "Cannot read commit count"
build_sequence=$((10#$build_sequence))
if [[ "$current_version" =~ \+([0-9]{8})\.([0-9]+)$ ]]; then
  previous_date="${BASH_REMATCH[1]}"
  previous_sequence=$((10#${BASH_REMATCH[2]}))
  [[ "$build_date" < "$previous_date" ]] && fail "Build date is older than the current version"
  if [ "$build_date" = "$previous_date" ] && [ "$build_sequence" -le "$previous_sequence" ]; then
    build_sequence=$((previous_sequence + 1))
  fi
fi
build_number="${build_date}.${build_sequence}"
new_version="${base_version}+${build_number}"

log "Build version: $current_version -> $new_version"
tmp_pubspec="$(mktemp "${PUBSPEC}.XXXXXX")"
trap 'rm -f "$tmp_pubspec"' EXIT
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
log "Generate secure env"
dart run enven

log "Refresh dependencies"
flutter pub get

log "Build $APP_NAME for $resolved_target"
flutter build "$resolved_target" --release --no-tree-shake-icons --build-name="$base_version" --build-number="$build_number"

case "$resolved_target" in
  macos)
    log "Output: build/macos/Build/Products/Release"
    app_bundle="build/macos/Build/Products/Release/kuraku.app"
    installed_app="/Applications/kuraku.app"
    [ -d "$app_bundle" ] || fail "App bundle not found: $app_bundle"
    require_command ditto
    log "Install $APP_NAME: $installed_app"
    if [ -w /Applications ] && { [ ! -e "$installed_app" ] || [ -w "$installed_app" ]; }; then
      ditto "$app_bundle" "$installed_app"
    else
      require_command sudo
      sudo ditto "$app_bundle" "$installed_app"
    fi
    log "Installed: $installed_app"
    ;;
  windows)
    log "Output: build/windows/x64/runner/Release"
    ;;
esac

mv "$tmp_pubspec" "$PUBSPEC"
log "Saved version: $new_version"

log "Clean compile cache"
find . -type d -name '__pycache__' -prune -exec rm -rf {} +

log "Done"
