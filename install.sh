#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/bin}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Linking scripts into $PREFIX"

mkdir -p "$PREFIX"

# Link top-level runnable scripts explicitly
find "$HERE/scripts" -maxdepth 2 -type f -name "*.sh" | while read -r f; do
  b="$(basename "$f")"
  # strip .sh for nicer UX when appropriate
  case "$b" in
    orientation-audit-volumio.sh) linkname="orientation-audit-volumio.sh" ;;
    *) linkname="$b" ;;
  esac
  ln -sf "$f" "$PREFIX/$linkname"
  chmod +x "$f"
  echo "  -> $linkname"
done

echo "==> Optional: install helpers: sudo apt-get install shellcheck shfmt bats"
echo "Done."
