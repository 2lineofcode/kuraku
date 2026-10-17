#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

case "$(uname -s)" in
  Darwin) target=macos ;;
  Linux) target=linux ;;
  *) echo 'Unsupported OS' >&2; exit 1 ;;
esac
exec flutter run -d "$target" "$@"
