# Weekly Research Scan — 2026-03-29

Repos monitored: **OpenOats**, **QMD**, **AppFlowy**
Period: March 22–29, 2026

---

## 1. OpenOats (yazinsai/OpenOats)

> Native macOS (Swift/SwiftUI) meeting note-taker with on-device WhisperKit transcription, local knowledge-base search via embeddings, and LLM-powered suggestions. 2.1k stars, MIT.

### Activity: Very High (33 commits, 13 merged PRs, 13 issues closed)

| PR | What shipped | Why it matters |
|----|-------------|----------------|
| #228 | **Sidecast** — multi-persona AI sidebar with intensity control, dedup, evidence gating | Novel UX for surfacing multiple AI perspectives simultaneously |
| #208 | **Real-time suggestion engine** — replaced 5-stage serial pipeline with 3-layer concurrent architecture (pre-fetch cache → local heuristic gate → streaming LLM). Sub-2s latency | Gold-standard pattern for "AI while you write" |
| #200 | **Granola import** — paginated fetch, speaker mapping, tag-based duplicate detection, Keychain credentials | Clean data-migration pattern with idempotent re-import |
| #210 | **Tabbed settings** — 16-section scroll → 5 native macOS tabs | Good SwiftUI settings reference as feature count grows |
| #224 | Model download progress (speed, size, ETA) | Polish detail for on-device model UX |
| #223 | Auto-discover Ollama models in settings | Pluggable local-LLM provider pattern |
| #205 | Webhook on meeting end | Lightweight extensibility without a plugin system |
| #191 | Auto-stop recording when meeting app exits | Smart lifecycle management |

### Patterns worth adapting for Bugbook

| Pattern | Detail | Effort | Impact |
|---------|--------|--------|--------|
| **Markdown chunking + incremental embedding** | Chunk by heading (80–500 words), prepend header breadcrumb, hash-based change detection, cache embeddings locally. Only re-embed changed files. | Med | High |
| **Pluggable LLM provider** | Common interface over OpenRouter (cloud) and Ollama (local). "Bring your own model" is table-stakes. | Med | High |
| **3-layer suggestion architecture** | Pre-fetch KB cache → local heuristic gate → streaming LLM synthesis. Avoids unnecessary LLM calls. | High | High |
| **Tag-based import dedup** | `source:"granola"` + `granola:{noteId}` tags for idempotent re-import. Works for any import source (Apple Notes, Bear, Obsidian). | Low | Med |
| **Tabbed settings (SwiftUI)** | Native `TabView` with 5 categories. Copy-paste-ready pattern. | Low | Med |

---

## 2. QMD (tobi/qmd)

> On-device hybrid search engine for markdown files. Combines BM25 (SQLite FTS5), vector similarity (sqlite-vec), and LLM reranking — all local via node-llama-cpp with GGUF models. 17.2k stars, MIT. By Tobi Lütke.

### Activity: Very High (10 merged PRs, 6+ new issues, active RFCs)

| PR | What shipped | Why it matters |
|----|-------------|----------------|
| #455 | **50× FTS5 speedup** — CTE wrapper prevents query planner from abandoning the FTS index when collection filters are present (19.8s → 0.4s) | Critical SQLite gotcha; directly applicable |
| #449 | **AST-aware chunking** via tree-sitter for code files | Respects code structure during chunking |
| #463 | Fix hyphenated token handling in FTS5 lex queries | Edge-case fix worth knowing about |
| #462 | Fix BM25 field weights to include all 3 FTS columns | Correct weighting = better ranking |
| #478 | Add `rerank` parameter to MCP query tool | MCP integration getting richer |
| #456 | Handle `vec0 OR REPLACE` limitation | sqlite-vec compatibility fix |

**Notable open PRs:** #484 Symbol extraction (Phase 2), #480 Remote OpenAI-compatible embeddings, #470 `qmd bench` for search quality benchmarks, #469 REST search endpoints.

**Notable issues:** #481 Feature request for knowledge-graph support, #483 Vector search unstable on Apple Silicon.

### Patterns worth adapting for Bugbook

| Pattern | Detail | Effort | Impact |
|---------|--------|--------|--------|
| **CTE trick for FTS5 + filters** | Wrap FTS MATCH in a CTE, then JOIN/filter. Without this, SQLite abandons the FTS index. 50× difference. | **Low** | **High** |
| **Hybrid search pipeline** | BM25 → vector similarity → LLM rerank. Each stage is optional. Clean `searchFTS() → searchVec() → rerank()` pipeline. | Med | High |
| **Scored break-point chunking** | Headings scored 100/90/80…, code fences, horizontal rules, paragraph boundaries. `findBestCutoff()` picks optimal splits within token budget (900 tokens, 15% overlap). | Med | High |
| **Content-addressable storage** | SHA256 hash as key, deduplicates content, trivial change detection. | **Low** | Med |
| **MCP server exposure** | Expose search as MCP tools (`query`, `get`, `multi_get`, `list_collections`). Makes the app accessible to Claude Desktop, Cursor, etc. | Med | High |
| **Collection context metadata** | Per-folder semantic hints (e.g., "these are engineering meeting notes") injected into search/embedding without modifying notes. | **Low** | Med |
| **LLM query expansion (HyDE)** | Generate hypothetical answer, search for documents similar to it. Also generates lex/vec query variants. | Med | Med |
| **Virtual path URIs** | `qmd://collection/path` — stable, location-independent document references. Enables deep linking and stable backlinks. | **Low** | Med |
| **Index health monitoring** | `{needsEmbedding, totalDocs, daysStale}` — simple signal for "your search is out of date". | **Low** | Low–Med |

---

## 3. AppFlowy (AppFlowy-IO/AppFlowy)

> Open-source AI-powered collaborative workspace (Flutter + Rust), 68.9k stars. Notion alternative emphasizing data privacy and local-first architecture.

### Activity: Moderate (v0.11.5 released March 26)

**v0.11.5 highlights:**
- AI Meeting Transcript — paste YouTube link → transcript
- Database bulk edit optimization
- Mobile: database embedded views support Feed and List views
- Fixes: shortcut conflicts, plus-menu insertion, filter evaluation

**Notable new issue:** #8599 — CLI Interface for Local AI Agent Integration & Headless Operations (proposes using the existing Rust `flowy-core` event dispatch to enable CLI/agent CRUD on workspaces).

### Patterns worth adapting for Bugbook

| Pattern | Detail | Effort | Impact |
|---------|--------|--------|--------|
| **Slash command menu** | "/" opens a filtered list of block types, AI actions, and formatting. Redesigned in v0.11.4 for discoverability. Straightforward in SwiftUI (filtered list overlay). | **Low** | **High** |
| **CRDT-based local-first sync** | Yrs (Yjs Rust port) wrapped in a `Collab` abstraction with plugin system: disk persistence, cloud sync, snapshot as separate plugins. Dual storage: SQLite for metadata, CollabKVDB for content. | Med | High |
| **In-editor AI text actions** | Select text → write/edit/translate/improve. Pre-built + custom prompts loaded from database pages (prompts-as-data). | **Low** | Med |
| **RAG search over workspace** | Natural language queries returning results with source links + AI-generated overview. | Med | High |
| **Event-dispatch / FFI architecture** | Flutter ↔ Rust via Protobuf event dispatch. Enables the proposed CLI (#8599) — same backend serves GUI and CLI. Swift equivalent via UniFFI. | Med | High |
| **Block-component-builder plugin system** | 22+ content types registered via builders. Toolbar items, shortcuts, slash commands, context menus are all separate extension points. | High | High |
| **Notification center** | In-app hub for mentions, reminders, backlink activity. Good for surfacing stale notes and pending tasks. | Low | Med |
| **Custom AI prompts as data** | Users define reusable AI workflows as database pages, not code. Clever for power users. | Low | Med |

---

## Top 3 This Week

The three highest-impact, lowest-effort items to act on first:

### 1. FTS5 CTE Query Pattern (from QMD #455)
**Effort: Low | Impact: High**
Wrap any FTS5 MATCH query in a CTE before applying additional WHERE filters. Without this, SQLite's query planner silently abandons the full-text index, causing 50× slowdowns. This is a one-line SQL restructure that applies immediately to Bugbook's existing search layer. No new dependencies.

### 2. Slash Command Menu (from AppFlowy v0.11.4)
**Effort: Low | Impact: High**
A "/" command menu is the standard interaction pattern for block-based editors. In SwiftUI, it's a filtered list overlay triggered by a single character. It provides a discoverable entry point for block insertion, formatting, and (eventually) AI actions. Implement now; extend later.

### 3. Content-Addressable Storage + Incremental Embedding Cache (from QMD + OpenOats)
**Effort: Low | Impact: High**
Both QMD and OpenOats independently converged on the same pattern: SHA256-hash documents, only re-process changed content. QMD uses it for dedup and change detection in the search index; OpenOats uses it for incremental embedding. This is the foundation for any local semantic search — get it in early so the embedding/indexing pipeline scales from day one.
