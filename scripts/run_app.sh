#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/build_app_bundle.sh"
open "$ROOT_DIR/dist/KapiBoard.app"
