#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$HOME/.matrix_screensaver"
PLIST_DEST="$HOME/Library/LaunchAgents/com.matrix.screensaver.plist"
LABEL="com.matrix.screensaver"
UID_NUM="$(id -u)"

echo "==> Compiling MatrixScreensaver (optimized arm64)..."
swiftc -O \
  -o "$PROJECT_DIR/MatrixScreensaver" \
  "$PROJECT_DIR/MatrixScreensaver.swift" \
  -framework Cocoa \
  -framework WebKit \
  -framework IOKit

mkdir -p "$RUNTIME_DIR"

echo "==> Installing binary to $RUNTIME_DIR/MatrixScreensaver..."
# Atomic replace so a running binary is never overwritten in place
cp "$PROJECT_DIR/MatrixScreensaver" "$RUNTIME_DIR/MatrixScreensaver.new"
chmod +x "$RUNTIME_DIR/MatrixScreensaver.new"
mv -f "$RUNTIME_DIR/MatrixScreensaver.new" "$RUNTIME_DIR/MatrixScreensaver"

if [ ! -f "$RUNTIME_DIR/config.ini" ]; then
  echo "==> Installing initial config.ini..."
  cp "$PROJECT_DIR/config.ini" "$RUNTIME_DIR/config.ini"
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
