#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/DoubaoVoiceToggle"
BIN_DIR="$APP_SUPPORT_DIR/bin"
LOG_DIR="$APP_SUPPORT_DIR/logs"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LABEL="com.yuhanli.doubao-voice-toggle"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
HOTKEY_PATH="$BIN_DIR/doubao-voice-hotkey"
LOG_PATH="$LOG_DIR/hotkey.log"
ERR_PATH="$LOG_DIR/hotkey.err.log"

escape_sed_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

mkdir -p "$BIN_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

cd "$ROOT_DIR"
swift build -c release

cp "$ROOT_DIR/.build/release/doubao-voice-toggle" "$BIN_DIR/"
cp "$ROOT_DIR/.build/release/doubao-voice-hotkey" "$BIN_DIR/"
chmod 755 "$BIN_DIR/doubao-voice-toggle" "$BIN_DIR/doubao-voice-hotkey"

sed \
  -e "s|__HOTKEY_PATH__|$(escape_sed_replacement "$HOTKEY_PATH")|g" \
  -e "s|__LOG_PATH__|$(escape_sed_replacement "$LOG_PATH")|g" \
  -e "s|__ERR_PATH__|$(escape_sed_replacement "$ERR_PATH")|g" \
  "$ROOT_DIR/launchd/$LABEL.plist.template" > "$PLIST_PATH"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

cat <<EOF
Installed Doubao Voice Toggle.

Binaries:
  $BIN_DIR/doubao-voice-toggle
  $BIN_DIR/doubao-voice-hotkey

LaunchAgent:
  $PLIST_PATH

If F8 does not work yet, grant Input Monitoring and Accessibility permission to:
  $BIN_DIR/doubao-voice-hotkey
  $BIN_DIR/doubao-voice-toggle

You can request both permission prompts with:
  $ROOT_DIR/scripts/request-permissions.sh
EOF
