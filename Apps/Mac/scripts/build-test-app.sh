#!/usr/bin/env bash
# Build 智额 (SmartQuota) test app → Desktop
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="智额"
DEST_DIR="${DEST_DIR:-$HOME/Desktop}"
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

echo "==> [3/4] install to $DEST_DIR/${APP_NAME}.app"
mkdir -p "$DEST_DIR"
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "AI额度监控" 2>/dev/null || true
sleep 0.3

rm -rf "${DEST_DIR}/${APP_NAME}.app" "${DEST_DIR}/AI额度监控.app"
cp -R "$APP_SRC" "${DEST_DIR}/${APP_NAME}.app"
xattr -cr "${DEST_DIR}/${APP_NAME}.app" 2>/dev/null || true
codesign --force --deep --sign - "${DEST_DIR}/${APP_NAME}.app" 2>/dev/null || true

LAUNCHER="${DEST_DIR}/启动智额.command"
cat > "$LAUNCHER" <<'EOF'
#!/bin/bash
APP="$HOME/Desktop/智额.app"
if [[ ! -d "$APP" ]]; then
  echo "找不到 $APP"
  read -r -p "按回车关闭…"
  exit 1
fi
xattr -cr "$APP" 2>/dev/null || true
open "$APP"
echo "已启动：智额 · SmartQuota"
sleep 1
EOF
chmod +x "$LAUNCHER"
rm -f "${DEST_DIR}/启动AI额度监控.command" 2>/dev/null || true

echo "==> [4/4] smoke check"
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${DEST_DIR}/${APP_NAME}.app/Contents/Info.plist" 2>/dev/null || true

echo ""
echo "OK — 智额 / SmartQuota"
echo "  双击：${DEST_DIR}/${APP_NAME}.app"
echo "  无启动弹窗 · 长按卡片进入排序"
