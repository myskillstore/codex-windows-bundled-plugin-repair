# Failure Patterns

Use these patterns to classify evidence after the standard inspection.

## Bundled plugins disappear together

Strong signal: Browser, Chrome, Computer Use, Sites, and Visualize disappear at the same time.

Likely causes:

- `openai-bundled` failed to register;
- the configured marketplace source is stale or outside the accepted Codex home;
- lexical and canonical `CODEX_HOME` paths disagree.

Do not repair each plugin independently until the marketplace itself is healthy.

## Reserved marketplace rejection

Representative message:

```text
marketplace `openai-bundled` is reserved and cannot be added from this source
```

Compare the backend's active Codex home with the source submitted by the desktop app. On Windows, a directory junction can make two paths reach the same files while still failing a lexical or policy check.

Preferred repair order:

1. persist the canonical `CODEX_HOME`;
2. correct an existing stale marketplace source only if necessary;
3. restart Codex and let the desktop app reconcile its bundled marketplace.

## Installed but runtime unavailable

If plugin state is healthy but Browser or Computer Use cannot initialize, compare AppX and relocated-runtime hashes for:

- `codex.exe`;
- `codex-code-mode-host.exe`;
- `node.exe`;
- `node_repl.exe`;
- `codex-command-runner.exe`;
- `codex-windows-sandbox-setup.exe`.

Also verify the current bundled `browser-client.mjs` hash is trusted when the corresponding config key exists.

## Command runs but its result fails IPC decoding

Representative message:

```text
failed to decode code-mode IPC frame: missing field `code_mode_host_duration_ns`
```

This can occur when the desktop AppX package is newer than the relocated `%LOCALAPPDATA%\OpenAI\Codex\bin\codex-code-mode-host.exe`. The command may already have executed; the failure occurs while the desktop app decodes the host's result frame.

Compare the AppX and relocated host by SHA-256. Do not rely on `FileVersion`, which may be empty. If they differ, classify it as runtime drift, fully exit Codex, and use `-RepairRuntimeDrift`. After restarting, verify both `-InspectOnly` and one minimal shell command.

## Missing client script

Required content in the current versioned cache normally includes:

```text
browser\<version>\scripts\browser-client.mjs
chrome\<version>\scripts\browser-client.mjs
computer-use\<version>\skills\computer-use\SKILL.md
```

Use the current bundled plugin version from the AppX package as the reference. Some releases still maintain `latest`, while others consume the versioned cache directly; do not treat `latest` as mandatory without current-version evidence.

## Chrome alone is unavailable

When Browser works but Chrome does not, inspect the Chrome extension and native messaging host rather than rewriting the entire bundled marketplace. Registry or extension repair is a separate mutation and requires explicit authorization.

## Runtime files are locked

Do not force replacement from inside the running Codex task. Ask the user to fully exit Codex, verify that its processes have stopped, and run the narrow runtime repair from PowerShell.

## Evidence hygiene

Search logs for exact error terms, but never print whole task records, configuration files, cookies, tokens, or global-state JSON. Report only the minimal matched diagnostic fields.
