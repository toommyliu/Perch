#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Perch"
BUNDLE_ID="com.app.perch"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/DerivedData/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
PROJECT="$ROOT_DIR/Perch.xcodeproj"
SCHEME="Perch"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
DEVELOPMENT_BUNDLE_ID="com.app.perch.dev"

usage() {
  cat >&2 <<'USAGE'
usage: ./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify]
USAGE
}

build_debug() {
  "$ROOT_DIR/scripts/perch" debug
}

build_debug_without_launching() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "PRODUCT_BUNDLE_IDENTIFIER=$DEVELOPMENT_BUNDLE_ID" \
    build
}

ensure_built_app() {
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
  fi
}

case "$MODE" in
  run)
    build_debug
    ;;
  --debug|debug)
    build_debug_without_launching
    ensure_built_app
    pkill -f "$APP_BINARY" >/dev/null 2>&1 || true
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    build_debug
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_debug
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_debug
    ensure_built_app
    sleep 1
    pgrep -f "$APP_BINARY" >/dev/null
    echo "Verified $APP_NAME is running"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
