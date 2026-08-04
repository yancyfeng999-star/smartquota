# Windows 发布目录

放置 **SmartQuota-Setup-x.y.z-x64.exe** 的说明与校验和。

构建（在 Windows 上）：

```bash
cd Apps/Windows
npm run tauri:build
```

产物一般在：

`Apps/Windows/src-tauri/target/release/bundle/nsis/`

上传到本目录或 GitHub Release（文件名请用 ASCII）。
