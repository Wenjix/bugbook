---
name: compile
description: Compile a Dahso workspace into an agent-navigable wiki. Reads all pages, groups them by topic, generates a root Index.md that serves as the agent's entry point, and optionally creates summary articles for each category. Reusable — run once after a bulk import, then periodically as the workspace grows. Use when the user says "compile", "build my wiki", "generate index", "organize my notes", "compile my workspace", or after running /import-obsidian.
---

# Compile

Turn a flat collection of Dahso pages into an agent-navigable wiki with a root Index.md.

This is the step that makes an imported vault (or any growing workspace) queryable by agents. Without an index, the agent has to guess which pages to read. With one, it can drill from a single entry point into whatever it needs.

---

## When to use

- After `/import-obsidian` (or `/import-notion` eventually) to organize the dump.
- After a week of manual note-taking to keep the structure tight.
- As a scheduled monthly job (`/schedule compile`) to incrementally enhance the wiki.
- Any time the user says "organize", "compile", or "build the index."

## Principles

1. **Don't move files silently.** Always propose and get approval before reorganizing.
2. **Wikilinks are resilient to moves** — Dahso resolves by filename, not path. But verify after moving.
3. **Index.md is for agents, not humans.** Structure it for crawlability (one-line per entry), not aesthetics.
4. **Read everything, group by content, not by folder.** Obsidian folder structure was arbitrary; the compile pass should reflect *what things are about*, not where they were stored.
5. **Summaries are optional.** The user can request them, but the default is: index + grouping only.

---

## Phase 1: Scan

Read the workspace via CLI. Do not try to read 400 files sequentially — use `dahso page list` for metadata and selective reads for content.

### Get all pages

```bash
dahso page list --format json
```

This returns `name`, `path`, `relative_path`, `title`, `tags`, `wikilinks`, `modified_at` for every page. Capture the full list as the working set.

### Build a summary for each page

For each page, extract a ~200-character summary from the first paragraph after the H1. Read in batches to avoid token explosion:

```bash
# Read the first 30 lines of a page (usually enough for title + opening paragraph)
dahso page get "<page-name>" --raw | head -30
```

For large workspaces (500+ pages), sample 20% of pages and classify the rest by filename alone. The user can re-run with `--thorough` to read everything.

### Extract metadata

From the scan, build a map:

```
{
  "page_name": {
    "title": "...",
    "summary": "...",  // first paragraph, ~200 chars
    "wikilinks": ["...", "..."],
    "tags": ["...", "..."],
    "folder": "Slip-Box/Body",  // original folder path
    "modified_at": "2026-..."
  }
}
```

---

## Phase 2: Propose grouping (approval gate)

Cluster pages into topical buckets. Use the summaries, wikilink graph, tags, and folder structure as signals.

### Default categories

Start with these and merge/split based on content:

- **People** — notes about individuals, relationship context, meeting notes mentioning specific people
- **Projects** — anything with a clear deliverable, timeline, or ticket
- **Concepts** — ideas, frameworks, mental models, definitions
- **Inspiration** — images, screenshots, aesthetics, things that sparked something
- **Health** — supplements, biomarkers, exercise, longevity, recovery
- **Writing** — drafts, blog posts, essays, public content
- **Learning** — book notes, course notes, Readwise highlights, lectures
- **Decisions** — documented choices, pros/cons, post-mortems
- **Personal** — diary entries, memories, reflections, spiritual notes

Pages that fit multiple categories go in the one that's most specific. Use judgment — a book note about health goes in **Health**, not **Learning**, because the topic matters more than the format.

### Present the grouping

Show the user a table:

```
Category      Count  Sample pages
──────────────────────────────────────────
People          12   Bret Convo, Shae's results, Grand Canyon Guy...
Projects        24   First Vision Project, Sameday, 12 Step Program...
Concepts        35   Perfectionism, Indifference, Systems...
Inspiration      8   Roll 05-14-2023, Images/...
Health          15   Exercise, Supplements, θεραπεία/...
Writing         18   Writing, Recent Ideas, Product Management...
Learning        87   Atomic Habits, The Mom Test, Readwise/...
Decisions        5   Startup Advice, Founder Coaching...
Personal        48   Birthday 2022, Sunday School, Stake Conference...
Uncategorized   141  <pages that didn't match any signal>
```

**Wait for user approval.** The user can:
- Approve the grouping and proceed
- Rename categories
- Move specific pages between categories
- Add new categories
- Say "skip grouping, just generate the index from the current structure"

---

## Phase 3: Restructure (optional, requires approval)

If the user approved the grouping, move pages into category folders.

```bash
# Create category folders
for cat in People Projects Concepts Inspiration Health Writing Learning Decisions Personal; do
  mkdir -p "$WORKSPACE/$cat"
done

# Move each page to its category folder
mv "$WORKSPACE/Exercise.md" "$WORKSPACE/Health/Exercise.md"
```

**Verify wikilinks still resolve after moves:**

```bash
dahso backlinks "Exercise"
# Should still return results — wikilinks resolve by filename, not path
```

If the user said "skip grouping", skip this phase entirely and generate the index from the existing folder structure.

---

## Phase 4: Generate Index.md

Create a root `Index.md` at the workspace root. This is the agent's primary entry point for any future query.

### Structure

```markdown
# Index

Catalog of all pages in this workspace, grouped by topic. Last compiled: YYYY-MM-DD.

---

## People

- [[Bret Convo]] — conversation notes with Bret about X
- [[Grand Canyon Guy]] — Swiss traveler met at Grand Canyon, works in Y

## Projects

- [[First Vision Project]] — research project on early LDS history
- [[Sameday]] — delivery startup project notes

## Concepts

- [[Perfectionism]] — reflections on perfectionism and productivity
- [[Systems]] — thinking in systems, feedback loops

...

## Recently Modified

- [[Exercise]] — updated 2026-04-03
- [[Startup Advice]] — updated 2026-04-01
- [[Writing]] — updated 2026-03-30

---

*393 pages indexed. Run `/compile` to refresh.*
```

### Rules

- Every page gets exactly one line: `- [[Page Name]] — <summary snippet, max 80 chars>`
- Group by category (from Phase 2) or by folder (if grouping was skipped)
- Add a "Recently Modified" section with the 10 most recently edited pages
- Add a compile timestamp
- Add a total page count

### Write it

```bash
echo '<generated index content>' | dahso page create "Index" --content-file -
# Or update if Index already exists:
echo '<generated index content>' | dahso page update "Index" --content-file -
```

---

## Phase 5: Optional summary articles

If the user requests them (or if the workspace has 200+ pages), generate one summary article per category. These link to all member pages with a 1-2 sentence hook.

```markdown
# Learning

87 pages of book notes, course notes, and highlights.

---

## Books

- [[Atomic Habits]] — James Clear's framework for habit formation through small changes
- [[The Mom Test]] — how to talk to customers without leading them
- [[You Need a Budget]] — zero-based budgeting philosophy

## Courses

- [[Leadership Development Experience]] — leadership course notes from 2023
...
```

Write these as standalone pages in each category folder:

```bash
echo '<summary content>' | dahso page create "Learning/Learning" --content-file -
```

---

## Phase 6: Verify

### Index renders

```bash
dahso page get "Index" --raw | head -40
```

Confirm it's well-formed markdown with working wikilinks.

### Agent crawl test

```bash
dahso context "Index" --depth 2
```

This should traverse from Index.md → category pages → individual pages. If the output is non-empty and structured, the compile loop is working.

### Sample query

Tell the user to ask a Farza-style question:

> "Based on everything in my wiki, what are my recurring themes around productivity and systems?"

The agent should be able to start at Index.md, drill into the relevant categories (Concepts, Learning), and pull from specific pages to answer. If it does, the compile worked.

---

## Incremental mode

On subsequent runs, `/compile` should:

1. Detect new pages not yet in the index (compare `dahso page list` against `Index.md` contents)
2. Classify the new pages using the existing category structure
3. Add them to the index
4. Optionally file new pages into the existing category folders
5. Refresh the "Recently Modified" section
6. Update the compile timestamp

This is lighter than a full rebuild — most of the work is reading the diff.

---

## Non-goals

- This skill does not import content from external sources. That's `/import-obsidian` or `/import-notion`.
- This skill does not create `raw/` inbox notes. That's `RawInboxWriter` via the share extension or manual drop.
- This skill does not lint the wiki for errors. That would be `/lint` (TBD).
- This skill does not run health checks for contradictions or stale data. That's a separate pass.
