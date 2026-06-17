#!/bin/bash
set -euo pipefail

BIN_DIR="$HOME/Library/Application Support/DoubaoVoiceToggle/bin"
HOTKEY="$BIN_DIR/doubao-voice-hotkey"
TOGGLE="$BIN_DIR/doubao-voice-toggle"

if [[ ! -x "$HOTKEY" || ! -x "$TOGGLE" ]]; then
  echo "Installed binaries not found. Run ./scripts/install.sh first." >&2
  exit 1
fi

"$HOTKEY" --request-permissions || true
"$TOGGLE" --request-permissions || true

cat <<EOF

Then confirm these entries in System Settings:

Input Monitoring:
  $HOTKEY

Accessibility:
  $TOGGLE

After changing permissions, restart the LaunchAgent:
  ./scripts/restart.sh
EOF
