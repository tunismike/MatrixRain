#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$HOME/.matrix_screensaver"
APP_BUNDLE="$RUNTIME_DIR/MatrixScreensaver.app"
PLIST_DEST="$HOME/Library/LaunchAgents/com.matrix.screensaver.plist"
LABEL="com.matrix.screensaver"
UID_NUM="$(id -u)"

echo "==> Compiling MatrixScreensaver (optimized arm64)..."
swiftc -O \
  -o "$PROJECT_DIR/MatrixScreensaver" \
  "$PROJECT_DIR/MatrixScreensaver.swift" \
  -framework Cocoa \
  -framework WebKit \
  -framework IOKit \
  -framework ScreenCaptureKit

mkdir -p "$RUNTIME_DIR" "$APP_BUNDLE/Contents/MacOS"

echo "==> Packaging $APP_BUNDLE..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MatrixScreensaver</string>
    <key>CFBundleIdentifier</key>
    <string>com.matrix.screensaver</string>
    <key>CFBundleName</key>
    <string>MatrixScreensaver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Atomic replace inside app bundle so a running binary is never overwritten in place
cp "$PROJECT_DIR/MatrixScreensaver" "$APP_BUNDLE/Contents/MacOS/MatrixScreensaver.new"
chmod +x "$APP_BUNDLE/Contents/MacOS/MatrixScreensaver.new"
mv -f "$APP_BUNDLE/Contents/MacOS/MatrixScreensaver.new" "$APP_BUNDLE/Contents/MacOS/MatrixScreensaver"

# Ad-hoc sign with stable bundle identifier for Screen Recording permission
codesign --force --sign - --identifier com.matrix.screensaver "$APP_BUNDLE" >/dev/null 2>&1 || true

# Keep top-level symlink so existing CLI invocations continue working
ln -sfn "$APP_BUNDLE/Contents/MacOS/MatrixScreensaver" "$RUNTIME_DIR/MatrixScreensaver"

if [ ! -f "$RUNTIME_DIR/config.ini" ]; then
  echo "==> Installing initial config.ini..."
  cp "$PROJECT_DIR/config.ini" "$RUNTIME_DIR/config.ini"
fi

if [ -d "$PROJECT_DIR/rezmason-overrides" ] && [ -d "$RUNTIME_DIR/rezmason" ]; then
  echo "==> Syncing rezmason-overrides to $RUNTIME_DIR/rezmason..."
  cp -R "$PROJECT_DIR/rezmason-overrides/." "$RUNTIME_DIR/rezmason/"
fi

echo "==> Installing LaunchAgent plist..."
plutil -lint "$PROJECT_DIR/com.matrix.screensaver.plist" >/dev/null
cp "$PROJECT_DIR/com.matrix.screensaver.plist" "$PLIST_DEST"

echo "==> Reloading LaunchAgent ($LABEL)..."
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
for _ in $(seq 1 25); do
  if ! launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
sleep 0.3
launchctl bootstrap "gui/$UID_NUM" "$PLIST_DEST"

sleep 1
echo "==> Verifying LaunchAgent..."
launchctl list | grep "$LABEL" || true
"$RUNTIME_DIR/MatrixScreensaver" --status
