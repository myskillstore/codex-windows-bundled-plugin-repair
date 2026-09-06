# Codex Windows Bundled Plugin Repair

Codex Windows Bundled Plugin Repair 是一个用于诊断和安全修复 Windows 版 Codex Desktop 内置插件消失或失效问题的 Codex Skill。
Codex Windows Bundled Plugin Repair is a Codex skill for diagnosing and safely repairing missing or broken bundled plugins in Codex Desktop for Windows.

[English](README.en.md)

## 为什么需要它

Windows 版 Codex Desktop 更新、运行时文件迁移或 Codex 数据目录使用 junction 后，Browser、Chrome、Computer Use 等 `openai-bundled` 插件可能同时从界面和新任务的能力列表中消失。插件目录明明存在，简单重启或反复安装单个插件却无法解决问题，还可能因为错误注册保留市场而扩大故障。

本 Skill 把处理过程改成可验证的顺序：先比较 Codex 数据目录的表面路径与真实路径，再核对保留市场、当前 AppX 包和本地运行时哈希，最后只执行有证据支持的最小修复。它不会接管 `WindowsApps`、重置整个 `.codex` 目录，或默认备份数 GB 的完整插件缓存。

适合以下情况：

- Browser、Chrome、Computer Use、Sites、Visualize 等内置插件同时消失；
- 日志出现 `openai-bundled` 为保留市场、无法从当前来源添加；
- 插件显示已启用，但 Browser 或 Computer Use 初始化失败；
- Codex 更新后，本地 `codex.exe`、`node_repl.exe` 或辅助程序仍是旧版本；
- 命令已经执行，但结果返回时出现 code-mode IPC 解码错误，例如缺少 `code_mode_host_duration_ns` 字段；
- `%USERPROFILE%\.codex` 是指向其他磁盘的 junction。

不适合普通第三方插件安装、非 Windows 系统或单纯的网页故障。

## 核心能力

- 默认只读检查，不直接修改系统；
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

完整方法与停止条件见 [诊断和修复方法](references/diagnosis-and-repair.md)。

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
