#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"

cd "$ROOT_DIR"
xcodebuild \
  -project KapiBoard.xcodeproj \
  -scheme KapiBoard \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

echo "$DERIVED_DATA/Build/Products/Debug/KapiBoard.app"

