#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MAC_DIR/.." && pwd)"
ARTIFACT_DIR="$MAC_DIR/artifacts"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT_PATH="$ARTIFACT_DIR/diagnostics-mac-$STAMP.txt"
APP_PATH="${APP_PATH:-/Applications/BarelyReal.app}"

mkdir -p "$ARTIFACT_DIR"

{
  echo "BarelyReal macOS diagnostics"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "== Repository =="
  echo "Repo: $REPO_ROOT"
  git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true
  git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true
  git -C "$REPO_ROOT" status --short 2>/dev/null || true
  echo
  echo "== System =="
  sw_vers
  uname -a
  echo
  echo "== App Bundle =="
  echo "APP_PATH: $APP_PATH"
  if [[ -d "$APP_PATH" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Print :NSInputMonitoringUsageDescription' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
    codesign -dvvv "$APP_PATH" 2>&1 || true
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 || true
  else
    echo "App bundle not found."
  fi
  echo
  echo "== Processes =="
  pgrep -afil BarelyReal || true
  echo
  echo "== Listening sockets =="
  lsof -nP -iTCP:24800 -sTCP:LISTEN 2>/dev/null || true
  lsof -nP -iTCP:24802 -sTCP:LISTEN 2>/dev/null || true
  lsof -nP -iUDP:24801 2>/dev/null || true
  echo
  echo "== Network =="
  ifconfig | sed -n '/^[a-zA-Z0-9]/,/^$/p' | grep -E '^[a-zA-Z0-9]|inet ' || true
  echo
  echo "== Notes =="
  echo "This diagnostic file intentionally does not include clipboard payloads or keystrokes."
} | tee "$OUT_PATH"

echo
echo "Diagnostics written to $OUT_PATH"
