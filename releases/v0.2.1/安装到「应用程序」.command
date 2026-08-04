#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP_SRC="$(pwd)/智额.app"
DEST="/Applications/智额.app"

if [[ ! -d "$APP_SRC" ]]; then
  echo "找不到 智额.app，请与本脚本放在同一文件夹。"
  read -r -p "按回车关闭…"
  exit 1
fi

echo "正在安装到 $DEST …"
# 去掉隔离属性
xattr -cr "$APP_SRC" 2>/dev/null || true
# 结束旧进程
pkill -x "智额" 2>/dev/null || true
sleep 0.3
rm -rf "$DEST"
ditto --norsrc --noextattr --noqtn "$APP_SRC" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
# 尽量保留签名
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

echo "安装完成，正在启动…"
open "$DEST"
echo ""
echo "已安装：/Applications/智额.app"
echo "菜单栏应出现图标。若被拦截：系统设置 → 隐私与安全性 → 仍要打开"
read -r -p "按回车关闭此窗口…"
