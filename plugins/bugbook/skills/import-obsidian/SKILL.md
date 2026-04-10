---
name: import-obsidian
description: One-shot migration from an Obsidian vault into the canonical Bugbook workspace. Preserves folder hierarchy, wikilinks, and images, transforming Obsidian-specific syntax into Bugbook equivalents. Use when the user says "import obsidian", "migrate my vault", "import my notes from obsidian", or pastes an Obsidian vault path. Runs phases: pre-flight → inventory → transform plan (approval gate) → write → verify → report.
---

# Import Obsidian

One-shot migration from an Obsidian vault into Bugbook. The goal is to land a clean, agent-crawlable wiki in the canonical Bugbook workspace without losing content, wikilinks, or media.

The user gets a dry-run preview first. Nothing is written until they approve.

**Reference spec:** `references/transforms.md` in this skill folder — cites the exact Obsidian → Bugbook transform rules. Read it before writing code that touches content.

---

## Phase 1: Pre-flight

Resolve both ends before touching anything.

### Source vault

Default to Max's Muse vault. If the user passed a path, use it instead. **Quote every path** — the Muse directory has a trailing space (`Muse /`).

```bash
SOURCE="${1:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Muse/}"
test -d "$SOURCE" && echo "✅ source: $SOURCE" || { echo "❌ source not found: $SOURCE"; exit 1; }
```

If the default doesn't exist, scan for any vault:

```bash
find ~ -maxdepth 5 -type d -name ".obsidian" 2>/dev/null | head
```

Present candidates to the user and confirm before continuing.

### Destination workspace

Always the canonical Bugbook workspace. On the user's Mac, `~/Documents/Bugbook` is a symlink into the iCloud container and is the correct target. Do **not** ask the user to pick — `WorkspaceResolver` is the source of truth.

```bash
DEST="$HOME/Documents/Bugbook"
test -d "$DEST" || mkdir -p "$DEST"
echo "✅ destination: $DEST"
```

### Guard: non-empty destination

If the destination already has `.md` files, confirm with the user before proceeding. Offer to import into a subfolder (`$DEST/Obsidian Import/`) so existing content is preserved.

```bash
find "$DEST" -maxdepth 2 -name "*.md" -not -path "*/\.*" | head -5
```

---

## Phase 2: Inventory (read-only)

Count and detect everything before planning. Every command is read-only.

### Counts

```bash
find "$SOURCE" -type f -name "*.md" -not -path "*/\.obsidian/*" | wc -l
find "$SOURCE" -type d -not -path "*/\.obsidian*" -not -path "$SOURCE" | head -20
```

### Media directories

```bash
# Common media folder names
for name in Images Attachments attachments assets media; do
  d="$SOURCE$name"
  if [ -d "$d" ]; then
    count=$(find "$d" -type f | wc -l | tr -d ' ')
    echo "📁 $name: $count files"
  fi
done
```

### Obsidian-specific syntax scan

Each of these needs a transform. Report counts so the user knows what's coming.

```bash
# Callouts — "> [!note]" / "> [!warning]" etc.
grep -rE '^> \[!' "$SOURCE" --include="*.md" | wc -l

# Dataview blocks
grep -rl '```dataview' "$SOURCE" --include="*.md" | wc -l

# Excalidraw files
find "$SOURCE" -name "*.excalidraw.md" | wc -l

# Frontmatter aliases (only the frontmatter block at file start)
grep -rl -E '^aliases:' "$SOURCE" --include="*.md" | wc -l

# Obsidian image embed syntax ![[image.png]] — NOT standard markdown
grep -rE '!\[\[[^]]+\]\]' "$SOURCE" --include="*.md" | wc -l

# Hashtag inline tags (kept as-is, but reported)
grep -roE '(^|[[:space:]])#[a-zA-Z][a-zA-Z0-9/_-]*' "$SOURCE" --include="*.md" | wc -l
```

### Filename collision scan

Bugbook wikilinks resolve by filename minus `.md`, case-insensitive, across all folders. Two files named `Note.md` in different folders both collide on `[[Note]]`. Detect them now.

```bash
find "$SOURCE" -type f -name "*.md" -not -path "*/\.obsidian/*" \
  -exec basename {} \; | sort | uniq -d
```

For each collision, the transform will rename the file as `<Name> (<parent-folder>).md` and rewrite inbound wikilinks accordingly. Report the full list to the user.

### Pages without an H1 title

Bugbook derives the page title from the first H1. Pages without one will get an H1 synthesized from the filename.

```bash
find "$SOURCE" -type f -name "*.md" -not -path "*/\.obsidian/*" | while read -r f; do
  head -20 "$f" | grep -qE '^# ' || echo "no-h1: $f"
done | head -20
```

Count the full set, don't just print first 20.

---

## Phase 3: Transform plan (approval gate)

Show the user a concise summary:

```
Source:     <path>
Destination: <path>

Content:
  393 markdown files across 6 folders
  1 media folder: Images/ (128 files)

Syntax found:
  callouts:       0
  dataview:       0
  excalidraw:     0
  aliases:        0
  embed syntax:   27   → will rewrite ![[image.png]] as ![](Images/image.png)
  hashtag tags:   412  → preserved as-is

Issues:
  Filename collisions: 3
    - Note.md (Inbox, Slip-Box)
    - Ideas.md (Inbox, Reference System)
    - Misc.md (Inbox, Memories)
  Pages without H1: 14  → title synthesized from filename

Transform rules (see references/transforms.md):
  - preserve folder hierarchy
  - copy Images/ to workspace root
  - rewrite image embed syntax to standard markdown
  - strip YAML frontmatter
  - synthesize H1 from filename when missing
  - rename collision files with parent-folder suffix
  - rewrite inbound wikilinks for renamed files
```

**Wait for user approval before proceeding to Phase 4.** Do not write any files in Phases 1–3.

---

## Phase 4: Write

After approval. Operate on a copy, not the source — never mutate the Obsidian vault.

### Move the Images directory first

```bash
# Copy images to the workspace root so relative paths resolve from any nested page
mkdir -p "$DEST/Images"
rsync -av "$SOURCE"Images/ "$DEST/Images/"
```

Use `rsync -av` (not `cp -r`) so subsequent runs are idempotent and progress is visible.

### Walk the markdown tree

For each `.md` file under `$SOURCE` (excluding `.obsidian/`, `.trash/`, the Images folder, and any `*.excalidraw.md`):

1. Compute the relative path and create the destination folder if needed.
2. Read the file.
3. Apply transforms (see `references/transforms.md`):
   - Strip YAML frontmatter block at file start.
   - If there's no `# H1` within the first 20 lines, synthesize one from the filename.
   - Rewrite every `![[image.png]]` embed as `![](Images/image.png)`. If the embedded file is not an image, leave a `<!-- TODO: embedded file not migrated: image.png -->` comment and continue.
   - Leave `[[Page Name]]` wikilinks as-is.
   - If this filename is in the collision list, rename it with the parent-folder suffix and record the rename.
4. Write the transformed content to the destination path.

Implement this in one pass — read, transform, write — via a small script (bash, python, or inline heredoc). Do not use subagents for this phase; it's a single deterministic loop.

### Rewrite wikilinks for renamed files

After all files are written, do a second pass to rewrite wikilinks pointing at the renamed collision files.

```bash
# Pseudocode: for each (old_name, new_name) in the rename map,
# find all .md files in $DEST, replace [[old_name]] with [[new_name]].
# Use sed -i '' or a scripted approach; be careful with shell escaping.
```

---

## Phase 5: Verify

After the write pass completes, run three checks.

### CLI sanity

```bash
bugbook page list | jq 'length'
# Expect ~393 (or whatever the inventory reported)
```

### Sample page

Pick a known page with wikilinks and images. Read it through the CLI and confirm it renders.

```bash
bugbook page get "<some-page>" --raw | head -40
bugbook backlinks "<some-page>"
```

### Macbook app

Tell the user to open the macOS Bugbook app and spot-check:
- Index/file tree shows the imported folder hierarchy
- A sample page opens with correct H1 title + body
- An image in a page loads (if `Images/` was present)
- A wikilink resolves to its target page

---

## Phase 6: Report

Write a concise summary and stop. Include:

- **Imported:** total `.md` files written, folders created, images copied
- **Transformed:** embed-syntax rewrites, H1 synthesizes, collision renames
- **Skipped:** Excalidraw files, any files that failed to read, frontmatter blocks stripped
- **Follow-ups:** anything the user should eyeball (pages with only a frontmatter block and no body, pages with non-image embeds, orphan wikilinks)
- **Next step:** suggest running `/compile` to generate `Index.md` and group pages by topic

Do not close the loop automatically — leave that to the user.

---

## Known edge cases

- **Trailing space in vault path.** Max's Muse vault is literally `Muse /` with a trailing space. Quote every path.
- **iCloud sync latency.** Files written to `$DEST` propagate to iCloud asynchronously. If the user expects them on their phone immediately, note that sync may take seconds to minutes.
- **Non-image embeds.** Obsidian supports `![[file.pdf]]` and `![[audio.mp3]]` — leave a TODO comment rather than trying to migrate.
- **Frontmatter-only pages.** Some pages are just metadata — after stripping frontmatter they're empty. Synthesize an H1 from the filename and leave the body empty; don't skip them.
- **Excalidraw files.** Skip `*.excalidraw.md` entirely — they're JSON drawings, not markdown content.
- **`.trash/` and `.obsidian/`.** Never import these directories.
- **Bugbook won't see the workspace until it's open.** If the CLI and macOS app disagree on what's in the workspace, re-launch the macOS app after the import completes.

## Known non-goals

- This skill does **not** create an `Index.md`, group pages by topic, or generate summaries. That's `/compile`'s job. Run `/compile` after this finishes.
- This skill does **not** import from Notion. Use `/import-notion` (TBD) for that.
- This skill does **not** handle incremental sync — it's a one-shot. If the user adds new files in Obsidian later, they need to re-run.
