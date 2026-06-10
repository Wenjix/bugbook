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
