#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$("$SCRIPT_DIR/build_app_bundle.sh")"
APP_NAME="BarelyReal.app"

if [[ -d "/Applications" && -w "/Applications" ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

TARGET_PATH="$INSTALL_DIR/$APP_NAME"

rm -rf "$TARGET_PATH"
ditto "$APP_PATH" "$TARGET_PATH"

if xattr -p com.apple.quarantine "$TARGET_PATH" >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET_PATH"
fi

codesign --verify --deep --strict "$TARGET_PATH"

echo "$TARGET_PATH"
