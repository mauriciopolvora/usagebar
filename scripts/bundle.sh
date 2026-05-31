#!/bin/bash
# Build UsageBar in release mode and wrap it into a double-clickable .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="UsageBar"
BUNDLE_ID="com.local.usagebar"
SIGN_IDENTITY="${USAGEBAR_SIGN_IDENTITY:-}"

swift build -c release

BIN=".build/release/${APP_NAME}"
APP="${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed ${APP} with ${SIGN_IDENTITY}"
else
    codesign --force --deep --sign - "$APP"
    echo "Ad-hoc signed ${APP}. Set USAGEBAR_SIGN_IDENTITY to use a stable Keychain identity across rebuilds."
fi

echo "Built ${APP}. Run: open ${APP}"
