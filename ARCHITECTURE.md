# Bugbook Swift — Database Architecture

Local-first database engine. Agent-editable via CLI + skills. Human-readable files on disk. Notion-like database UI on the frontend.

## Project Structure

```
bugbook/
  Package.swift

  Sources/
    BugbookCore/              # shared library — everything depends on this
      Model/
        Schema.swift           # DatabaseSchema, PropertyDefinition, PropertyType
        Row.swift              # DatabaseRow, PropertyValue enum
        Query.swift            # Filter, Sort, Pagination types
        View.swift             # ViewConfig, ViewType (table/kanban/calendar/list)
        Agent.swift            # AgentTask, AgentRun, AgentEvent models

      Storage/
        DatabaseStore.swift    # discover databases, load/save schemas
        RowStore.swift         # read/write row .md files, atomic writes
        IndexManager.swift     # load/rebuild/patch _index.json with reverse indexes
        RowSerializer.swift    # YAML frontmatter <-> Row parsing
        AgentWorkspaceStore.swift # task/run/event files in workspace

      Engine/
        QueryEngine.swift      # filter + sort against index, pagination
        MutationEngine.swift   # validate -> write rows -> patch index (batch)
        RelationResolver.swift # cross-database relation lookups
        SchemaValidator.swift  # type-check values against property defs

    BugbookCLI/               # executable
      main.swift
      Commands/
        DBCommand.swift        # db list, db schema, db create
        QueryCommand.swift     # query <db> --filter --sort --limit
        GetCommand.swift       # get <db> <row_id> --body
        CreateCommand.swift    # create <db> --set k=v
        UpdateCommand.swift    # update <db> <row_id> --set k=v
        DeleteCommand.swift    # delete <db> <row_id>
        BatchCommand.swift     # batch <db> < operations.json
        AgentCommand.swift     # agent task/run/event/dashboard commands

    Bugbook/                  # macOS SwiftUI app (desktop)
      App/
      Views/
      ViewModels/

    BugbookMobile/            # lightweight iPhone-first SwiftUI app
      App/
      Views/
      ViewModels/
      Services/

  skills/
    bugbook.md               # skill prompt teaching agents the CLI
```

---

## On-Disk Format

```
~/Bugbook/                    # workspace root (configurable)
  bugbook.json                # workspace config: { "version": 1 }
  AGENTS.md                   # optional workspace instructions for coding agents
  .bugbook/
    agents/
      tasks.json              # canonical task list (JSON)
      runs.jsonl              # run history (JSON Lines)
      events.jsonl            # event/log history (JSON Lines)
  pages/
    My Note.md                # regular markdown pages
    My Note/                  # companion folder
      Tasks/                  # database (identified by _schema.json)
        _schema.json
        _index.json
        Fix auth bug (a1b2c3).md
        Add tests (d4e5f6).md
  databases/
    Projects/                 # top-level databases not owned by a page
      _schema.json
      _index.json
      ...
```

A folder is a database if and only if it contains `_schema.json`. No external registry.

## Agent Ops Layer

Agent collaboration is persisted as plain files in `.bugbook/agents`:

- `tasks.json` is the editable source of truth for agent tasks.
- `runs.jsonl` tracks each execution run (`start`/`finish`).
- `events.jsonl` records progress logs tied to runs/tasks.

CLI surface:

- `bugbook agent init` to bootstrap files.
- `bugbook agent task ...` for task lifecycle.
- `bugbook agent run ...` for run lifecycle.
- `bugbook agent event ...` for structured logs.
- `bugbook agent dashboard` for a unified status view.

UI surface:

- Desktop app has an **Agent Hub** page in the sidebar.
- Mobile app has an **Agent Hub** tab for iPhone workflows.

### _schema.json

Pure JSON. No markdown wrapper.

```json
{
  "id": "db_tasks",
  "name": "Tasks",
  "version": 1,
  "properties": [
    { "id": "prop_title", "name": "Title", "type": "title" },
    { "id": "prop_status", "name": "Status", "type": "select",
      "config": {
        "options": [
          { "id": "opt_backlog", "name": "Backlog", "color": "gray" },
          { "id": "opt_todo", "name": "Todo", "color": "blue" },
          { "id": "opt_doing", "name": "In Progress", "color": "yellow" },
          { "id": "opt_done", "name": "Done", "color": "green" },
          { "id": "opt_cancelled", "name": "Cancelled", "color": "red" }
        ]
      }
    },
    { "id": "prop_priority", "name": "Priority", "type": "select",
      "config": {
        "options": [
          { "id": "opt_urgent", "name": "Urgent", "color": "red" },
          { "id": "opt_high", "name": "High", "color": "orange" },
          { "id": "opt_medium", "name": "Medium", "color": "yellow" },
          { "id": "opt_low", "name": "Low", "color": "gray" }
        ]
      }
    },
    { "id": "prop_assignee", "name": "Assignee", "type": "text" },
    { "id": "prop_project", "name": "Project", "type": "relation",
      "config": { "target": "db_projects", "cardinality": "many_to_one" }
    },
    { "id": "prop_blocks", "name": "Blocks", "type": "relation",
      "config": { "target": "db_tasks", "cardinality": "many_to_many" }
    },
    { "id": "prop_due", "name": "Due Date", "type": "date" },
    { "id": "prop_estimate", "name": "Estimate", "type": "number",
      "config": { "format": "number" }
    },
    { "id": "prop_done", "name": "Completed", "type": "checkbox" },
    { "id": "prop_tags", "name": "Tags", "type": "multi_select",
      "config": {
        "options": [
          { "id": "opt_bug", "name": "bug", "color": "red" },
          { "id": "opt_feature", "name": "feature", "color": "purple" }
        ]
      }
    }
  ],
  "views": [
    { "id": "view_table", "name": "All Tasks", "type": "table",
      "sorts": [], "filters": [],
      "column_widths": {}, "hidden_columns": [] },
    { "id": "view_board", "name": "Board", "type": "kanban",
      "group_by": "prop_status",
      "sorts": [{ "property": "prop_priority", "direction": "asc" }],
      "filters": [{ "property": "prop_status", "op": "not_equals", "value": "opt_cancelled" }] },
    { "id": "view_calendar", "name": "Calendar", "type": "calendar",
      "date_property": "prop_due", "sorts": [], "filters": [] }
  ],
  "default_view": "view_table",
  "created_at": "2026-02-20T10:00:00Z"
}
```

### _index.json

Contains flat row metadata (no bodies) plus reverse indexes for discrete-value properties.

```json
{
  "version": 1,
  "updated_at": "2026-02-23T14:00:00Z",
  "rows": {
    "row_a1b2c3": {
      "properties": {
        "prop_title": "Fix auth bug",
        "prop_status": "opt_doing",
        "prop_priority": "opt_high",
        "prop_project": "row_proj_001",
        "prop_blocks": ["row_xyz"],
        "prop_due": "2026-03-01",
        "prop_estimate": 3,
        "prop_done": false,
        "prop_tags": ["opt_bug"]
      },
      "created_at": "2026-02-20T10:00:00Z",
      "updated_at": "2026-02-23T14:00:00Z",
      "filename": "Fix auth bug (a1b2c3)",
      "mtime": 1708700000000
    }
  },
  "indexes": {
    "prop_status": {
      "opt_doing": ["row_a1b2c3"],
      "opt_todo": ["row_d4e5f6"]
    },
    "prop_priority": {
      "opt_high": ["row_a1b2c3"],
      "opt_medium": ["row_d4e5f6"]
    },
    "prop_project": {
      "row_proj_001": ["row_a1b2c3"]
    },
    "prop_tags": {
      "opt_bug": ["row_a1b2c3"]
    }
  }
}
```

**Indexed property types:** `select`, `multi_select`, `relation`, `checkbox`. These get reverse indexes for O(1) filtered lookups.

**Non-indexed types:** `text`, `number`, `date`. Scanned against the flat `rows` map (fast enough — it's in-memory JSON, not file reads).

**Staleness detection:** Compare file mtimes in the index against actual file mtimes on disk. If any differ or row count doesn't match, rebuild.

### Row File Example

`Fix auth bug (a1b2c3).md`:

```markdown
---
id: row_a1b2c3
created_at: 2026-02-20T10:00:00Z
updated_at: 2026-02-23T14:00:00Z
properties:
  prop_title: "Fix auth bug"
  prop_status: opt_doing
  prop_priority: opt_high
  prop_assignee: max
  prop_project: row_proj_001
  prop_blocks: [row_xyz]
  prop_due: 2026-03-01
  prop_estimate: 3
  prop_done: false
  prop_tags: [opt_bug]
---

## Root Cause

The token refresh logic doesn't handle expired refresh tokens.
When the access token expires and the refresh token is also expired,
the user gets a silent failure instead of a redirect to login.

## Fix

Check refresh token expiry before attempting refresh.
If expired, clear session and redirect.
```

Row filenames: sanitized title + 6-char ID suffix for uniqueness. Body is a full markdown document, loaded lazily (only when the row is opened).

---

## Property Types

| Type | Value Format | Stored As | Indexed |
|------|-------------|-----------|---------|
| `title` | string | `"Fix auth bug"` | No (scan) |
| `text` | string | `"max"` | No (scan) |
| `number` | number | `3` | No (scan) |
| `select` | option ID | `"opt_doing"` | Yes |
| `multi_select` | option ID array | `["opt_bug"]` | Yes |
| `date` | YYYY-MM-DD | `"2026-03-01"` | No (scan) |
| `checkbox` | boolean | `true` / `false` | Yes |
| `url` | string | `"https://..."` | No |
| `email` | string | `"user@..."` | No |
| `relation` | row ID or array | `"row_proj_001"` or `["row_x"]` | Yes |

`title` is its own type (not just the first text property) so queries can unambiguously identify the display name.

Relations store row IDs. Resolution (getting the related row's properties) happens at query time via `RelationResolver`.

---

## Core Library — BugbookCore

### DatabaseStore

Discovers and manages databases in the workspace.

```swift
class DatabaseStore {
    let workspacePath: URL

    func listDatabases() -> [DatabaseInfo]          // scan for _schema.json
    func loadSchema(databaseId: String) -> DatabaseSchema
    func saveSchema(databaseId: String, schema: DatabaseSchema)
    func createDatabase(name: String, schema: DatabaseSchema) -> String  // returns path
}
```

### IndexManager

Loads, validates, rebuilds, and patches the index.

```swift
class IndexManager {
    func loadIndex(databasePath: URL) -> DatabaseIndex
    func isStale(index: DatabaseIndex, databasePath: URL) -> Bool
    func rebuild(databasePath: URL, schema: DatabaseSchema) -> DatabaseIndex
    func patchRow(index: inout DatabaseIndex, row: Row, filename: String, mtime: Int)
    func removeRow(index: inout DatabaseIndex, rowId: String)
    func save(index: DatabaseIndex, databasePath: URL)
}
```

Rebuild reads all .md row files, parses frontmatter, builds both the flat row map and reverse indexes in one pass.

Patch updates a single row entry and its reverse index entries. Used after mutations to avoid full rebuild.

### QueryEngine

Filters and sorts against the in-memory index. Never reads row files.

```swift
struct Query {
    let databaseId: String
    let filters: [Filter]       // ANDed
    let sorts: [Sort]
    let limit: Int?
    let offset: Int?
    let includeBody: Bool       // false by default
    let fields: [String]?       // nil = all properties
}

enum Filter {
    case equals(property: String, value: PropertyValue)
    case notEquals(property: String, value: PropertyValue)
    case greaterThan(property: String, value: PropertyValue)
    case lessThan(property: String, value: PropertyValue)
    case contains(property: String, value: PropertyValue)
    case notContains(property: String, value: PropertyValue)
    case isEmpty(property: String)
    case isNotEmpty(property: String)
    case inList(property: String, values: [PropertyValue])
}

struct QueryResult {
    let rows: [Row]
    let totalCount: Int
    let hasMore: Bool
}
```

Execution path:
1. If filter is on an indexed property, look up reverse index -> candidate row IDs (O(1))
2. If filter is on a scanned property, iterate `index.rows` (O(n) but in-memory)
3. Intersect candidates if multiple filters
4. Sort the result
5. Apply offset/limit
6. If `includeBody`, read row files for matching rows only

### MutationEngine

Validates, writes, and patches the index. Batch is the default path.

```swift
struct Mutation {
    let databaseId: String
    let operations: [Operation]
}

enum Operation {
    case createRow(properties: [String: PropertyValue], body: String?)
    case updateRow(rowId: String, properties: [String: PropertyValue])
    case updateRowBody(rowId: String, body: String)
    case deleteRow(rowId: String)
}

struct MutationResult {
    let created: [String]    // row IDs
    let updated: [String]
    let deleted: [String]
    let errors: [MutationError]
}
```

Execution:
1. Validate all property values against schema via SchemaValidator
2. If any validation fails, return errors (no partial execution)
3. Write/update/delete row files (atomic write per file)
4. Patch the index once at the end (not per operation)
5. Save index to disk

### SchemaValidator

Rejects bad types before they hit disk.

```swift
class SchemaValidator {
    func validate(properties: [String: PropertyValue], schema: DatabaseSchema) -> [ValidationError]
}
```

Checks:
- Property ID exists in schema
- Value type matches property type (string in number field -> error)
- Select value is a valid option ID
- Relation target is a valid row ID (optional, can be deferred)
- Required properties are present (title)

### RelationResolver

Cross-database relation lookups. Reads target database indexes, not row files.

```swift
class RelationResolver {
    func resolve(
        rows: [Row],
        relations: [String],           // which relation property IDs to expand
        fields: [String],              // which properties to include from related rows
        store: DatabaseStore
    ) -> [Row]  // rows with relation properties expanded
}
```

---

## CLI

Built with swift-argument-parser. All output is JSON to stdout. Errors to stderr with nonzero exit codes.

```
bugbook <command> [options]

  --workspace <path>    workspace root (default: ~/Bugbook)
  --format <json|text>  output format (default: json)

Commands:

  db list                           list all databases
  db schema <db>                    print schema
  db create <name> --schema <file>  create database from schema JSON

  query <db>                        query rows
    --filter <expr>                 repeatable
    --sort <expr>                   repeatable
    --limit <n>
    --offset <n>
    --body                          include row body in output
    --fields <f1,f2,...>            only return these properties

  get <db> <row_id>                 get single row
    --body                          include body

  create <db>                       create row
    --set <k=v>                     repeatable
    --body-file <path>              read body from file (- for stdin)

  update <db> <row_id>              update row
    --set <k=v>                     repeatable
    --body-file <path>

  delete <db> <row_id>              delete row

  batch <db>                        batch operations from stdin JSON
```

### Filter Syntax

```
property=value          equals
property!=value         not equals
property>value          greater than (number, date)
property<value          less than
property~value          contains (text, multi_select, relation)
property!~value         not contains
property=_empty         is empty
property=_not_empty     is not empty
```

### CLI Examples

```bash
# Active high-priority tasks
bugbook query tasks --filter "status=opt_doing" --filter "priority=opt_high"

# Tasks due before March
bugbook query tasks --filter "due<2026-03-01" --sort "due:asc"

# Tasks in a project
bugbook query tasks --filter "project~row_proj_001"

# Tasks blocking a specific task
bugbook query tasks --filter "blocks~row_xyz"

# Create a task
bugbook create tasks \
  --set "title=Deploy fix" \
  --set "status=opt_todo" \
  --set "priority=opt_urgent" \
  --set "project=row_proj_001"

# Update status
bugbook update tasks row_a1b2c3 --set "status=opt_done"

# Batch: mark all Done tasks as completed
bugbook query tasks --filter "status=opt_done" --fields "id" \
  | jq -c '[.rows[] | {op:"update", id:.id, set:{done:true}}]' \
  | bugbook batch tasks
```

### Batch Input Format

```json
[
  { "op": "create", "set": { "title": "New task", "status": "opt_todo" } },
  { "op": "update", "id": "row_a1b2", "set": { "status": "opt_done" } },
  { "op": "delete", "id": "row_old1" }
]
```

All operations validate first, execute together, update the index once.

---

## Skill

`skills/bugbook.md` — teaches agents the CLI:

```markdown
You manage a local bugbook workspace via the `bugbook` CLI.
All commands return JSON. Use jq to parse output when needed.

## Discovering what exists

bugbook db list                    # -> [{id, name, path, row_count}]
bugbook db schema <db_name>        # -> full schema with properties and options

Always check the schema before querying to get correct property IDs and option IDs.

## Querying

bugbook query <db> [--filter "prop=val"] [--sort "prop:asc"] [--limit N]

Filter operators: = != > < ~ !~ =_empty =_not_empty
Multiple --filter flags are ANDed.

Common patterns:
  bugbook query tasks --filter "status=opt_doing"
  bugbook query tasks --filter "status!=opt_done" --sort "priority:asc"
  bugbook query tasks --filter "project~row_proj_001"

## Reading a row

bugbook get <db> <row_id> --body   # includes markdown body

## Creating

bugbook create <db> --set "title=..." --set "status=opt_todo"

Use option IDs for select/multi_select (e.g. opt_todo not "Todo").

## Updating

bugbook update <db> <row_id> --set "status=opt_done"
bugbook update <db> <row_id> --body-file -    # pipe body via stdin

## Deleting

bugbook delete <db> <row_id>

## Batch operations

Pipe JSON array to stdin:
echo '[{"op":"update","id":"row_x","set":{"status":"opt_done"}}]' | bugbook batch <db>

## Conventions

- Always use property IDs (prop_status) not display names (Status)
- Always use option IDs (opt_todo) not display names (Todo)
- Relations store row IDs: --set "project=row_proj_001"
- Dates are YYYY-MM-DD: --set "due=2026-03-15"
- Multi-select values are comma-separated: --set "tags=opt_bug,opt_feature"
```

---

## SwiftUI Frontend

The app imports BugbookCore. Views never touch files directly.

### DatabaseViewModel

The boundary between UI and core:

```swift
@Observable
class DatabaseViewModel {
    let store: DatabaseStore
    let query: QueryEngine
    let mutation: MutationEngine

    var schema: DatabaseSchema
    var rows: [Row] = []
    var activeView: ViewConfig
    var totalCount: Int = 0

    // Called when filters/sorts/view changes
    func refresh() {
        let result = query.execute(Query(
            databaseId: schema.id,
            filters: activeView.filters,
            sorts: activeView.sorts,
            limit: 100
        ))
        rows = result.rows
        totalCount = result.totalCount
    }

    // Called on cell edit
    func updateProperty(rowId: String, propertyId: String, value: PropertyValue) {
        mutation.execute(Mutation(
            databaseId: schema.id,
            operations: [.updateRow(rowId: rowId, properties: [propertyId: value])]
        ))
        refresh()
    }

    // Called when row is opened (lazy body load)
    func loadBody(rowId: String) -> String {
        store.loadRowBody(databaseId: schema.id, rowId: rowId)
    }
}
```

### View Types

All views are projections of the same QueryResult:

- **Table** — rows as spreadsheet rows, properties as columns. Inline cell editing. Column resize/reorder/hide.
- **Kanban** — group by a select property (e.g. status). Drag between columns calls `updateProperty`.
- **Calendar** — rows placed on dates by a date property. Week/month toggle.
- **List** — compact title + key properties. Good for dense views.

Each view reads `activeView.type` and renders accordingly. Filter/sort/group_by are per-view and stored in the schema. Switching views swaps `activeView` and calls `refresh()`.

### Inline Database Embeds

Markdown pages can embed databases using `[[database:path]]` syntax. The markdown editor recognizes this and renders a `DatabaseEmbed` SwiftUI view inline. The embed is a read-only mini table view. Click to open the full database view.

---

## File Locking

Both the app and CLI can write to the same database. Use advisory file locks on `_index.json`:

- CLI: acquire lock, execute mutation, release lock
- App: acquire lock before write, release after index update
- Reader (query-only): no lock needed, reads are safe against partial index writes because of atomic writes

---

## Key Design Decisions

1. **`_schema.json` is the sentinel.** A folder is a database if and only if it contains this file. No registry.
2. **Index has reverse indexes.** Select, multi_select, relation, and checkbox properties get O(1) lookup maps. Built during index rebuild, patched on mutation.
3. **Batch mutations update the index once.** Not once per row. Eliminates the N-index-write problem.
4. **Bodies are always lazy.** The index never stores body content. Bodies are read from row files only when explicitly requested.
5. **Atomic writes everywhere.** Write to `.tmp`, then rename. Prevents corruption from crashes.
6. **Schema validation on every write.** Both CLI and app go through SchemaValidator. Agents can't silently corrupt data.
7. **One core library, two consumers.** BugbookCore is the single source of truth. CLI and SwiftUI app are thin wrappers.
8. **Property IDs, not names.** All storage and queries use stable IDs (prop_status, opt_todo). Display names are for the UI only.
