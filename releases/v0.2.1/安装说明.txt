═══════════════════════════════════════
  智额 · SmartQuota  0.2.1 (构建 3)
  macOS 15+ 菜单栏 · AI 会员额度监控
═══════════════════════════════════════

【推荐安装】
1. 双击「安装到「应用程序」.command」
   → 自动复制到 /Applications/智额.app 并启动
2. 若系统提示无法打开：
   - 在「安装到…」窗口中选「打开」
   - 或：系统设置 → 隐私与安全性 → 仍要打开

【手动安装】
1. 将「智额.app」拖到「应用程序」文件夹
2. 首次打开：按住 Control 点图标 → 打开 → 打开
3. 或在终端执行：
   xattr -cr /Applications/智额.app
   open /Applications/智额.app

【系统要求】
· macOS 15.0 或更高
· 各 AI 会员需本机已登录对应 CLI/客户端（见应用内设置）

【使用】
· 菜单栏图标 → 查看额度
· 设置 → 会员开关 / 额度检测 / 语言
· 文档：https://（本机仓库 README）

【签名说明】
临时签名（ad-hoc）。其他电脑首次请右键 → 打开，或运行安装脚本。
本包若为临时签名，非 App Store / 未公证，Gatekeeper 会警告，属正常现象。
有 Apple Developer ID 时，打包方可用：
  SIGN_IDENTITY="Developer ID Application: …" ./scripts/package-release.sh

【隐私】
· 数据与密钥仅在本机；不上传账号
· 请勿把 auth.json / API Key 分享给他人

版权：本地构建，非各 AI 厂商官方应用。独立开源产品，MIT 许可。
