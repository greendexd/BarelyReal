#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$("$PROJECT_DIR/mac/scripts/install_app.sh")"

echo
echo "BarelyReal installed:"
echo "$APP_PATH"
echo
echo "Opening app..."
open "$APP_PATH"
