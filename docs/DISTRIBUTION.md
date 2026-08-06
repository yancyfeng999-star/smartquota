# 智额 · 分发与安装

如何把智额打成安装包、上传 GitHub Release，并在其他 Mac 上使用。

---

## 一、在你这台电脑打包

```bash
cd Apps/Mac
./scripts/package-release.sh
```

可选：

```bash
COPY_TO_DESKTOP=1 ./scripts/package-release.sh   # 同时拷到 桌面/智额-发布/
```

### 产物位置

```text
releases/Mac/
  README.md / LATEST / LATEST.md
  v0.3.12/
    智额-0.3.12.dmg      ← 本机中文名（方便 AirDrop）
    智额-0.3.12.pkg
    RELEASE_NOTES.md
    SHA256SUMS.txt
```

| 位置 | 内容 |
|------|------|
| `releases/Mac/v版本号/*.dmg` | 推荐安装方式（拖到 Applications） |
| `releases/Mac/v版本号/*.pkg` | 双击安装向导 |
| `releases/Mac/LATEST.md` | 最新版本指针 |
| `桌面/智额-发布/` | 可选副本 |

**不**在 `releases/` 里保留松散的 `智额.app`，以免 Spotlight 搜出多份同名应用。日常只用 `/Applications/智额.app`。

`.gitignore` 已忽略 `*.dmg` / `*.pkg` / `*.exe`：**二进制不入库**，只把说明与 SHA 提交仓库。

---

## 二、上传 GitHub Release（维护者）

应用内「检查更新」读的是：

```text
https://api.github.com/repos/yancyfeng999-star/smartquota/releases/latest
```

### 要求

1. **Tag**：`v0.3.12`（与版本号一致，前缀 `v`）  
2. **资产名必须 ASCII**（中文文件名在 GitHub 会乱码，更新器可能匹配失败）：

| 上传文件名 | 来源 |
|------------|------|
| `SmartQuota-0.3.12.dmg` | 复制自 `智额-0.3.12.dmg` |
| `SmartQuota-0.3.12.pkg` | 复制自 `智额-0.3.12.pkg` |
| `SHA256SUMS.txt` | 对上述两个 ASCII 名计算 |

### 示例命令

```bash
STAGE=$(mktemp -d)
cp releases/Mac/v0.3.12/智额-0.3.12.dmg "$STAGE/SmartQuota-0.3.12.dmg"
cp releases/Mac/v0.3.12/智额-0.3.12.pkg "$STAGE/SmartQuota-0.3.12.pkg"
cd "$STAGE"
shasum -a 256 SmartQuota-0.3.12.dmg SmartQuota-0.3.12.pkg > SHA256SUMS.txt

gh release create v0.3.12 \
  --repo yancyfeng999-star/smartquota \
  --title "智额 Mac 0.3.12" \
  --notes-file /path/to/notes.md \
  SmartQuota-0.3.12.dmg \
  SmartQuota-0.3.12.pkg \
  SHA256SUMS.txt
```

最新 Mac 安装包：  
https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.15

---

## 三、用户怎么装

### 推荐：DMG

1. 下载 **SmartQuota-x.y.z.dmg**  
2. 打开 dmg，把 **智额** 拖到 **Applications**  
3. 从启动台 / 应用程序打开  
4. 若 Gatekeeper 拦截：见下文  

### PKG

双击 **SmartQuota-x.y.z.pkg**，按安装向导装到「应用程序」。

### 应用内更新（已装旧版）

1. 菜单栏 → 设置 → **检查更新**  
2. 有新版本时自动下载 dmg，打开后拖到 Applications  
3. 覆盖后重新打开智额  

### 系统要求

- macOS **15.0** 或更高  
- 各会员需在本机登录对应工具（Codex / Kimi / …），见应用内「额度检测配置」

---

## 四、关于「未识别的开发者」

当前默认使用 **临时签名（ad-hoc）**，且通常**未公证（notarize）**。  
因此其他 Mac 的 Gatekeeper 会警告——**正常**，按下面处理即可。

1. **Control + 点击** 智额 → **打开** → **打开**  
2. 或：**系统设置 → 隐私与安全性 → 仍要打开**  
3. 或终端：

```bash
xattr -cr /Applications/智额.app
open /Applications/智额.app
```

若你有 **Apple Developer ID** 证书，可正式签名后再分发：

```bash
security find-identity -v -p codesigning

SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" \
  ./scripts/package-release.sh
```

公证需自备 Apple Developer 账号与 app 专用密码，按 Apple 官方流程对 dmg/pkg 公证。

---

## 五、版本号

改版本再打包：

`Apps/Mac/Sources/App/Info.plist`

- `CFBundleShortVersionString`：如 `0.3.12`  
- `CFBundleVersion`：构建序号，每次发版 +1（如 `15`）  

同步更新：`CHANGELOG.md`、`releases/Mac/LATEST*`、根 `README.md` 下载链接。

---

## 六、日常调试包 vs 发布包

| | 调试 | 发布 |
|--|------|------|
| 脚本 | `Apps/Mac/scripts/build-test-app.sh` | `Apps/Mac/scripts/package-release.sh` |
| 配置 | Debug | Release |
| 输出 | 桌面 `智额.app` | dmg / pkg + 说明 |
| 用途 | 本机开发 | 给别人安装 / GitHub Release |

---

## 七、卸载

```bash
pkill -x 智额 2>/dev/null || true
rm -rf /Applications/智额.app
# 可选：删除设置（会丢掉开关与语言偏好）
# rm -rf ~/.smartquota
```

---

## 八、Windows 分发

见 [`WINDOWS.md`](./WINDOWS.md)。  
Setup.exe 在 **Windows** 上 `npm run tauri:build` 产出，上传到同一仓库的 Release（资产名 ASCII，如 `SmartQuota-Setup-0.1.0-x64.exe`）。
