#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$("$PROJECT_DIR/mac/scripts/build_app_bundle.sh")"
open "$APP_PATH"
