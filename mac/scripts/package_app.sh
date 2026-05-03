#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$("$SCRIPT_DIR/build_app_bundle.sh")"
ZIP_PATH="$MAC_DIR/dist/BarelyReal-mac.zip"
SHA_PATH="$ZIP_PATH.sha256"

rm -f "$ZIP_PATH" "$SHA_PATH"
cd "$(dirname "$APP_PATH")"
ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "$ZIP_PATH"
