# HTML Artifacts Upgrade Plan

Status: design complete, not yet implemented.

Adopt `.html` as a first-class **agentic output type** alongside markdown. Markdown + YAML frontmatter + `_schema.json`/`_index.json` remain the only canonical store; an artifact is a single self-contained `.html` file — a rendered, regenerable projection, never a source of truth. Delete an artifact and you lose nothing but pixels.

---

## 1. Motivation (evaluation findings)

1. **The markdown dialect is already straining toward HTML.** Toggles, columns, callouts, TOC, and meeting blocks are encoded as HTML comments (`<!-- toggle -->`, `<!-- columns -->`) in `.md` files, parsed by a ~1,400-line custom parser (`Sources/Bugbook/Lib/MarkdownBlockParser.swift`) and rendered by ~8,000 lines of native editor (`Sources/Bugbook/Views/Editor/`). Every new structured block re-invents a piece of HTML inside the dialect.
2. **The format constrains the agents.** The weekly-review skill (`plugins/bugbook/skills/wreview/SKILL.md`) reduces 7 days of Garmin time-series to "Numbers only — no daily breakdown, no trend commentary" because markdown cannot chart. `Sources/Bugbook/Services/AiService.swift` (~line 67) hard-codes "NEVER use HTML tags… This app does NOT render HTML." The data wants to be a sparkline; the format forces a sentence.
3. **HTML is the model's native rich format.** LLMs are maximally fluent in HTML (the web is the training corpus); the private markdown dialect must be taught per-skill and fails in ways HTML does not.
4. **The substrate already exists.** WKWebView is the default browser engine (`Sources/Bugbook/Services/WebKitBrowserEngine.swift`); `MailHTMLView` (`Sources/Bugbook/Views/Mail/MailPaneView.swift:888-941`) already renders HTML in a WKWebView. Pane routing is type-dispatched on `TabKind` (`Sources/Bugbook/Models/FileEntry.swift` → `ContentView.swift` `paneContentRouting()`), so a new artifact kind slots in cleanly. The FSEvents `WorkspaceWatcher` is format-agnostic.
5. **WKWebView is the only rich-rendering path that also works on iOS** (CEF cannot ship there), so artifacts render identically in BugbookMobile with a small `UIViewRepresentable`.

## 2. Decision and non-goals

**Hybrid model:** agents keep writing markdown as the source of truth and *additionally* emit `.html` artifacts for anything that benefits from interactivity, charts, or app-like UI. The markdown body always links to its artifacts — markdown remains the spine.

**Do not:**
- Make HTML canonical or dual-source any content — md is the greppable, diffable, human- and agent-editable, schema-queryable store; replacing it breaks section selectors, backlinks, search, row serialization, and the human-edit loop.
- Render the block editor in a web view — the native TextKit editor is the product's core; this adds a view substrate beside it, not a rewrite path.
- Build artifacts on CEF/Chromium — absent on iOS, heavyweight process model; WKWebView has `WKURLSchemeHandler` + content rule lists.
- Reuse the browser pane / `BrowserManager` for artifacts — that engine has full network and shared sessions by design; artifacts get a dedicated, locked-down configuration.
- Allow multi-file artifacts or asset folders in v1 — one self-contained file keeps the scheme handler single-resource, validation trivial, and sync atomic.

## 3. Capability ladder

- **Level 1 — static artifacts (build first, ships standalone):** self-contained `.html` (inline CSS/JS, embedded JSON data, zero network). File tree shows them; a sandboxed pane renders them. Unlocks charts, sortable/filterable tables, dashboards, progressive disclosure.
- **Level 2 — data-bound artifacts (read):** a `window.bugbook.query()` JS bridge into BugbookCore's `QueryEngine`, gated by a capability manifest, native consent UI, and an audit log. Artifacts become live, regenerable views over the local database — generative UI over a stable data layer.
- **Level 3 — interactive artifacts (write, sketched only):** scoped `updateRow`/`createRow` with per-action confirmation and undo. Triage boards, approve/reject panels for agent proposals, forms writing back to databases.

## 4. Design

### 4.1 On-disk model

`.html` files are admitted anywhere a `.md` can live. Two conventions (documented in the authoring skill, not enforced by code):

- **Page-attached:** in the page's companion folder — `Weekly Review.md` + `Weekly Review/sleep-trends.html` (companion-folder nesting in the sidebar comes free once `.html` is admitted).
- **Row-attached:** in `_artifacts/` inside the database folder — `Weekly Reviews/_artifacts/2026-W23-sleep.html`. Safe by construction: `RowStore.loadAllRows` filters `hasSuffix(".md") && !hasPrefix("_")` and the sidebar hides `_`-prefixed entries, so artifacts never pollute `_index.json` or row counts.

### 4.2 Artifact metadata (HTML has no YAML frontmatter)

Parsed natively with a bounded scan of the first 4 KB (regex, no HTML parser), shared in BugbookCore (`Sources/BugbookCore/Model/ArtifactManifest.swift`) so app, CLI, and iOS use one implementation.

```html
<meta name="bugbook-artifact" content="1">      <!-- marker + format version -->
<meta name="bugbook-title" content="Sleep Trends — 2026-W23">
<meta name="bugbook-icon" content="sf:bed.double">
<meta name="bugbook-generator" content="claude-code/wreview">

<!-- Level 2+ only; absent = pure static artifact -->
<script type="application/bugbook-manifest">
{ "manifestVersion": 1,
  "capabilities": { "query": ["Garmin Sleep", "Weekly Reviews"], "mutate": [] } }
</script>
```

The manifest is *requested* capabilities; the native user grant is the only authority, and granted scopes freeze at load time (page JS can never self-escalate).

### 4.3 Rendering (Level 1)

New `TabKind.artifact` case; routing branch in `paneContentRouting()`. New files:

- `Sources/Bugbook/Services/ArtifactSandbox.swift` — `WKWebViewConfiguration` factory:
  - **WKURLSchemeHandler** (not `loadHTMLString`, not `loadFileURL`): `bugbook-artifact://a/<UUID-token>` resolves to exactly one registered file; any sub-resource request fails. Real path never appears in `window.location`; no `file://` origin semantics; no directory read grants. Serves a real CSP response header:
    `default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-src 'none'`
  - **WKContentRuleList** blocking `^https?://` and `^wss?://` — enforced in the network process; the strongest kill switch.
  - `websiteDataStore = .nonPersistent()` (no cookies/localStorage persistence, isolated from the browser pane); no `window.open`; `isInspectable` in DEBUG only.
  - **Navigation delegate:** allow only the initial scheme load. Link-activated http(s) → native confirmation sheet showing the full URL → route to browser pane or system browser. Everything else cancelled.
- `Sources/Bugbook/Views/Artifacts/ArtifactWebView.swift` — `NSViewRepresentable` modeled on `MailHTMLView` but JS-enabled + sandbox config.
- `Sources/Bugbook/Views/Artifacts/ArtifactPaneView.swift` — pane chrome (title/icon from meta tags, reload, reveal in Finder, consent-banner slot for L2); FSEvents-driven reload (~300 ms debounce) so agent regeneration live-refreshes an open pane.

### 4.4 Bridge (Level 2, future)

```js
window.bugbook = {
  version: 1,
  query(db, {filters, sorts, limit})  -> Promise<{rows, schemaVersion}>,
  getRow(db, rowId)                   -> Promise<{row}>,
  schema(db)                          -> Promise<{properties, views}>,
  querySelf(opts)                     -> Promise<...>,   // when artifact is a schema html view
  // Level 3 sketch:
  updateRow(db, rowId, props)         -> Promise<{ok, undoToken}>,
  createRow(db, props, body)          -> Promise<{ok, rowId}>,
}
```

- Protocol: `WKScriptMessageHandlerWithReply` — `postMessage` returns a Promise natively, so no correlation layer. Injected user script (`.atDocumentStart`, main frame only) is ~10 lines.
- Native side: `ArtifactBridgeHandler` validates method+db against grants → off-main task → `DatabaseStore`/`RowStore` → `QueryEngine.execute` → JSON reply. Filter/sort JSON mirrors `FilterConfig`/`SortConfig` from `Sources/BugbookCore/Model/View.swift` — one vocabulary across schema views, CLI, and bridge. Guardrails: ≤4 concurrent calls/pane, ~256 calls/min, 2 MB response cap.
- Consent: native banner above the pane (never inside the webview — anti-spoofing): "This artifact wants to read: X, Y. [Allow] [Open without data] [Don't allow]". Grants persist in `<workspace>/.bugbook/artifact-grants.json` keyed by `relativePath + sha256(capability set)` — *not* content hash, since agents regenerate artifacts constantly; any capability-set change re-prompts. `mutate` grants are session-scoped and always re-prompt.
- Audit: append-only JSONL at `<workspace>/.bugbook/logs/artifact-bridge.jsonl` (denied calls included), surfaced in the pane footer.

### 4.5 Agent surface

- **CLI** — new `ArtifactCommand` (`bugbook artifact create | validate | list`). `validate` is the agent feedback loop: requires the `bugbook-artifact` meta marker; hard-errors on any external `https?://`/`wss?://` reference in `src/href/url()/import` ("inline it"); size warn >2 MB, error >10 MB; JSON errors, nonzero exit. `create` = write + validate (delete on failure) + print workspace-relative path and a suggested markdown link line.
- **MCP** — `bugbook_artifact_create(path, html)` + `bugbook_artifact_validate(path)` in `mcp-server/index.js`, thin CLI wrappers; tool descriptions state the self-contained rules so models see them at tool-selection time.
- **Skills** — new `plugins/bugbook/skills/artifact/SKILL.md` (the authoring contract: one self-contained file; zero network/CDN; embed data as `<script type="application/json" id="data">`; system font stack + `prefers-color-scheme`; meta title/icon; placement conventions; always link from the md body). Update `wreview` to optionally emit `_artifacts/<week>-health.html`. Reword `AiService.swift` ~67: HTML stays banned *in note content*; interactive HTML belongs in `.html` artifacts via the CLI.

## 5. Security model

Threat model: the artifact author is an agent that may be operating under prompt injection — treat every artifact as attacker-controlled code. The agent already reads/writes the whole workspace via CLI/MCP, so the sandbox defends the **rendering boundary**: exfiltration, escalation, persistence, phishing.

| # | Threat | Mitigation | Level |
|---|--------|-----------|-------|
| T1 | Network exfiltration (fetch/img/beacon/ws/form/meta-refresh) | Content rule list + CSP header + navigation deny + no `window.open` | L1 |
| T2 | Reading other workspace files | Scheme handler serves exactly one token-mapped resource; no `file://` origin | L1 |
| T3 | Bridge abuse / self-escalation | No handler installed without manifest+grant; scopes frozen at load; rate limits; audit incl. denials | L2 |
| T4 | Link phishing / data-in-URL exfil via user click | Mandatory native confirmation sheet with full URL; at L2+ the sheet notes what the artifact can read. Weakest link; audit trail is the realistic backstop | L1 |
| T5 | UI spoofing (fake consent chrome in-page) | All consent/confirmation is native chrome outside the webview | L2 |
| T6 | Cross-artifact persistence/XSS | `nonPersistent()` store + per-open token host → unstable origin | L1 |
| T7 | Resource abuse | WebKit's separate content process; teardown on pane close; bridge rate limits | L1/L2 |
| T8 | Escalation via regeneration of a granted artifact | Accepted residual at read level (agent already has read via CLI); capability-set change re-prompts; mutations session-scoped + per-action confirm + undo | L2/L3 |

Per-level guarantees — **L1:** a rendered artifact cannot reach the network, cannot read any file, cannot persist state, cannot navigate without explicit user confirmation. **L2:** additionally reads only user-granted databases through an audited, rate-limited channel whose scopes JS cannot modify. **L3:** additionally writes only granted properties; every write confirmed, undoable, audited.

## 6. Implementation steps — Level 1

| Step | What | Files | Size |
|---|---|---|---|
| 1 | `TabKind.artifact` + shims + pane title/icon | `Models/FileEntry.swift`, `Models/OpenFile.swift`, `Models/PaneContent.swift` | S |
| 2 | Admit `.html` in tree as `.artifact`; extension-aware companion-folder helper; migrate drag/rename/trash call sites | `Services/FileSystemService.swift` (~797-832), `Views/Sidebar/FileTreeView.swift` (~142), `ContentView.swift` companion paths | M |
| 3 | Sandbox + renderer (scheme handler, rule list, CSP, nav delegate, FSEvents reload, link-confirm sheet) | new `Services/ArtifactSandbox.swift`, new `Views/Artifacts/*`, new `BugbookCore/Model/ArtifactManifest.swift` | L — core |
| 4 | Route in `paneContentRouting()`; admit `.html` in internal links; skip block parsing for artifacts | `ContentView.swift` (~2169, ~4209), `Models/BlockDocument.swift` (~1627) | S |
| 5 | Escape-attempt fixture + sandbox/manifest tests — **do not skip** | `Tests/BugbookTests/Fixtures/hostile-artifact.html` + unit tests | M |
| 6 | CLI `artifact create/validate/list` | new `Sources/BugbookCLI/Commands/ArtifactCommand.swift`, register in `BugbookCLI.swift` | M |
| 7 | MCP tools | `mcp-server/index.js` | S |
| 8 | Authoring skill + wreview update + AiService reword | `plugins/bugbook/skills/artifact/SKILL.md` (new), `plugins/bugbook/skills/wreview/SKILL.md`, `Services/AiService.swift` | S |
| 9 | Demo artifacts (also skill reference examples) | `plugins/bugbook/skills/artifact/examples/health-dashboard.html`, `ticket-board.html` | M |

**Demo artifacts:**
- `health-dashboard.html` — 14 days of embedded sample JSON (sleep/deep/REM, resting HR, steps, stress, body battery); hand-rolled inline SVG charts; 7d/14d toggle; dark-mode aware. The thing wreview currently flattens to "numbers only".
- `ticket-board.html` — embedded snapshot of ~12 sample tickets; kanban grouped by status; client-side filter chips + search; drag visual-only with a "snapshot — write-back arrives with the Level 2 bridge" note.

**Riskiest parts:** (a) content-rule-list + CSP-header interaction with custom schemes must be verified empirically on current WebKit (hence step 5 early and mandatory); (b) the ~25 `hasSuffix(".md")` sites — rename/trash/companion flows need a focused audit; (c) `TabKind` Codable: old binaries can't decode sessions containing the new case (same accepted risk as past case additions).

## 7. Verification

1. `swift build && swift test && bash scripts/smoke-cli.sh`
2. `cd macos && xcodegen generate && xcodebuild -project Bugbook.xcodeproj -scheme BugbookApp -configuration Debug build`
3. CLI round-trip: `artifact create` a demo into a scratch workspace; `artifact validate` rejects a CDN-referencing file.
4. Run `swift run Bugbook` (WebKit path; no CEF needed) against a scratch workspace containing both demos + the hostile fixture: artifacts appear in the sidebar; charts/board render and interact; external link click → native confirmation sheet; hostile artifact reports every probe blocked; editing the artifact on disk live-reloads the open pane.
5. MCP smoke: call `bugbook_artifact_create` via node.

## 8. Future work

- **Level 2** (steps, in order): `ArtifactBridgeHandler` + injected user script; lift `PropertyValue`→JSON encoding from `Sources/BugbookCLI/Helpers.swift` into BugbookCore; consent banner + grants store; audit JSONL + pane footer.
- **Level 3:** mutation scopes through `MutationEngine`, per-action confirm + undo journal, `proposeMutation()` always-confirm sheet. Spec after L2 usage data.
- `_schema.json` `views` gains `{"type": "html", "artifactPath": …}` (make `ViewType` decoding tolerant in the same change); inline `<!-- artifact: ./path.html -->` embed blocks in the editor (WKWebView-inside-NSTextView is the riskiest UI work — keep quarantined); iOS rendering via a small `UIViewRepresentable` (scheme handler + rule lists port cleanly).
