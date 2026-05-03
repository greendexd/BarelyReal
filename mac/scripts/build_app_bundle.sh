#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$MAC_DIR/dist/BarelyReal.app"
CONFIGURATION="${CONFIGURATION:-release}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "CONFIGURATION must be 'debug' or 'release'." >&2
  exit 2
fi

cd "$MAC_DIR"
swift build -c "$CONFIGURATION" --product BarelyReal >&2
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BARELYREAL_BIN="$BIN_DIR/BarelyReal"

if [[ ! -x "$BARELYREAL_BIN" ]]; then
  echo "Built executable not found at $BARELYREAL_BIN" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

install -m 755 "$BARELYREAL_BIN" "$APP_DIR/Contents/MacOS/BarelyReal"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>BarelyReal</string>
  <key>CFBundleDisplayName</key>
  <string>BarelyReal</string>
  <key>CFBundleIdentifier</key>
  <string>local.barelyreal.mac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>BarelyReal</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSInputMonitoringUsageDescription</key>
  <string>BarelyReal needs Input Monitoring to capture keyboard and mouse events for sharing them with your paired Windows machine.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>BarelyReal connects to your paired Windows machine on your local network.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_barelyreal._tcp</string>
  </array>
</dict>
</plist>
PLIST

cat > "$APP_DIR/Contents/Entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.input-monitoring</key>
  <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - --entitlements "$APP_DIR/Contents/Entitlements.plist" "$APP_DIR" >/dev/null

echo "$APP_DIR"
