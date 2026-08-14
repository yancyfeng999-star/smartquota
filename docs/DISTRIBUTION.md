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

## 二、发版铁律（每次交付用户必须做）

用户通过 **设置 → 检查更新** 拿新版本。更新器比较的是 **GitHub Release 上的版本号**。  
因此：**有用户可见修复 / 功能变更 → 必须升版本并发布 Release**，否则别人检查更新仍是旧包。

### 发版检查清单

1. **改代码后先升版本**（`Apps/Mac/Sources/App/Info.plist`）  
   - `CFBundleShortVersionString`：如 `0.3.18` → `0.3.19`  
   - `CFBundleVersion`：构建号 +1（如 `21` → `22`）  
2. **CHANGELOG.md**：把变更写进对应版本段（不要长期留在 Unreleased）  
3. **文档版本指针**：README / PRODUCT / USER_GUIDE / Apps/Mac/README 等里的版本号对齐  
4. **打包**：`cd Apps/Mac && ./scripts/package-release.sh`  
5. **上传 GitHub Release**（Tag `vX.Y.Z` + ASCII 名 dmg/pkg）  
6. **提交仓库**：源码、CHANGELOG、SHA256、LATEST 指针一并 push `main`  

> 不要「只 push 代码不升版本」——已装旧版的用户无法在软件内更新到你的修复。

---

## 三、上传 GitHub Release（维护者）

应用内「检查更新」读的是：

```text
https://api.github.com/repos/yancyfeng999-star/smartquota/releases
```

（取最新 **Mac** 候选，比较 `vX.Y.Z` 与本机 `CFBundleShortVersionString`。）

### 要求

1. **Tag**：`v0.3.19`（与 Info.plist 版本一致，前缀 `v`）  
2. **资产名必须 ASCII**（中文文件名在 GitHub 会乱码，更新器可能匹配失败）：

| 上传文件名 | 来源 |
|------------|------|
| `SmartQuota-0.3.19.dmg` | 复制自 `智额-0.3.19.dmg` |
| `SmartQuota-0.3.19.pkg` | 复制自 `智额-0.3.19.pkg` |
| `SHA256SUMS.txt` / `SHA256SUMS-github.txt` | 对上述两个 ASCII 名计算 |

### 示例命令

```bash
VER=0.3.19
STAGE=$(mktemp -d)
cp "releases/Mac/v${VER}/智额-${VER}.dmg" "$STAGE/SmartQuota-${VER}.dmg"
cp "releases/Mac/v${VER}/智额-${VER}.pkg" "$STAGE/SmartQuota-${VER}.pkg"
cd "$STAGE"
shasum -a 256 "SmartQuota-${VER}.dmg" "SmartQuota-${VER}.pkg" > SHA256SUMS-github.txt

gh release create "v${VER}" \
  --repo yancyfeng999-star/smartquota \
  --title "智额 Mac ${VER}" \
  --notes-file "../releases/Mac/v${VER}/RELEASE_NOTES.md" \
  "SmartQuota-${VER}.dmg" \
  "SmartQuota-${VER}.pkg" \
  SHA256SUMS-github.txt
```

最新 Mac 安装包：  
https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.19

---

## 四、用户怎么装

### 首次安装：DMG 或 PKG

1. 下载 **SmartQuota-x.y.z.dmg** 或 **SmartQuota-x.y.z.pkg**  
2. DMG：打开后把 **智额** 拖到 **Applications**  
3. PKG：双击安装向导，装到「应用程序」  
4. 从启动台 / 应用程序打开  
5. 若 Gatekeeper 拦截：见下文（默认 ad-hoc，首次需右键打开）  

### 应用内更新（已装旧版）

**PKG 是主路径**，**DMG 是回退**。

1. 菜单栏 → 设置 → **检查更新**  
2. 先展示当前版本、新版本、发布日期、变更说明、安装包大小和最低 macOS  
3. 你在更新区域确认后才下载；系统版本不够则不下载  
4. 有合法 PKG + 校验：下载到临时文件（有大小上限、超时、可取消、失败清理），退出后替换  
5. 没有 PKG 时打开 DMG，由你拖到 Applications；**不会**把当前版本标成已更新  
6. 缺少 PKG/DMG 或 SHA256 时显示资产异常，并打开 GitHub Release 页面  
7. 安装失败保留当前可启动的 App，不删除当前版本  

默认只检查**稳定版**。自动更新调度不属于本路径。

### 系统要求

- macOS **15.0** 或更高  
- 各会员需在本机登录对应工具（Codex / Kimi / …），见应用内「额度检测配置」

---

## 五、关于「未识别的开发者」（Gatekeeper）

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

## 六、版本号（与第二节铁律一致）

改版本再打包：

`Apps/Mac/Sources/App/Info.plist`

- `CFBundleShortVersionString`：如 `0.3.19`  
- `CFBundleVersion`：构建序号，每次发版 +1（如 `22`）  

同步更新：`CHANGELOG.md`、`releases/Mac/LATEST*`、根 `README.md` 下载链接。  
**有用户可见改动就必须升版本并发 GitHub Release**，否则应用内「检查更新」拿不到新包。

---

## 七、日常调试包 vs 发布包

| | 调试 | 发布 |
|--|------|------|
| 脚本 | `Apps/Mac/scripts/build-test-app.sh` | `Apps/Mac/scripts/package-release.sh` |
| 配置 | Debug | Release |
| 输出 | 桌面 `智额.app` | dmg / pkg + 说明 |
| 用途 | 本机开发 | 给别人安装 / GitHub Release |

---

## 八、卸载

```bash
pkill -x 智额 2>/dev/null || true
rm -rf /Applications/智额.app
# 可选：删除设置（会丢掉开关与语言偏好）
# rm -rf ~/.smartquota
```

---

## 九、Windows 分发

见 [`WINDOWS.md`](./WINDOWS.md)。  
Setup.exe 在 **Windows** 上 `npm run tauri:build` 产出，上传到同一仓库的 Release（资产名 ASCII，如 `SmartQuota-Setup-0.1.0-x64.exe`）。
