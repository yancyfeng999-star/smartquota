# Releases · Mac

macOS 安装包目录说明。  
**二进制（dmg/pkg）不入库**，请到 GitHub Releases 下载：

https://github.com/yancyfeng999-star/smartquota/releases

## 最新

见 [LATEST.md](./LATEST.md)。  
当前：**0.3.12** · Tag [`v0.3.12`](https://github.com/yancyfeng999-star/smartquota/releases/tag/v0.3.12)

| GitHub 资产（ASCII） | 用途 |
|----------------------|------|
| `SmartQuota-0.3.12.dmg` | 拖到 Applications（推荐） |
| `SmartQuota-0.3.12.pkg` | 安装向导 |
| `SHA256SUMS.txt` | 校验 |

## 版本列表（本目录有说明文件）

| 版本 | 本机产物名 | GitHub 资产名 |
|------|------------|---------------|
| [v0.3.12](./v0.3.12/) | `智额-0.3.12.dmg` | `SmartQuota-0.3.12.dmg` |
| [v0.3.11](./v0.3.11/) | `智额-0.3.11.dmg` | `SmartQuota-0.3.11.dmg` |
| [v0.3.10](./v0.3.10/) | `智额-0.3.10.dmg` | `SmartQuota-0.3.10.dmg` |
| [v0.3.9](./v0.3.9/) | `智额-0.3.9.dmg` | `SmartQuota-0.3.9.dmg` |
| [v0.3.8](./v0.3.8/) | `智额-0.3.8.dmg` | `SmartQuota-0.3.8.dmg` |
| [v0.3.7](./v0.3.7/) | `智额-0.3.7.dmg` | `SmartQuota-0.3.7.dmg` |
| [v0.3.6](./v0.3.6/) | `智额-0.3.6.dmg` | `SmartQuota-0.3.6.dmg` |
| [v0.3.5](./v0.3.5/) | `智额-0.3.5.dmg` | `SmartQuota-0.3.5.dmg` |
| [v0.3.4](./v0.3.4/) | `智额-0.3.4.dmg` | `SmartQuota-0.3.4.dmg` |
| [v0.3.3](./v0.3.3/) | `智额-0.3.3.dmg` | `SmartQuota-0.3.3.dmg` |
| [v0.3.2](./v0.3.2/) | `SmartQuota-0.3.2.dmg` | `SmartQuota-0.3.2.dmg` |
| [v0.3.1](./v0.3.1/) | `智额-0.3.1.dmg` | — |
| [v0.2.1](./v0.2.1/) | `智额-0.2.1-build3.dmg` | — |

## 打包

```bash
cd Apps/Mac
./scripts/package-release.sh
```

上传 Release 时务必使用 **ASCII 文件名**，步骤见 [`docs/DISTRIBUTION.md`](../../docs/DISTRIBUTION.md)。

## 使用方式

1. 打开 **.dmg**  
2. 将 **智额.app** 拖到 **Applications**  
3. 从启动台打开「智额」  

或双击 **.pkg** 使用系统安装向导。
