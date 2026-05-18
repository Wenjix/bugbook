# Neutralize UI Colors — Strip to Grayscale, Reserve Red for Brand Only

## Context

The app currently uses blue (`#2383e2`) as the primary accent color for all interactive elements (buttons, selections, focus states, drop targets) and red appears in both error/destructive states and as the brand color. The blue feels generic (default Apple blue) and the red brand color conflicts with error semantics. The goal is to go fully neutral first, then selectively reintroduce color with intention.

**Design reference**: YouTube's approach — brand color (red) lives only in the logo/icon, while the entire UI runs on black, white, and gray. Color becomes memorable through scarcity.

## Scope

### Phase 1: Neutralize all accent/blue usage

Replace `Color.fallbackAccent` / `appAccent` (`#2383e2` / `#528bcc`) with a neutral dark tone across all interactive elements.

**Files to change:**
- `Sources/Bugbook/Extensions/Color+Theme.swift` — Redefine `fallbackAccent` and `fallbackAccentLight` to neutral values (e.g., dark charcoal `#2d2d2d` light / soft gray `#b0b0b0` dark mode)
- `Sources/Bugbook/Extensions/DesignTokens.swift` — Update `StatusColor.info` and `StatusColor.active` away from blue
- `BugbookApp.swift` — Review the `.tint(Color.fallbackAccent)` modifier
- `macos/App/Assets.xcassets/AccentColor.colorset/Contents.json` — Update the macOS system accent color asset (currently `#D43D32`)

**UI areas affected (~162 usages of accentColor):**
- Button fills and borders (primary CTAs like "New Note", "Open Folder")
- Selection highlights (table rows, sidebar items, calendar dates)
- Active tab/state indicators
- Drag-and-drop target highlights
- Focus rings and form states
- Database cell selection states

**Target palette for interactive elements:**
- Light mode: Black/dark charcoal fills with white text for primary actions; medium gray borders/outlines for secondary
- Dark mode: White/light gray fills with dark text for primary actions; medium gray for secondary
- Hover/pressed states: Slightly lighter/darker variants of the above

### Phase 2: Isolate brand red to logo only

Ensure `Brand.primary` (`#e8453c`) is only used for the app icon/logo and not in UI chrome.

**Files to change:**
- `Sources/Bugbook/Extensions/DesignTokens.swift` — Keep `Brand.primary` defined but audit all usage
- Any views currently using `Brand.primary` or `Brand.subtle` for non-logo purposes (e.g., `AiSidePanelView.swift` uses `Brand.primary` for the AI send button, `BlockCellView.swift` uses `Brand.subtle` as a background)
- Replace these usages with neutral alternatives

### Phase 3: Preserve functional color meanings

Keep existing color semantics for things that genuinely need color:
- `StatusColor.error` (red) — keep for actual error/destructive states, but consider shifting to a less alarming tone
- `StatusColor.success` (green) — keep
- `StatusColor.warning` (yellow/amber) — keep
- `BlockColor` palette — keep the full 10-color palette for user-applied text/background colors (these are content colors, not UI chrome)
- `TagColor` palette — keep for kanban columns and database select options

### Phase 4 (future): Reintroduce intentional accent color

After living with neutral for a while, selectively add back a "burnt red" / oxide accent for a small number of high-signal UI moments. This is a separate ticket — don't do it in this pass.

## Acceptance Criteria

- [ ] No blue accent color remains in the app UI
- [ ] All primary interactive elements (buttons, selections, focus states) use neutral black/gray tones
- [ ] `Brand.primary` red only appears in the app icon — not in interactive UI elements
- [ ] Functional status colors (error, success, warning) still work and are visually distinct
- [ ] Block and tag color palettes are untouched
- [ ] Light mode and dark mode both look intentional and consistent
- [ ] No accessibility regressions — contrast ratios still meet WCAG AA for all interactive elements

## Notes

- This is a "reset to neutral" pass. Resist the urge to pick a new accent color during this work.
- When in doubt, look at how YouTube, Linear, or iA Writer handle neutral UI with a colored logo.
- Test with both light and dark mode at every step.
