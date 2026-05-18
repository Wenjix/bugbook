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

### iCloud file availability

If the source vault is in iCloud (paths under `iCloud~md~obsidian/` or `com~apple~CloudDocs/`), confirm files are downloaded locally before attempting to read content. `.icloud` stub files are placeholders that trigger slow downloads or timeouts during bulk reads.

```bash
stub_count=$(find "$SOURCE" -type f -name "*.icloud" 2>/dev/null | wc -l | tr -d ' ')
if [ "$stub_count" -gt 0 ]; then
  echo "⚠️  $stub_count .icloud stub files detected — content not downloaded locally."
  echo "   In Finder: right-click the vault folder → Download Now, then retry."
  exit 1
fi
```

Hard-fail rather than push through; downstream content reads will stall for tens of minutes on a large vault if the files aren't local.

### Cross-workspace collision scan

Intra-Obsidian collisions aren't the only risk. Scan source filenames against existing destination filenames — anything in common will cause wikilinks in imported pages to potentially resolve to the wrong target.

```bash
# Find source filenames that already exist somewhere in $DEST (excluding Bugbook system dirs)
python3 << 'PY'
from pathlib import Path
src = Path("$SOURCE")
dst = Path("$DEST")
skip_prefixes = ("Agent Flow/", "Bugbook Context/", "logseq/", "Settings/",
                 "WorkspaceLayouts/", "_assets/", "covers/", "icons/",
                 "journals/", "pages/", "whiteboards/", ".trash", ".git")
existing = set()
for md in dst.rglob("*.md"):
    rel = str(md.relative_to(dst))
    if any(rel.startswith(p) for p in skip_prefixes):
        continue
    existing.add(md.name)
incoming = set(md.name for md in src.rglob("*.md") if "/.obsidian/" not in str(md) and "/.trash/" not in str(md))
cross = sorted(existing & incoming)
print(f"Cross-workspace collisions: {len(cross)}")
for c in cross[:20]:
    print(f"  {c}")
PY
```

For each cross-collision, the import rewrites the inbound page with a parent-folder suffix (same treatment as intra-Obsidian collisions). Report the list to the user in Phase 3.

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

### Empty source files

0-byte or whitespace-only source files create fake collisions with destination scaffolding (e.g. Obsidian's `Untitled.md` vs Bugbook's `QA Slash Blocks/Untitled.md`) and add noise to the index. Count them so the Phase 3 summary is honest about what's actually being imported.

```bash
find "$SOURCE" -type f -name "*.md" -not -path "*/\.obsidian/*" -not -path "*/\.trash/*" -size 0 | wc -l
```

Phase 4 will skip files under ~10 bytes (empty after frontmatter stripping also counts).

### Inline wikilink scan (known rendering caveat)

Obsidian content heavily uses inline `[[Page Name]]` wikilinks inside bullets and paragraphs (e.g. `- [[Foo]]` or `See [[Foo]] for context`). Bugbook's current parser only resolves `[[Page Name]]` when *the line is exactly `[[Page Name]]`* — tracked in app-side ticket `row_dwjb9w`. Inline wikilinks render as literal `[[...]]` text in the app until that ships.

Count inline wikilinks so the user can choose a mode in Phase 3:

```bash
# Any line where [[Name]] is not the only content on the line
grep -rE '.[[].+[]]|^.*[[][^]]+[]].+' "$SOURCE" --include="*.md" \
  -l 2>/dev/null | wc -l
```

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
  - rename intra-Obsidian and cross-workspace collision files with parent-folder suffix
  - rewrite inbound wikilinks for renamed files
  - skip 0-byte / empty source files
```

### Wikilink rendering mode (user choice)

If the inline-wikilink scan found any, ask the user to choose:

**A) Leave wikilinks as-is** (recommended default). Inline `[[Name]]` will render as literal `[[brackets]]` in Bugbook until the parser fix (`row_dwjb9w`) lands. Standalone-line `[[Name]]` wikilinks render as clickable links today. Best option for preserving original authored structure.

**B) Rewrite inline wikilinks to standalone-line form** (workaround mode). The transform extracts inline wikilinks onto their own lines (bullet `- [[Foo]] — note` becomes `[[Foo]]` on one line + `note` on the next). All wikilinks become clickable in current Bugbook, at the cost of changing the original bullet-list layout. Reversible when the parser fix ships.

Both modes are deterministic; pick based on user preference. Record the choice for Phase 4.

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

For each `.md` file under `$SOURCE` (excluding `.obsidian/`, `.trash/`, the Images folder, any `*.excalidraw.md`, and any file under ~10 bytes after frontmatter stripping):

1. Compute the relative path and create the destination folder if needed.
2. Read the file.
3. Apply transforms (see `references/transforms.md`):
   - Strip YAML frontmatter block at file start.
   - Skip file entirely if post-frontmatter body is empty or whitespace-only.
   - If there's no `# H1` within the first 20 lines, synthesize one from the filename.
   - Rewrite every `![[image.png]]` embed as `![](Images/image.png)`. If the embedded file is not an image, leave a `<!-- TODO: embedded file not migrated: image.png -->` comment and continue.
   - **If wikilink mode B was chosen in Phase 3**: for each line where `[[Name]]` is embedded with other content, extract the wikilink onto its own line — split before and after so surrounding text stays on separate lines. Skip this transform if mode A.
   - Leave standalone-line `[[Page Name]]` wikilinks as-is.
   - If this filename is in the intra-Obsidian or cross-workspace collision list, rename it with the parent-folder suffix and record the rename.
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

### Relaunch the Bugbook app (required)

**This is not optional.** Bugbook's in-memory page index does not rebuild on external bulk file changes. After a 100+ page import, the app's sidebar, search, and wikilink resolver will be stale until the app fully restarts.

Tell the user explicitly: **quit Bugbook (Cmd+Q) and relaunch** before the next check. If running from Xcode, Stop (⌘.) and Run (⌘R).

### macOS app spot-check (post-restart)

After the user has restarted the app, ask them to spot-check:
- Sidebar shows the imported top-level folders
- A sample page opens with correct H1 title + body
- An image in a page loads (if `Images/` was present)
- A wikilink on a standalone line resolves to its target

Inline wikilinks (not on their own line) will display as literal `[[brackets]]` — this is tracked by app-side ticket `row_dwjb9w` and the user will have been warned at Phase 3. If mode B was chosen, all wikilinks should be clickable.

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

- **Trailing space in vault path.** Quote every path. Some iCloud-synced vaults have a trailing space in the folder name (e.g. `Muse /`) that breaks unquoted shell expansion.
- **iCloud sync latency and stubs.** Pre-flight catches `.icloud` stub files. Files written to `$DEST` also propagate to iCloud asynchronously — sync to other devices may take seconds to minutes.
- **Non-image embeds.** Obsidian supports `![[file.pdf]]` and `![[audio.mp3]]` — leave a TODO comment rather than trying to migrate.
- **Frontmatter-only pages.** After frontmatter stripping, some pages are empty or whitespace-only. Skip these rather than writing empty H1-only files that pollute the index.
- **Excalidraw files.** Skip `*.excalidraw.md` entirely — they're JSON drawings, not markdown content.
- **`.trash/` and `.obsidian/`.** Never import these directories.
- **0-byte source files.** Skip entirely. They create fake collisions with destination system files (notably `Untitled.md`) and add no content.
- **Inline wikilinks render as raw `[[brackets]]` in current Bugbook.** Tracked in app ticket `row_dwjb9w`. The user chose mode A (leave as-is) or mode B (rewrite to standalone-line) at Phase 3. Reversible once the parser fix ships.
- **Absolute-path database embeds.** Some Obsidian pages carry `<!-- database: /absolute/path -->` comments that break silently when workspace is renamed or moved. Tracked in app ticket `row_r8pk0p`. Import leaves them intact; user should eyeball any page that renders blank post-restart.
- **Bugbook `Page.md` + `Page/` folder pairs.** Bugbook's convention pairs a markdown page with a sibling folder for embedded database content. The import doesn't create these, but downstream `/compile` runs that move files must move the pair together — orphaned pair folders cause silent data loss. Flag for `/compile` authors.
- **Bugbook app requires relaunch after bulk import.** Not "usually" — always. The app's in-memory index doesn't rebuild on external file changes. Already called out in Phase 5 as a required step.

## Known non-goals

- This skill does **not** create an `Index.md`, group pages by topic, or generate summaries. That's `/compile`'s job. Run `/compile` after this finishes.
- This skill does **not** import from Notion. Use `/import-notion` (TBD) for that.
- This skill does **not** handle incremental sync — it's a one-shot. If the user adds new files in Obsidian later, they need to re-run.
