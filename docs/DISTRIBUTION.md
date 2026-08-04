# 智额 · 分发与安装

如何把智额打成安装包，并拷到其他 Mac 使用。

---

## 一、在你这台电脑打包

```bash
cd ~/Desktop/智额   # 或仓库路径
./scripts/package-release.sh
```

### 产物位置（GitHub 风格）

```text
releases/
  README.md          ← 版本索引
  LATEST.md          ← 最新版指针
  v0.3.1/
    智额-0.3.1-build4.zip   ← 推荐发给别人
    智额-0.3.1-build4.dmg
    智额.app
    安装说明.txt
    安装到「应用程序」.command
    RELEASE_NOTES.md
    SHA256SUMS.txt
```

| 位置 | 内容 |
|------|------|
| `releases/v版本号/*.zip` | **推荐发给别人** |
| `releases/v版本号/*.dmg` | 磁盘镜像 |
| `releases/LATEST.md` | 最新版本链接 |
| `桌面/智额-发布/` | 可选副本（方便 AirDrop） |

包内包含：

- `智额.app`
- `安装说明.txt`
- `安装到「应用程序」.command`（一键装到 `/Applications`）

---

## 二、其他电脑怎么装

### 推荐

1. 收到并**解压** zip  
2. 双击 **`安装到「应用程序」.command`**  
3. 若弹出「无法打开」→ 点 **打开**，或：  
   **系统设置 → 隐私与安全性 → 仍要打开**  
4. 菜单栏出现图标即成功  

### 手动

1. 把 `智额.app` 拖进 **应用程序**  
2. **按住 Control 点击** 智额 → **打开** → **打开**  
3. 或终端：

```bash
xattr -cr /Applications/智额.app
open /Applications/智额.app
```

### 系统要求

- macOS **15.0** 或更高  
- 各会员需在本机登录对应工具（Codex / Kimi / …），见应用内「额度检测配置」

---

## 三、关于「未识别的开发者」

当前默认使用 **临时签名（ad-hoc）**，且通常**未公证（notarize）**。  
因此其他 Mac 的 Gatekeeper 会警告——**正常**，按上面「仍要打开」即可。

若你有 **Apple Developer ID** 证书，可正式签名后再分发：

```bash
# 查看证书
security find-identity -v -p codesigning

# 正式签名打包
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" \
  ./scripts/package-release.sh
```

公证需自备 Apple Developer 账号与 app 专用密码，按 Apple 官方流程对 dmg/pkg 公证。

---

## 四、版本号

改版本再打包：

`Sources/App/Info.plist`

- `CFBundleShortVersionString`：如 `0.2.1`  
- `CFBundleVersion`：构建序号，每次发版 +1  

---

## 五、日常调试包 vs 发布包

| | 调试 | 发布 |
|--|------|------|
| 脚本 | `./scripts/build-test-app.sh` | `./scripts/package-release.sh` |
| 配置 | Debug | Release |
| 输出 | 桌面 `智额.app` | zip / dmg + 安装脚本 |
| 用途 | 本机开发 | 给别人安装 |

---

## 六、卸载

```bash
pkill -x 智额 2>/dev/null || true
rm -rf /Applications/智额.app
# 可选：删除设置（会丢掉开关与语言偏好）
# rm -rf ~/.smartquota
```
