# Diagnosis and Repair Method

## Package registration and elevation boundary

If a Desktop update reports `0x80073D28` requiring administrator privileges for a packaged `windows.service` (possibly wrapped in `0x80073CF6`), resolve package registration first, preferably through `codex-windows-update-repair` when installed. Hand off one explicitly authorized elevated registration attempt from a standalone terminal under the same Windows account. This does not make routine plugin inspection or user-scoped runtime/config/environment repair require Administrator. Do not switch users, self-elevate, alter WindowsApps ACLs, or treat sandbox/browser permission denial as plugin corruption. After successful registration, recheck AppX version, runtime hashes, and fresh-task browser control before claiming recovery.

Read this reference before changing Codex Desktop state.

## 1. Establish the active paths

Determine all of the following independently:

- the lexical default data path: `%USERPROFILE%\.codex`;
- the user-level `CODEX_HOME` value;
- the canonical path after resolving a junction or symbolic link;
- the newest installed `OpenAI.Codex` AppX package;
- the active relocated runtime under `%LOCALAPPDATA%\OpenAI\Codex\bin`;
- the AppX and relocated copies of `codex-code-mode-host.exe`;
- the materialized bundled marketplace under `<CODEX_HOME>\.tmp\bundled-marketplaces\openai-bundled`.

Do not assume two paths are equivalent merely because Windows Explorer reaches the same files through both. Newer Codex plugin validation can compare a reserved marketplace against the active Codex home before accepting it.

## 2. Inspect before repairing

If the browser page is visibly open and only automation control is failing, first follow [browser-control-recovery.md](browser-control-recovery.md). That workflow is read-only and can recover a stale tab handle without changing the Codex installation. Run the inspection below when the browser surface is absent, reattachment remains broken in a fresh task, or evidence points to marketplace/runtime drift.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly
```

Use `-Json` when structured output is useful:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly -Json
```

The inspection is intentionally local and read-only. It does not dump the contents of `config.toml`, global state, task history, or logs.

For post-update inspection before Desktop starts, add `-SkipCliInspection -Json`. This skips both CLI plugin-list commands; `Marketplace.CliInspectionSkipped` is true and `CliListsBundledMarketplace` is null. File hashes, existing paths, and manifests remain available. Missing materialized caches before startup are not proof of plugin failure. The update skill can orchestrate inspection, authorized runtime-only synchronization, and an independent second inspection; only configured relocated-runtime drift is automatically eligible. Do not use `-RepairAll` as an update hook. Repair reports now rehash destinations after synchronization, but always run a separate inspection as the final gate.

## 3. Repair a CODEX_HOME canonical-path mismatch

Typical evidence:

- `%USERPROFILE%\.codex` is a junction to another path;
- user-level `CODEX_HOME` is unset or names the lexical junction;
- the materialized marketplace resolves under the junction target;
- the app reports that `openai-bundled` is reserved and cannot be added from the submitted source.

After authorization, run:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairCodexHome
```

This persists the canonical path as the user-level `CODEX_HOME`. It does not move the data directory. Fully exit and reopen Codex so the new environment reaches all processes.

## 4. Repair a stale bundled-marketplace source

Only use this repair when the valid materialized marketplace exists at:

```text
<CODEX_HOME>\.tmp\bundled-marketplaces\openai-bundled\.agents\plugins\marketplace.json
```

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairMarketplaceSource
```

The script backs up `config.toml` and changes only the `marketplaces.openai-bundled` section. It does not recreate the marketplace from arbitrary content.

Do not point a modern Codex installation at a permanent `openai-bundled-fixed` copy unless current-version evidence proves that compatibility path is required. A reserved marketplace can reject such a source and make all bundled plugins disappear from the UI.

## 5. Repair runtime drift

Typical evidence:

- one or more hashes differ between the current AppX resources and `%LOCALAPPDATA%\OpenAI\Codex\bin`;
- Browser or Computer Use setup fails even though the plugins are installed;
- `node_repl`, the command runner, or the Windows sandbox setup helper is missing or stale after an update.
- a shell command visibly executes or produces output, but the tool result fails to decode because a field such as `code_mode_host_duration_ns` is missing.

The runtime comparison must include `codex-code-mode-host.exe`. Its AppX source is normally `app\resources\codex-code-mode-host.exe`, and its relocated destination is `%LOCALAPPDATA%\OpenAI\Codex\bin\codex-code-mode-host.exe`. Compare SHA-256 hashes rather than file versions because these binaries may not expose Windows version metadata.

Fully exit Codex first, then run from a separate PowerShell window:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairRuntimeDrift
```

The script refuses to replace runtime files while Codex processes are active. It backs up and replaces only mismatched files, then updates related user environment variables and existing runtime keys in `config.toml`.

## 6. Combined repair

Use only when inspection supports all repair classes and the user authorizes them:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -RepairAll
```

## 7. Verification and stopping condition

After restart:

1. Repeat `-InspectOnly` and confirm the path and hash checks are healthy.
2. Confirm `browser@openai-bundled`, `chrome@openai-bundled`, and `computer-use@openai-bundled` are installed and enabled when available for the current account/build.
3. Open a fresh Codex task because an existing task's capability catalog can remain stale.
4. If explicitly requested, open a harmless page with Browser and report its title and URL.
   If a page is already visible, enumerate and reattach that tab before creating another one; verify DOM or screenshot before attempting a harmless interaction.
5. Run one minimal shell command and confirm its result returns normally without a code-mode IPC decode error.

Stop after two repair-and-restart cycles with the same failure. Preserve the latest small backup and report the exact remaining evidence rather than broadening the mutation scope.

## Backups

Backups are written under:

```text
<CODEX_HOME>\backups\bundled-plugin-repair-<timestamp>
```

Only changed configuration, prior environment values, and mismatched runtime files are included. Never back up the entire plugin cache by default.
