#!/usr/bin/env bash
# Build 智额 (SmartQuota) and install **one** copy — default: /Applications
# Avoids Desktop + Applications dual apps (Spotlight / menu-bar doubles).
#
# Usage:
#   ./scripts/build-test-app.sh
#   DEST_DIR="$HOME/Desktop" ./scripts/build-test-app.sh   # only if you really want Desktop
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="智额"
# Default: Applications — single install path for daily use
DEST_DIR="${DEST_DIR:-/Applications}"
CONFIG="${CONFIG:-Debug}"
DERIVED="${ROOT}/.build/DerivedData"

echo "==> [1/4] tuist generate"
tuist generate --no-open

echo "==> [2/4] xcodebuild ($CONFIG)"
xcodebuild \
  -workspace SmartQuota.xcworkspace \
  -scheme SmartQuota \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  | tail -30

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name "*.app" | head -1)"
if [[ -z "${APP_SRC}" || ! -d "${APP_SRC}" ]]; then
  echo "ERROR: built .app not found under $DERIVED/Build/Products/$CONFIG"
  ls -la "$DERIVED/Build/Products/$CONFIG" || true
  exit 1
fi

echo "==> [3/4] install to ${DEST_DIR}/${APP_NAME}.app (replace)"
mkdir -p "$DEST_DIR"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

# Remove common extra copies so only DEST remains
if [[ "$DEST_DIR" == "/Applications" ]]; then
  rm -rf "$HOME/Desktop/${APP_NAME}.app" 2>/dev/null || true
  rm -f "$HOME/Desktop/启动智额.command" 2>/dev/null || true
fi

rm -rf "${DEST_DIR}/${APP_NAME}.app"
cp -R "$APP_SRC" "${DEST_DIR}/${APP_NAME}.app"
xattr -cr "${DEST_DIR}/${APP_NAME}.app" 2>/dev/null || true
codesign --force --deep --sign - "${DEST_DIR}/${APP_NAME}.app" 2>/dev/null || true

echo "==> [4/4] smoke check"
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${DEST_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || true
VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${DEST_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "?")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${DEST_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || echo "?")

echo ""
echo "OK — 智额 / SmartQuota  ${VER} (build ${BUILD})"
echo "  唯一安装：${DEST_DIR}/${APP_NAME}.app"
echo "  打开：open -a \"${DEST_DIR}/${APP_NAME}.app\""
