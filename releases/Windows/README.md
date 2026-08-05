# Windows 发布

安装包 **不入库**（见根目录 `.gitignore`），请到 GitHub Releases 下载。

## 下载

**公开安装包（0.1.0）：**  
https://github.com/yancyfeng999-star/smartquota/releases/tag/windows-v0.1.0

| 文件 | 说明 |
|------|------|
| `SmartQuota-Setup-0.1.0-x64.exe` | 双击安装（约 2.2MB） |

源码版本线已推进至 **0.5.0**（见 `Apps/Windows/`、`CHANGELOG.md`）。新 Setup 需在 Windows 上构建后另开 Release 上传。

## 本地构建

```bash
cd Apps/Windows
npm install
npm run tauri:build
# 产物示例：src-tauri/target/release/bundle/nsis/SmartQuota_*_x64-setup.exe
```

依赖与对齐说明：[`docs/WINDOWS.md`](../../docs/WINDOWS.md)、[`Apps/Windows/README.md`](../../Apps/Windows/README.md)。