# Codex Windows Bundled Plugin Repair

Codex Windows Bundled Plugin Repair 是一个用于诊断和安全修复 Windows 版 Codex Desktop 内置插件消失或失效问题的 Codex Skill。
Codex Windows Bundled Plugin Repair is a Codex skill for diagnosing and safely repairing missing or broken bundled plugins in Codex Desktop for Windows.

[中文](README.md)

## Why this exists

After a Codex Desktop update, runtime relocation, or a junctioned Codex data directory, bundled tools such as Browser, Chrome, and Computer Use can disappear from both the UI and new task capability catalogs. The plugin files may still exist, while restarts or repeated per-plugin installs do not address the root cause. Registering the reserved marketplace from the wrong path can make the failure broader.

This skill turns the repair into an evidence-driven sequence: compare the lexical and canonical Codex data paths, validate the reserved marketplace, compare the current AppX bundle with relocated runtime hashes, and apply only the smallest supported mutation. It does not take ownership of `WindowsApps`, reset the whole `.codex` directory, or create multi-gigabyte plugin-cache backups by default.

Use it when:

- several bundled plugins disappear together, including Browser, Chrome, Computer Use, Sites, or Visualize;
- logs say that `openai-bundled` is reserved and cannot be added from the submitted source;
- plugins are enabled but Browser or Computer Use cannot initialize;
- local `codex.exe`, `node_repl.exe`, or helper binaries remain stale after an update;
- `%USERPROFILE%\.codex` is a junction to another volume.

It is not intended for ordinary third-party plugin installation, non-Windows systems, or general website failures.

## Capabilities

- Read-only inspection by default.
- Detects lexical/canonical `CODEX_HOME` mismatches.
- Checks the `openai-bundled` configured and materialized paths.
- Compares SHA-256 hashes for the current AppX and relocated runtime.
- Can persist the correct canonical `CODEX_HOME`.
- Can repair only the bundled-marketplace section in `config.toml`.
- Backs up and replaces only runtime files that have drifted.
- Avoids pointing a modern reserved marketplace at an `openai-bundled-fixed` copy.
- Reports compact diagnostic facts without dumping private configuration.

## Installation

Clone the repository into the Codex Skills directory:

```powershell
git clone <repository-url> "$env:CODEX_HOME\skills\codex-windows-bundled-plugin-repair"
```

If `CODEX_HOME` is not set:

```powershell
git clone <repository-url> "$env:USERPROFILE\.codex\skills\codex-windows-bundled-plugin-repair"
```

Reopen Codex, then describe the failure naturally or invoke the skill explicitly:

```text
$codex-windows-bundled-plugin-repair
```

## Usage

Start with read-only inspection:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly
```

For structured output:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly -Json
```

Choose the narrowest repair supported by the findings:

```powershell
# Fix a junction/canonical-path mismatch
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairCodexHome

# Repair a stale openai-bundled config source
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairMarketplaceSource

# Fully exit Codex first, then repair runtime drift
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairRuntimeDrift
```

See [Diagnosis and Repair Method](references/diagnosis-and-repair.md) for the full decision process and stopping condition.

## Safety boundaries

- Inspect first and obtain authorization for the specific mutation.
- Never modify `WindowsApps` ACLs or ownership.
- Never delete the whole Codex data directory.
- Never stop Codex automatically.
- Never print complete config, logs, task history, or authentication data.
- Back up only files and environment values that will be changed.

## Validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\Test-CodexBundledPluginRepair.ps1"
conda run -n codex-base python "<skill-creator>\scripts\quick_validate.py" .
conda run -n codex-base python "<open-source-skill-publisher>\scripts\scan_release_safety.py" .
```

## License

[MIT](LICENSE)
