#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/DerivedData/Build/Products/Debug/KapiBoard.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/KapiBoard.app"
OLD_APP_NAME="MacDash""board"
OLD_DEST_APP="$DEST_DIR/$OLD_APP_NAME.app"

"$ROOT_DIR/scripts/build_widget_app.sh"

mkdir -p "$DEST_DIR"
pluginkit -r "$OLD_DEST_APP/Contents/PlugIns/${OLD_APP_NAME}WidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$OLD_DEST_APP/Contents/PlugIns/${OLD_APP_NAME}DetailWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$OLD_DEST_APP/Contents/PlugIns/${OLD_APP_NAME}ArxivWidgetExtension.appex" 2>/dev/null || true
rm -rf "$OLD_DEST_APP"

pluginkit -r "$DEST_APP/Contents/PlugIns/KapiBoardWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$DEST_APP/Contents/PlugIns/KapiBoardDetailWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$DEST_APP/Contents/PlugIns/KapiBoardArxivWidgetExtension.appex" 2>/dev/null || true
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

pluginkit -r "$SOURCE_APP/Contents/PlugIns/KapiBoardWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$SOURCE_APP/Contents/PlugIns/KapiBoardDetailWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$SOURCE_APP/Contents/PlugIns/KapiBoardArxivWidgetExtension.appex" 2>/dev/null || true
pluginkit -a "$DEST_APP/Contents/PlugIns/KapiBoardWidgetExtension.appex" 2>/dev/null || true
pluginkit -a "$DEST_APP/Contents/PlugIns/KapiBoardDetailWidgetExtension.appex" 2>/dev/null || true
pluginkit -a "$DEST_APP/Contents/PlugIns/KapiBoardArxivWidgetExtension.appex" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$DEST_APP"
killall chronod NotificationCenter WidgetRenderer 2>/dev/null || true

echo "$DEST_APP"
