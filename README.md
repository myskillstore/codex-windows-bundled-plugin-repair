# Codex Windows Bundled Plugin Repair

Codex Windows Bundled Plugin Repair 是一个用于诊断和安全修复 Windows 版 Codex Desktop 内置插件消失或失效问题的 Codex Skill。
Codex Windows Bundled Plugin Repair is a Codex skill for diagnosing and safely repairing missing or broken bundled plugins in Codex Desktop for Windows.

[English](README.en.md)

## 为什么需要它

Windows 版 Codex Desktop 更新、运行时文件迁移或 Codex 数据目录使用 junction 后，Browser、Chrome、Computer Use 等 `openai-bundled` 插件可能同时从界面和新任务的能力列表中消失。另一种容易误判的情况是浏览器页面明明已经显示，但当前任务无法枚举或控制标签页：页面创建可能成功了，只是自动化句柄没有返回或已经失效。简单重启、重复开页或反复安装单个插件不仅不一定解决问题，还可能制造重复标签页或因错误注册保留市场而扩大故障。

本 Skill 把处理过程改成可验证的顺序：先区分页面渲染状态与自动化控制状态，优先枚举并重新附着已有标签页；仍失败时再比较 Codex 数据目录的表面路径与真实路径，核对保留市场、当前 AppX 包和本地运行时哈希，最后只执行有证据支持的最小修复。它不会接管 `WindowsApps`、重置整个 `.codex` 目录，或默认备份数 GB 的完整插件缓存。

适合以下情况：

- Browser、Chrome、Computer Use、Sites、Visualize 等内置插件同时消失；
- 日志出现 `openai-bundled` 为保留市场、无法从当前来源添加；
- 插件显示已启用，但 Browser 或 Computer Use 初始化失败；
- 浏览器页面已显示，但当前任务无法读取 DOM、截图或执行交互；
- Codex 更新后，本地 `codex.exe`、`node_repl.exe` 或辅助程序仍是旧版本；
- 命令已经执行，但结果返回时出现 code-mode IPC 解码错误，例如缺少 `code_mode_host_duration_ns` 字段；
- `%USERPROFILE%\.codex` 是指向其他磁盘的 junction。

不适合普通第三方插件安装、非 Windows 系统或单纯的网页故障。

## 核心能力

- 默认只读检查，不直接修改系统；
- 区分“页面已经打开”和“控制句柄已经附着”，优先恢复现有标签页；
- 识别 lexical/canonical `CODEX_HOME` 不一致；
- 检查 `openai-bundled` 配置源和物化目录；
- 比较当前 AppX 与迁移后运行时的 SHA-256；
- 覆盖可能缺少 Windows 文件版本信息的 `codex-code-mode-host.exe`；
- 按需持久化正确的 `CODEX_HOME`；
- 只修复 `config.toml` 中的内置市场段落；
- 只备份、替换发生漂移的运行时文件；
- 避免把新版保留市场错误指向 `openai-bundled-fixed`；
- 输出适合后续验证的精简诊断结果，不转储隐私配置。

## 安装

将仓库克隆到 Codex Skills 目录：

```powershell
git clone <repository-url> "$env:CODEX_HOME\skills\codex-windows-bundled-plugin-repair"
```

如果没有设置 `CODEX_HOME`，使用：

```powershell
git clone <repository-url> "$env:USERPROFILE\.codex\skills\codex-windows-bundled-plugin-repair"
```

重新打开 Codex 后，可以自然描述故障，或显式调用：

```text
$codex-windows-bundled-plugin-repair
```

## 使用

首先运行只读检查：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly
```

结构化输出：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly -Json
```

根据检查结果选择最小修复：

```powershell
# 修复 junction/真实路径不一致
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairCodexHome

# 修复旧的 openai-bundled 配置源
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairMarketplaceSource

# Codex 完全退出后，修复运行时漂移
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairRuntimeDrift
```

页面可见但无法控制时，先使用[浏览器控制句柄恢复方法](references/browser-control-recovery.md)。完整安装诊断、修复方法与停止条件见[诊断和修复方法](references/diagnosis-and-repair.md)。

## 安全边界

- 修复前必须先检查，并获得用户对具体修改的授权；
- 不修改 `WindowsApps` ACL 或所有权；
- 不删除整个 Codex 数据目录；
- 不自动关闭 Codex；
- 不输出完整配置、日志、任务记录或认证信息；
- 备份仅包含即将被修改的文件和环境变量值。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\Test-CodexBundledPluginRepair.ps1"
conda run -n codex-base python "<skill-creator>\scripts\quick_validate.py" .
conda run -n codex-base python "<open-source-skill-publisher>\scripts\scan_release_safety.py" .
```

## 许可

[MIT](LICENSE)
