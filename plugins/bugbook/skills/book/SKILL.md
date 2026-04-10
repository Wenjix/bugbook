---
name: bb
description: Access your bugbook workspace — local-first notes, databases, and personal context. Use when the user wants to see their notes, tickets, databases, or personal knowledge.
---

# Bugbook

Your personal operating system. A local-first knowledge workspace for notes, databases, and structured context.

## Finding Your Workspace

Bugbook stores workspaces in these locations (check in order):

1. **iCloud (macOS/iOS):** `~/Library/Mobile Documents/iCloud~com~bugbook~app/Documents/`
2. **Local fallback:** `~/Documents/Bugbook/`

To find your workspace:
```bash
ls ~/Library/Mobile\ Documents/iCloud~com~bugbook~app/Documents/ 2>/dev/null || ls ~/Documents/Bugbook/
```

## Structure

Each workspace is a folder containing:
- `*.md` files — markdown pages with optional YAML frontmatter
- **Database folders** — structured data with:
  - `_schema.md` — property definitions (name, type, options)
  - `_index.json` — row metadata for quick scanning
  - `*.md` files — one per row (YAML frontmatter + body)

## Traversal

- Start by listing the workspace root
- Databases have `_schema.md` — read it to understand the data model
- Read `_index.json` for a quick overview of all rows
- Follow `[[wikilinks]]` in prose to navigate related pages

## Block Types

Bugbook pages are composed of these block types, each with its markdown syntax:

| Block | Markdown | Notes |
|-------|----------|-------|
| Paragraph | Plain text | Default block type |
| Heading 1 | `# Title` | First H1 becomes the page title |
| Heading 2 | `## Section` | Primary sections |
| Heading 3 | `### Subsection` | Secondary sections |
| Bullet list | `- item` | Nest with 2-space indent |
| Numbered list | `1. item` | Nest with 3-space indent |
| To-do | `- [ ] task` or `- [x] done` | Checkbox items |
| Quote | `> text` | Block quote |
| Code | ` ```lang ... ``` ` | Fenced code block with language |
| Divider | `---` | Horizontal rule |
| Toggle | `<details><summary>Title</summary>` | Collapsible section, children inside |
| Image | `![alt](path)` | Relative path to workspace image |
| Database embed | `<!-- bugbook-database: path -->` | Embeds a database view inline |
| Page link | `<!-- bugbook-page-link: Name -->` | Link to a sub-page |
| Columns | `<!-- bugbook-columns -->` | Multi-column layout |
| Wikilink | `[[Page Name]]` | Inline link to another page |

## Creating Beautiful Pages

When creating pages, use structure and hierarchy intentionally. Don't dump raw text — compose blocks like a designer would.

**Principles:**
- Use heading hierarchy (H1 → H2 → H3), never skip levels
- Use dividers (`---`) between major sections for visual breathing room
- Use toggles for content that's useful but not always needed (details, FAQs, background)
- Use to-do lists for action items, bullet lists for information
- Use database embeds for structured/tabular data instead of markdown tables
- Leave an empty paragraph between sections (the editor renders this as whitespace)
- Use bold for key terms in prose, not for emphasis on every other word

**Example — Project Brief:**
```markdown
# Project Name

One-paragraph overview of what this is and why it matters.

---

## Goals

1. First measurable goal
2. Second measurable goal
3. Third measurable goal

## Timeline

- **Phase 1** — Description (Week 1-2)
- **Phase 2** — Description (Week 3-4)
- **Phase 3** — Description (Week 5-6)

---

## Resources

- [[Related Page]] — context on prior work
- [[Team Member]] — responsible for X

<details>
<summary>Open Questions</summary>

- Question one that needs answering
- Question two that needs research
- Decision to be made about X

</details>

## Action Items

- [ ] First thing to do
- [ ] Second thing to do
- [ ] Third thing to do
```

**Example — Meeting Notes:**
```markdown
# Meeting Title

**Date:** 2026-03-13
**Attendees:** Alice, Bob, Charlie

---

## Agenda

1. Topic one
2. Topic two
3. Topic three

## Discussion

### Topic one

Key points discussed. Decisions made.

### Topic two

Key points discussed. Decisions made.

---

<details>
<summary>Background Context</summary>

Prior work, links, or context that informed this meeting.

</details>

## Action Items

- [ ] Alice: Do the thing by Friday
- [ ] Bob: Follow up on X
- [ ] Charlie: Write the proposal
```

## Quick Edits

Use the `bugbook` CLI for surgical edits. Always prefer the most targeted command — don't rewrite a whole page to change one block.

### Find blocks on a page

```bash
# List all blocks with their IDs and types
bugbook block list "Page Name"

# Get a specific block by selector
bugbook block get "Page Name" path:0
bugbook block get "Page Name" <block-uuid>
```

### Replace a block

```bash
# Replace a specific block with new markdown (can be multiple blocks)
echo '## New Heading

New paragraph text here.' | bugbook block replace "Page Name" <block-selector> --content-file -
```

### Insert content at a position

```bash
# Insert after a specific block
echo '- [ ] New action item' | bugbook block insert "Page Name" <block-selector> --after --content-file -

# Insert before a specific block
echo '---' | bugbook block insert "Page Name" <block-selector> --before --content-file -
```

### Update just a block's text (preserve type)

```bash
# Change bullet text without converting it to a paragraph
echo 'Updated bullet text' | bugbook block update-text "Page Name" <block-selector> --text-file -
```

### Section-level updates

```bash
# Replace an entire section's body (everything under a heading until the next same-level heading)
echo 'New section content here.' | bugbook page update "Page Name" --section "Section Title" --content-file -

# Append to a section
echo '- New item' | bugbook page update "Page Name" --section "Action Items" --append-file -

# Create a section if it doesn't exist
echo '- First item' | bugbook page update "Page Name" --section "Notes" --create-section --section-level 2 --content-file -
```

### Preview changes before writing

```bash
# Dry run — see what would change without writing
echo 'Changed text' | bugbook block replace "Page Name" <block-selector> --content-file - --dry-run
```

## Database Row Editing

Use the `bugbook` CLI for database CRUD. The `create`, `update`, `get`, `query`, and `delete` commands work on database rows.

### Read schema and data

```bash
# List all databases
bugbook db list

# Get database schema (property names, types, options)
bugbook db schema "Database Name"

# Query rows with filters
bugbook query "Database Name" --filter "Status=To Do" --body

# Get a single row with body
bugbook get "Database Name" <row_id> --body
```

### Create a row

```bash
echo '## What

Description of the item.

## Notes

Additional details.' | bugbook create "Database Name" \
  --set "Name=Row Title" \
  --set "Status=To Do" \
  --set "Priority=High" \
  --body-file -
```

### Update row properties

```bash
# Update one or more properties
bugbook update "Database Name" <row_id> --set "Status=Done"
bugbook update "Database Name" <row_id> --set "Status=In Progress" --set "Priority=High"
```

### Update row body

```bash
# Replace the entire body
echo '## Updated content

New body here.' | bugbook update "Database Name" <row_id> --body-file -
```

### Delete a row

```bash
bugbook delete "Database Name" <row_id>
```

## Page Management

### Create a page

```bash
# Create with default content
bugbook page create "Page Name"

# Create with custom content from stdin
echo '# My Page

Opening paragraph.

---

## Section One

Content here.' | bugbook page create "Page Name" --content-file -
```

### Read a page

```bash
# Full page as JSON
bugbook page get "Page Name"

# Raw markdown only
bugbook page get "Page Name" --raw

# Just a section
bugbook page get "Page Name" --section "Section Title"

# With parsed block data
bugbook page get "Page Name" --blocks
```

### Search

```bash
# Full-text search across the workspace
bugbook search "keyword"
```

## Context Traversal

Gather a page and all its linked context in one shot:

```bash
bugbook context "Page Name" --depth 2
```

This starts from the given page, extracts all `[[wikilinks]]`, and recursively follows them up to `--depth N` levels (default 2). Output is concatenated markdown with `--- Page: Name ---` delimiters between pages. Pages are deduplicated so circular links are safe.

## Ticket Workflow

When working on tickets in `Bugbook Team/Tickets/`:

```
todo → in_progress → in_review → done
```

| Status | Meaning |
|--------|---------|
| `opt_mltwla79_backlog` | Not ready to work on |
| `opt_mltwla79_todo` | Ready to pick up |
| `opt_mltwla79_inprog` | Agent is actively working |
| `opt_mltwla79_review` | Agent finished, needs human smoke test |
| `opt_mltwla79_done` | Human approved |
| `opt_mltwla79_cancel` | Won't do |

**Important:** When you finish a task, set status to `in_review`, NOT `done`. The human will review and mark it done after smoke testing.
