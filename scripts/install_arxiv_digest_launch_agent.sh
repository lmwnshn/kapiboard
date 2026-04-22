#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/me.wanshenl.KapiBoard.arxiv-digest.plist"
PYTHON_BIN="/usr/bin/python3"
KAPIBOARD_BIN_DIR="$HOME/.kapiboard/bin"
SCRIPT_PATH="$KAPIBOARD_BIN_DIR/update_arxiv_digest.py"
WRAPPER_PATH="$KAPIBOARD_BIN_DIR/update_arxiv_digest_daily.sh"

mkdir -p "$PLIST_DIR"
mkdir -p "$KAPIBOARD_BIN_DIR"
chmod 700 "$HOME/.kapiboard"
cp "$ROOT_DIR/scripts/update_arxiv_digest.py" "$SCRIPT_PATH"
chmod 755 "$SCRIPT_PATH"

cat > "$WRAPPER_PATH" <<SH
#!/usr/bin/env bash
set -euo pipefail

"$PYTHON_BIN" "$SCRIPT_PATH" --output "$HOME/.kapiboard/arxiv/cs.DB-summary.json"
/usr/bin/open "kapiboard://refresh" >/dev/null 2>&1 || true
SH
chmod 755 "$WRAPPER_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>me.wanshenl.KapiBoard.arxiv-digest</string>
  <key>ProgramArguments</key>
  <array>
    <string>$WRAPPER_PATH</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/KapiBoard-arxiv-digest.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/KapiBoard-arxiv-digest.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/me.wanshenl.KapiBoard.arxiv-digest"

echo "Installed daily arXiv digest launch agent:"
echo "$PLIST_PATH"
