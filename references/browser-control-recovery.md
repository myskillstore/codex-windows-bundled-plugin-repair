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

## Browser-object inventory fallback

Use this fallback when a page is visibly open but `cua.getState()` or `cua.listTabs()` times out, returns `nodeRepl.fetch request failed`, returns an empty or incomplete inventory, or a top-level `cua.getTab({ url })` lookup reports that the tab was not found. These failures can belong to the top-level adapter while the browser-scoped API remains healthy.

1. Select the expected browser without opening a tab. For an in-app Browser target with a known URL, use the current API equivalent of:

   ```javascript
   let browser = await cua.getBrowser({ url: targetUrl });
   ```

   Respect an explicitly selected browser. Use the browser ID returned by the current documentation rather than assuming that the string `"iab"` is the active browser ID.

2. Enumerate tabs through the selected browser object:

   ```javascript
   let tabs = await browser.tabs.list();
   ```

3. Match the target from the returned `id`, `providerTabId`, `title`, and normalized URL. If exactly one match exists, bind it through the browser object:

   ```javascript
   let tab = await browser.tabs.get(match.id);
   ```

4. Verify the recovered handle with the browser-scoped API:

   ```javascript
   let evidence = {
     id: tab.id,
     url: await tab.url(),
     title: await tab.title(),
     dom: (await tab.playwright.domSnapshot()).slice(0, 1200),
   };
   ```

   A matching URL/title plus page-specific DOM or screenshot evidence is sufficient. Do not perform extra interactions merely to prove control.

5. If inventory confirms that the target does not exist, create one tab with `browser.tabs.new()` and navigate it once. If creation or navigation times out after a visible page appears, treat the result as ambiguous: reset the CUA session once, reacquire the browser using the required first-call entry point, and repeat `browser.tabs.list()` before creating anything else.

6. Call `tab.markDeliverable()` only when the user wants the page to remain available after the turn. Otherwise preserve the normal temporary-tab lifecycle.

## Classification after recovery attempts

| Evidence | Classification | Next action |
| --- | --- | --- |
| Top-level inventory fails, browser-object inventory lists the tab, and `browser.tabs.get(id)` succeeds | Top-level adapter failure with healthy browser-scoped control | Continue through the recovered handle; no plugin repair |
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
