# Releases

macOS 安装包目录（类似 GitHub Releases）。

## 最新

见 [LATEST.md](./LATEST.md)。

## 版本列表

| 版本 | DMG（拖到应用程序） | PKG（双击安装） |
|------|---------------------|-----------------|
| [`v0.3.2`](./v0.3.2/) | `智额-0.3.2.dmg` | `智额-0.3.2.pkg` |
| [`v0.3.1`](./v0.3.1/) | `智额-0.3.1.dmg` | `智额-0.3.1.pkg` |
| [`v0.2.1`](./v0.2.1/) | `智额-0.2.1-build3.dmg` | `—` |

## 打包

```bash
cd Apps/Mac
./scripts/package-release.sh
# 产物写入本目录 releases/Mac/v*
```

## 使用方式（与常见 Mac 安装包相同）

1. 打开 **.dmg**
2. 将 **智额.app** 拖到 **Applications**
3. 从启动台打开「智额」

或双击 **.pkg** 使用系统安装向导。
