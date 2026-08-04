#!/usr/bin/env bash
# 智额 · SmartQuota — 打成 macOS 标准安装包
#
# 同类做法（常见 Mac 菜单栏工具）：
#   DMG 打开后：左侧 智额.app → 拖到右侧「应用程序」
#   另附 .pkg 双击安装（安装向导）
#
# 产物：
#   <repo>/releases/Mac/vX.Y.Z/
#     智额-X.Y.Z.dmg     ← 推荐分发（拖进 Applications）
#     智额-X.Y.Z.pkg     ← 双击安装包
#     RELEASE_NOTES.md
#     SHA256SUMS.txt
#
# 用法（在 Apps/Mac 下）：
#   ./scripts/package-release.sh
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/package-release.sh
#
set -euo pipefail

# Apps/Mac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 仓库根（Apps/Mac → Apps → 根）
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

APP_NAME="智额"
EN_NAME="SmartQuota"
CONFIG="Release"
DERIVED="${ROOT}/.build/DerivedData-Release"
RELEASES_ROOT="${RELEASES_ROOT:-$REPO_ROOT/releases/Mac}"
COPY_TO_DESKTOP="${COPY_TO_DESKTOP:-1}"
DESKTOP_OUT="${DESKTOP_OUT:-$HOME/Desktop/智额-发布}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

printf '%s\n' "==> [1/5] tuist generate"
tuist generate --no-open

printf '%s\n' "==> [2/5] xcodebuild Release (universal)"
BUILD_LOG="${DERIVED}/xcodebuild-release.log"
mkdir -p "${DERIVED}"
set +e
xcodebuild \
  -workspace SmartQuota.xcworkspace \
  -scheme SmartQuota \
  -configuration "${CONFIG}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  >"${BUILD_LOG}" 2>&1
BUILD_STATUS=$?
set -e
tail -25 "${BUILD_LOG}" || true
if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "ERROR: xcodebuild failed (exit ${BUILD_STATUS}). Full log: ${BUILD_LOG}"
  exit "${BUILD_STATUS}"
fi

APP_SRC="$(find "${DERIVED}/Build/Products/${CONFIG}" -maxdepth 1 -name "*.app" | head -1)"
if [[ -z "${APP_SRC}" || ! -d "${APP_SRC}" ]]; then
  echo "ERROR: Release .app not found under ${DERIVED}/Build/Products/${CONFIG}"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_SRC}/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_SRC}/Contents/Info.plist")"
TAG="v${VERSION}"
STAGE="${RELEASES_ROOT}/${TAG}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zhi-e-pkg.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

printf '%s\n' "==> [3/5] stage app + sign  (${VERSION} build ${BUILD})"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$WORK/app"

ditto --norsrc --noextattr --noqtn "$APP_SRC" "$WORK/app/${APP_NAME}.app"
xattr -cr "$WORK/app/${APP_NAME}.app" 2>/dev/null || true

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$WORK/app/${APP_NAME}.app"
  SIGN_NOTE="临时签名（ad-hoc）。其他 Mac 首次打开：右键 → 打开，或系统设置 → 隐私与安全性 → 仍要打开。"
else
  ENT="$ROOT/Sources/App/entitlements.plist"
  if [[ -f "$ENT" ]]; then
    codesign --force --deep --options runtime --timestamp \
      --entitlements "$ENT" --sign "$SIGN_IDENTITY" \
      "$WORK/app/${APP_NAME}.app"
  else
    codesign --force --deep --options runtime --timestamp \
      --sign "$SIGN_IDENTITY" \
      "$WORK/app/${APP_NAME}.app"
  fi
  SIGN_NOTE="已签名：${SIGN_IDENTITY}"
fi

# Keep a copy of the app inside the version folder (for archive / debugging)
ditto --norsrc --noextattr --noqtn "$WORK/app/${APP_NAME}.app" "$STAGE/${APP_NAME}.app"

printf '%s\n' "==> [4/5] build installer DMG + PKG"

# ---------- DMG: drag App → Applications（行业标准）----------
DMG_ROOT="$WORK/dmg"
mkdir -p "$DMG_ROOT"
ditto --norsrc --noextattr --noqtn "$WORK/app/${APP_NAME}.app" "$DMG_ROOT/${APP_NAME}.app"
# Symlink to Applications — user drags app onto it
ln -s /Applications "$DMG_ROOT/Applications"

# Short install tip on the disk (English filename avoids encoding issues on some tools)
cat > "$DMG_ROOT/Install.txt" <<EOF
智额 · ${EN_NAME}  ${VERSION}

安装方法（和常见 Mac 软件一样）：
  1. 把「${APP_NAME}.app」拖到「Applications」文件夹
  2. 打开「启动台」或「应用程序」里的 智额
  3. 菜单栏出现图标即成功

若提示无法打开：
  Control + 点击 智额 → 打开 → 打开
  或：系统设置 → 隐私与安全性 → 仍要打开

系统要求：macOS 15+
${SIGN_NOTE}
EOF

# Chinese name for users who open the volume in Finder
cp "$DMG_ROOT/Install.txt" "$DMG_ROOT/安装说明.txt"

DMG_PATH="${STAGE}/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"
# RW then convert for cleaner layout
RW_DMG="$WORK/temp.dmg"
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$DMG_ROOT" \
  -ov -fs HFS+ -format UDRW \
  "$RW_DMG" >/dev/null

# Optional: set Finder window size / icon positions via AppleScript (best-effort)
MOUNT_DIR="$WORK/mnt"
mkdir -p "$MOUNT_DIR"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/Apple_HFS|Apple_APFS|GUID_partition_scheme/ {print $1; exit}')"
# Find mount point
VOL_PATH="$(ls -d /Volumes/${APP_NAME}* 2>/dev/null | head -1 || true)"
if [[ -n "${VOL_PATH:-}" && -d "$VOL_PATH" ]]; then
  # Try to position icons like a classic installer DMG
  osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
  tell disk "$(basename "$VOL_PATH")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 480}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    try
      set position of item "${APP_NAME}.app" of container window to {160, 180}
      set position of item "Applications" of container window to {480, 180}
      set position of item "安装说明.txt" of container window to {320, 340}
    end try
    update without registering applications
    delay 0.5
    close
  end tell
end tell
APPLESCRIPT
  sync
  hdiutil detach "$VOL_PATH" -quiet 2>/dev/null || hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
else
  hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
fi

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG"

# ---------- PKG: 双击安装向导 ----------
PKG_ROOT="$WORK/pkgroot"
mkdir -p "$PKG_ROOT"
ditto --norsrc --noextattr --noqtn "$WORK/app/${APP_NAME}.app" "$PKG_ROOT/${APP_NAME}.app"

PKG_PATH="${STAGE}/${APP_NAME}-${VERSION}.pkg"
rm -f "$PKG_PATH"
pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "com.smartquota.app" \
  --version "${VERSION}" \
  --install-location "/Applications" \
  --min-os-version "15.0" \
  "$PKG_PATH" >/dev/null

# Release notes + checksums
DATE_STR="$(date '+%Y-%m-%d')"
cat > "$STAGE/RELEASE_NOTES.md" <<EOF
# 智额 ${VERSION} (build ${BUILD})

- **日期**：${DATE_STR}
- **标签**：\`${TAG}\`

## 安装包

| 文件 | 怎么用 |
|------|--------|
| **${APP_NAME}-${VERSION}.dmg** | 打开后，把 App **拖到 Applications**（推荐，同类 Mac 软件通用） |
| **${APP_NAME}-${VERSION}.pkg** | 双击，按安装向导装到「应用程序」 |

## 首次打开

若提示无法验证开发者：Control + 点击 → 打开。  
${SIGN_NOTE}

## 系统

macOS 15.0 或更高。
EOF

(
  cd "$STAGE"
  shasum -a 256 "${APP_NAME}-${VERSION}.dmg" "${APP_NAME}-${VERSION}.pkg" > SHA256SUMS.txt
)

# LATEST pointers
cat > "${RELEASES_ROOT}/LATEST" <<EOF
${TAG}
${VERSION}
${BUILD}
EOF

cat > "${RELEASES_ROOT}/LATEST.md" <<EOF
# Latest release

| | |
|--|--|
| **Version** | ${VERSION} (build ${BUILD}) |
| **Tag** | [\`${TAG}\`](./${TAG}/) |
| **DMG 安装盘** | [\`${APP_NAME}-${VERSION}.dmg\`](./${TAG}/${APP_NAME}-${VERSION}.dmg) |
| **PKG 安装包** | [\`${APP_NAME}-${VERSION}.pkg\`](./${TAG}/${APP_NAME}-${VERSION}.pkg) |

安装：打开 DMG → 拖到 Applications；或双击 PKG 按向导安装。
EOF

# Index (quoted heredoc — no bash expansion / backtick pitfalls)
RELEASES_ROOT="$RELEASES_ROOT" python3 - <<'PY'
import os
import re
from pathlib import Path

root = Path(os.environ["RELEASES_ROOT"])
rows = []
for p in sorted(root.iterdir(), reverse=True):
    if p.is_dir() and re.match(r"^v\d", p.name):
        dmgs = list(p.glob("*.dmg"))
        pkgs = list(p.glob("*.pkg"))
        d = dmgs[0].name if dmgs else "—"
        k = pkgs[0].name if pkgs else "—"
        rows.append(f"| [`{p.name}`](./{p.name}/) | `{d}` | `{k}` |")

lines = [
    "# Releases",
    "",
    "macOS 安装包目录（类似 GitHub Releases）。",
    "",
    "## 最新",
    "",
    "见 [LATEST.md](./LATEST.md)。",
    "",
    "## 版本列表",
    "",
    "| 版本 | DMG（拖到应用程序） | PKG（双击安装） |",
    "|------|---------------------|-----------------|",
    *rows,
    "",
    "## 打包",
    "",
    "    ./scripts/package-release.sh",
    "",
    "## 使用方式（与常见 Mac 安装包相同）",
    "",
    "1. 打开 **.dmg**",
    "2. 将 **智额.app** 拖到 **Applications**",
    "3. 从启动台打开「智额」",
    "",
    "或双击 **.pkg** 使用系统安装向导。",
    "",
]
(root / "README.md").write_text("\n".join(lines), encoding="utf-8")
print("index ok")
PY

printf '%s\n' "==> [5/5] desktop copy"
if [[ "${COPY_TO_DESKTOP}" == "1" ]]; then
  rm -rf "${DESKTOP_OUT}"
  mkdir -p "${DESKTOP_OUT}"
  if [[ ! -f "${DMG_PATH}" || ! -f "${PKG_PATH}" ]]; then
    echo "ERROR: missing installer files"
    echo "  DMG=${DMG_PATH}"
    echo "  PKG=${PKG_PATH}"
    exit 1
  fi
  cp -f "${DMG_PATH}" "${PKG_PATH}" "${STAGE}/RELEASE_NOTES.md" "${STAGE}/SHA256SUMS.txt" "${DESKTOP_OUT}/"
  cat > "${DESKTOP_OUT}/如何安装.txt" <<EOF
智额 ${VERSION} 安装包

推荐：双击「${APP_NAME}-${VERSION}.dmg」
  → 把 智额.app 拖到 Applications（应用程序）

或：双击「${APP_NAME}-${VERSION}.pkg」按向导安装

项目内位置：${STAGE}
EOF
  printf '%s\n' "  → ${DESKTOP_OUT}"
fi

# Remove obsolete clutter files if any from old packaging style
rm -f "${STAGE}/安装到「应用程序」.command" "${STAGE}/安装说明.txt" "${STAGE}/README.txt" 2>/dev/null || true
# Old zip style no longer primary
rm -f "${STAGE}"/*.zip 2>/dev/null || true

echo ""
echo "======== 安装包已就绪 ========"
echo "版本 ${VERSION} (build ${BUILD})  ${TAG}"
echo ""
echo "  DMG（推荐）：${DMG_PATH}"
echo "  PKG（向导）：${PKG_PATH}"
echo ""
echo "  发给别人：发 .dmg 或 .pkg 任一即可"
echo "  安装：DMG 里拖到 Applications  /  或双击 PKG"
echo "================================"
ls -lh "${DMG_PATH}" "${PKG_PATH}"
