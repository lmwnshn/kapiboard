#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="KapiBoard"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/DashboardApp" "$MACOS_DIR/DashboardApp"
cp "$ROOT_DIR/DashboardApp/AppInfo.plist" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

chmod +x "$MACOS_DIR/DashboardApp"

echo "$APP_DIR"

