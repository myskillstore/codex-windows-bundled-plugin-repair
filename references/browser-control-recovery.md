# Visible Browser, Missing Control Handle

Use this reference when the user can see an in-app Browser or Chrome page, but Codex cannot inspect, attach to, or interact with it.

## Key distinction

Treat rendering and automation as separate states:

- **rendering state**: a browser window or tab exists and is visibly showing a page;
- **control state**: the current task has a valid browser surface and tab handle that can return URL, DOM, screenshots, logs, and interaction results.

A timed-out open/create call can be ambiguous: the desktop app may have completed the visible side effect even though the caller never received a usable handle. Do not create repeated duplicate tabs until the existing-tab inventory has been checked.

## Non-mutating recovery workflow

1. Ask or observe whether the target page is visibly open. Record its browser, title, and URL when available.
2. Initialize a fresh Computer Use/CUA session using exactly the current tool documentation's first-call entry point. Do not reuse a handle that already timed out.
3. Read the available browser surfaces and enumerate their existing tabs.
4. Match the target using all available identifiers: browser, URL, title, tab ID, and provider tab ID. Do not guess when multiple tabs are ambiguous.
5. Reattach to the matched existing tab using its current ID. Create a new tab only when the inventory confirms that the target does not exist.
6. Verify the handle read-only: read URL/title and a DOM snapshot or screenshot.
7. If the user requested an interaction test, perform one harmless action such as switching a local UI tab or filling a non-submitting search field. Confirm the resulting DOM state and review console errors.
8. If attachment still fails, reset the CUA session once and repeat steps 2–7. Then try a fresh Codex task because an existing task can retain a stale capability catalog or handle.

These steps do not authorize edits to `config.toml`, environment variables, runtime files, registry entries, extensions, or running processes.

## Classification after recovery attempts

| Evidence | Classification | Next action |
| --- | --- | --- |
| Page visible, tab listed, reattachment succeeds | Stale or lost task-local handle | Continue QA; no plugin repair |
| Page visible, tab listed, reattachment fails twice | Control-session or runtime binding failure | Open a fresh task; then run `-InspectOnly` if it persists |
| Page visible, tab absent from the expected browser inventory | Surface/provider inventory mismatch | Recheck selected browser, reset once, then restart Codex if needed |
| Browser surface or bundled skills absent | Bundled plugin registration/runtime failure | Continue with the standard `-InspectOnly` workflow |
| Inspection reports current paths and hashes healthy, but attachment still fails in a fresh task | Unclassified app/control defect | Stop mutation; preserve concise evidence and report the app/build boundary |

Do not treat a visible page alone as proof of control success, and do not treat a control timeout alone as proof that the browser failed to open.

## Evidence to preserve

Record only compact, non-sensitive facts:

- whether the page was visible;
- browser identity and target URL origin (omit sensitive query strings);
- whether the tab appeared in inventory;
- the attach/read/interaction step that failed;
- exact short timeout or schema error;
- whether a CUA reset, fresh task, or Codex restart changed the result;
- final DOM/screenshot/console verification when recovery succeeds.

Never dump cookies, tokens, full task records, complete logs, or browser storage.

## Stopping condition

After one CUA reset and one fresh-task retry, do not keep opening tabs or broadening mutations. If `-InspectOnly` is healthy, report the control defect without changing the installation. If inspection identifies a supported failure class, return to [diagnosis-and-repair.md](diagnosis-and-repair.md) and request authorization for only the indicated repair.
