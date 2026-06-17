#!/bin/bash
set -euo pipefail

APP_SUPPORT_DIR="$HOME/Library/Application Support/DoubaoVoiceToggle"
BIN_DIR="$APP_SUPPORT_DIR/bin"
LABEL="com.yuhanli.doubao-voice-toggle"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true

rm -f "$PLIST_PATH"
rm -f "$BIN_DIR/doubao-voice-toggle" "$BIN_DIR/doubao-voice-hotkey"
rmdir "$BIN_DIR" >/dev/null 2>&1 || true

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$APP_SUPPORT_DIR"
fi

echo "Uninstalled Doubao Voice Toggle."
