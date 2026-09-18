---
name: codex-windows-bundled-plugin-repair
description: Diagnose and safely repair Codex Desktop on Windows when bundled Browser, Chrome, Computer Use, or other openai-bundled plugins disappear, fail to load, cannot reattach to a visible browser tab, or break after an app update, runtime relocation, CODEX_HOME junction/path mismatch, or code-mode IPC schema mismatch. Do not use for ordinary third-party plugin installation or non-Windows systems.
---

# Codex Windows Bundled Plugin Repair

Restore the current Codex Desktop bundle without resetting unrelated user state.

## Non-negotiable gates

- A Desktop update failing with packaged-service error `0x80073D28` is a package-registration problem, not evidence of bundled-plugin corruption. Route it to `codex-windows-update-repair` when available; see the diagnosis reference for the elevation boundary. Do not use `-RepairAll`, alter ACLs, or require elevation for routine user-scoped inspection/runtime repair on this evidence alone.

- Start with read-only inspection. Run `scripts/Repair-CodexBundledPlugins.ps1 -InspectOnly` before proposing a mutation.
- Treat the newest installed `OpenAI.Codex` AppX package as the source of truth for bundled plugins and runtime binaries.
- Include `codex-code-mode-host.exe` in runtime drift checks. A stale copy can execute a command but fail while returning its result, for example with a missing `code_mode_host_duration_ns` field.
- Resolve both the lexical and canonical `CODEX_HOME` paths. A junction that resolves to another drive can make the reserved `openai-bundled` marketplace reject its own materialized source.
- Never change ownership or ACLs under `WindowsApps`, delete the whole Codex data directory, or overwrite unrelated configuration.
- Before any mutation, read [references/diagnosis-and-repair.md](references/diagnosis-and-repair.md). Back up only files that will change.
- Obtain user authorization immediately before changing user environment variables, `config.toml`, runtime executables, registry entries, or running processes. A request to diagnose is not repair authorization.
- Do not stop Codex automatically. If runtime files are locked, ask the user to fully exit Codex and run the repair command from PowerShell.
- A visible browser page does not prove that its automation handle is attached. When the page is visible but control calls time out, read [references/browser-control-recovery.md](references/browser-control-recovery.md) and attempt the non-mutating reattachment workflow before classifying the bundled plugin as broken or proposing a repair.

## Workflow

1. Classify what failed. If a browser page is already visible but cannot be controlled, use the reattachment workflow first. Otherwise run inspection:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Repair-CodexBundledPlugins.ps1" -InspectOnly
   ```

2. Explain the evidence and choose only the required repair flags:

   - `-RepairCodexHome`: persist the canonical Codex data path when an unset or junctioned path causes reserved-marketplace rejection.
   - `-RepairMarketplaceSource`: repair only the `openai-bundled` marketplace source in `config.toml`; require a valid materialized marketplace.
   - `-RepairRuntimeDrift`: copy only mismatched runtime files from the current AppX package and update related existing config/environment entries.
   - `-RepairAll`: combine the three repairs after the user authorizes all of them.

3. Restart Codex Desktop after a repair.

   For a pre-start update gate, use `-InspectOnly -SkipCliInspection -Json` to compare files without launching CLI or Desktop. `-RepairRuntimeDrift -SkipCliInspection` is compatible with the update skill's authorized synchronization workflow. Skipped CLI checks are unknown, not failed or verified; plugin materialization and browser connectivity still require a fresh task after startup.

4. Open a fresh task and verify that the Browser and Computer Use skills are present. When the user asks for an interaction test, use the current Browser or Computer Use entry point, enumerate tabs before creating another one, and verify URL/DOM before a harmless interaction; otherwise keep verification read-only.

## Interpretation

Do not treat `plugin list` alone as proof of success. Require agreement between:

- the canonical `CODEX_HOME` and the process/user environment;
- the current AppX bundle and relocated runtime hashes;
- the AppX and relocated `codex-code-mode-host.exe` hashes when command results fail IPC decoding;
- the configured and expected materialized `openai-bundled` paths;
- installed/enabled plugin state and the presence of required client scripts;
- a fresh Codex task's actual skill/tool catalog.

Read [references/failure-patterns.md](references/failure-patterns.md) when symptoms remain after the standard workflow or when logs contain reserved-marketplace, trust-hash, native-host, or runtime-startup errors.
