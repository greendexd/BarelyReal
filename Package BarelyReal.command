#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_PATH="$("$PROJECT_DIR/mac/scripts/package_app.sh")"

echo
echo "BarelyReal package created:"
echo "$ZIP_PATH"
echo
echo "SHA-256:"
cat "$ZIP_PATH.sha256"
echo
open -R "$ZIP_PATH"
