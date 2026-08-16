# DeepSeek Harness Desktop

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 Web GUI 做成 Windows 桌面应用：
**双击图标即用**，不用每次手动开终端、启动服务、打开浏览器。

## 下载安装

1. 到本仓库 [Releases](../../releases) 下载最新的 `DeepSeekHarness-Setup-*.exe`
2. 双击运行，按向导选择**安装路径**（默认 `%LOCALAPPDATA%\DeepSeekHarness`）
3. 完成即可：桌面和开始菜单会出现 **DeepSeek Harness** 图标

> 依赖 [Node.js](https://nodejs.org)（安装向导会自动检测，未安装时会提示）。
> 由于未做代码签名，首次运行 Windows SmartScreen 可能提示，选择「更多信息 → 仍要运行」。

## 功能特性

- **一键启动**：双击图标 → 后台静默启动服务（约 3 秒）→ 弹出无地址栏、无标签页的应用窗口
- **智能复用**：如果 3080 端口已有正在运行的 harness，直接复用，不重复启动
- **自动清理**：关闭应用窗口后，桌面版自己启动的服务自动停止；复用的已有服务不受影响
- **端口冲突自动避让**：3080 被其他程序占用时自动改用 3081+ 空闲端口
- **数据共享**：沿用 `~/.dsh`，与命令行版共享会话、模型配置等全部数据
- **开始菜单**：附带「Stop DeepSeek Harness」快捷方式，可随时停止服务

## 使用

| 操作 | 说明 |
| --- | --- |
| 启动 | 双击桌面图标 |
| 退出 | 直接关闭应用窗口（桌面版启动的服务随之停止） |
| 停止服务 | 开始菜单 → Stop DeepSeek Harness |
| 卸载 | 控制面板「应用和功能」→ DeepSeek Harness 卸载（`~/.dsh` 数据保留） |

日志位于 `%LOCALAPPDATA%\DSHDesktop\logs\`（`server.out.log` / `server.err.log` / `launcher.log`）。

## 工作原理

- 桌面版把 harness 完整固定拷贝到安装目录的 `app\`，与 npx 缓存解耦
- `Launch.ps1` 负责：检测端口 → 按需启动 `dsh web`（隐藏窗口、日志落盘）→
  用 Edge/Chrome 的应用窗口模式打开 → 监听窗口关闭并回收服务
- 运行态数据（日志、浏览器 profile、pid 文件）统一放在 `%LOCALAPPDATA%\DSHDesktop\`

## 从源码构建

```powershell
# 1. 本地快速安装（免打包，供开发调试）
powershell -ExecutionPolicy Bypass -File Install.ps1

# 2. 打安装包（需要 Inno Setup 6，https://jrsoftware.org）
iscc installer\DSHSetup.iss
# 产物: dist\DeepSeekHarness-Setup-<version>.exe
```

`Install.ps1` 会自动从 npx 缓存（`%LOCALAPPDATA%\npm-cache\_npx\*`）找到 harness
并固定拷贝；`-SourceRoot <dir>` 可手动指定来源。

## 目录结构

```
DSH-Desktop\
├── Install.ps1          本地一键安装（调试用）
├── Launch.ps1           启动器（核心）
├── Stop.ps1             停止服务 + 关闭应用窗口
├── Uninstall.ps1        卸载（本地安装方式用）
├── installer\
│   └── DSHSetup.iss     Inno Setup 打包脚本
├── build\payload\       打包内容（app\ + 脚本 + 图标）
└── dist\                Setup.exe 产物
```

## License

MIT。本仓库仅为打包与启动层封装；DeepSeek Harness 本身版权归其作者所有。
