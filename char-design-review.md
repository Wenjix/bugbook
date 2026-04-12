# Char Design Review — UI/UX Patterns for Dahso Meetings

**Date:** 2026-03-27
**Subject:** Char (char.com) — AI notepad for private meetings
**Purpose:** Identify design patterns and inspiration points for Dahso's meeting experience

---

## 1. Char Product Overview

Char (formerly Hyprnote) is a YC-backed, open-source AI meeting notepad with 8k+ GitHub stars. Built with Tauri + React + Rust, it positions itself as a "privacy-first AI notepad" — no bots joining calls, local-first data in SQLite, and BYOLLM support (Ollama, Claude, Gemini). The design philosophy is "Apple Notes for meetings": open it, start typing, the app handles the rest.

Tech stack: 45% Rust, 42% TypeScript, React frontend, Tauri desktop shell, SQLite persistence.

---

## 2. Char UI Patterns — Key Screens

### 2a. Session Layout (During a Meeting)

The core screen is a **single-session view** with a tabbed content area:

- **Outer header:** Minimal bar with folder breadcrumbs (left), and three buttons (right): Listen, Metadata, Overflow. The metadata button expands to show date and participant info. The listen button controls recording state. Clean, uncluttered.

- **Inner header (tab bar):** Four tabs accessible via keyboard shortcuts:
  - `Alt+M` — Raw/Memos (user's handwritten notes)
  - `Alt+S` — Enhanced/Summary (AI-generated from notes + transcript)
  - `Alt+T` — Transcript (real-time speech-to-text)
  - Attachments (when files exist)

- **Content area:** Full-height scrollable editor with scroll-fade overlays at top/bottom edges. Click-to-focus delegation. Different overflow behavior per tab (scrollable for notes/enhanced, fixed for transcript).

- **Floating action button:** Centered at bottom (`absolute bottom-4 left-1/2`), stone-colored button with recording icon. Only appears in raw notes tab when no transcript exists yet. Spinner replaces icon during active recording. Shadow effect for elevation. Tooltip shows configuration warnings.

### 2b. Recording State Machine

Char tracks four visual states for session tabs:

| State | Trigger | Visual |
|---|---|---|
| `listening` | Active recording | Recording indicator |
| `listening-degraded` | Recording with quality issues | Degraded indicator |
| `finalizing` | Wrapping up session | Finalizing spinner |
| `processing` | Background enhancement (unfocused tab) | Processing badge |
| (none) | Idle / complete | Clean tab |

This is a thoughtful model. The "degraded" state handles real-world audio issues gracefully rather than pretending they don't exist. The "processing" state only shows on unfocused tabs, keeping the active session clean.

### 2c. Post-Meeting Summary

After recording ends, Char generates summaries using customizable templates:

- **Template system:** Users choose from predefined formats (bullet points, agenda-based, paragraph) or community-contributed templates. A "Use template" button opens a popover with search, suggested templates ranked by meeting content relevance, and favorites.

- **Summary presentation:** Structured markdown with topic headers (e.g., "Mobile UI Update and API Adjustments") and bullet points underneath. Clean section delineation.

- **Source verification:** Hovering over any AI-generated summary point shows the exact transcript quote it came from. This is a standout trust-building pattern.

- **Edit approval flow:** When AI proposes changes, a diff view shows current vs. proposed content with Approve/Decline buttons. The user stays in control.

### 2d. Session Preview Cards

In timeline/list views, hovering over a session shows a preview card:

- Title, date formatted as "MMM d, yyyy · h:mm a"
- Up to 3 participant names, "+X more" for overflow
- 200-character content preview with mask gradient fade
- Embedded images extracted as full-width preview
- Cursor-following animation with spring physics
- Max height 128px

### 2e. Sidebar Navigation

70px-wide sidebar with three zones:

- **Header:** Platform controls, devtool toggle, collapse button (`Cmd+\`)
- **Content:** Context-sensitive — shows either Search Results or Timeline by default, switches to Settings/Calendar/Contacts/Templates nav when those tabs are active
- **Footer:** Profile section (expandable), toast notifications

### 2f. Daily View

Date-organized timeline with:
- Date headers
- Lazy-loaded note cards
- Note editor inline
- "Today" button for quick navigation

---

## 3. Dahso's Current Meeting Experience

### 3a. Architecture

Dahso's meeting support is **calendar-centric**, not session-centric:

1. **CalendarService** syncs Google Calendar events to local SQLite
2. **WorkspaceCalendarView** displays day/week/month views with events
3. **CalendarDayView / CalendarWeekView** render time grids with event blocks
4. When user taps an event, **MeetingNoteService** creates a markdown page with:
   - Title, date, time, location, meeting link
   - Attendees as wikilinks (with response status icons)
   - Empty "Notes" and "Action Items" sections
   - Event description

### 3b. What Dahso Has

- Clean calendar views (day/week/month) with Google Calendar sync
- Notion-style week view headers ("Sun 15")
- Current-time indicator with red dot + line
- Event blocks with left color accent bar, hover states
- Database overlay items on calendar
- One-click meeting note creation from calendar events
- Auto-generated person pages for attendees with wikilink backlinks
- Source picker for calendar filtering

### 3c. What Dahso Lacks (Compared to Char)

- No audio capture or real-time transcription
- No AI-generated summaries from meeting content
- No "during meeting" state — the experience is pre-meeting (calendar) and post-meeting (static markdown page)
- No meeting-specific template system
- No session state machine (listening, processing, etc.)
- No floating recording controls
- No meeting list/timeline view outside the calendar
- No preview cards for past meetings
- No source verification for AI-generated content

---

## 4. Side-by-Side Comparison

| Dimension | Char | Dahso |
|---|---|---|
| **Primary metaphor** | Notepad (session-centric) | Calendar (event-centric) |
| **Meeting lifecycle** | Before → During (recording + notes) → After (summary + chat) | Before (calendar event) → After (static markdown) |
| **During-meeting UX** | Tabbed editor with raw notes, live transcript, floating record button | None — user manually writes in the generated markdown page |
| **AI integration** | Real-time transcription, template-based summary generation, in-note chat, source verification | None for meetings specifically |
| **Information density** | Moderate — focused on one session at a time | Low in note, high in calendar view |
| **State transitions** | 4 visual states with smooth transitions | No meeting-specific states |
| **Meeting discovery** | Timeline/daily view with preview cards | Calendar views only |
| **Template system** | Rich — searchable, ranked by relevance, community-contributed | Fixed markdown template in MeetingNoteService |
| **Data format** | SQLite + markdown export | Markdown files (local-first, Obsidian-compatible) |
| **Privacy model** | Local-first, BYOLLM, no bots | Local-first, Google Calendar OAuth |

---

## 5. Actionable Design Recommendations

### Recommendation 1: Add a Meeting Timeline View

**What:** Create a dedicated "Meetings" view (distinct from the calendar) that shows a chronological list of past and upcoming meetings with preview cards. Think of it as a filtered, meeting-only timeline.

**Why:** Char's daily/timeline view makes it trivial to find "that meeting from last Tuesday." Dahso's calendar is great for planning but poor for retrieval. Users need a meeting-specific entry point.

**How:** Filter pages created by MeetingNoteService, display as a list with: title, date, attendee count, and a 2-line content preview. Add a "Meetings" tab in the sidebar or as a view mode alongside the calendar.

### Recommendation 2: Introduce Meeting Note Templates

**What:** Replace the single hardcoded markdown template in MeetingNoteService with a selectable template system. Start with 3-4 built-in options: "Standard" (current), "1:1", "Standup", "Decision Log."

**Why:** Char's template system (with search, favorites, and relevance ranking) is one of their strongest UX patterns. Different meetings need different structures. A 1:1 has "discussion topics" and "follow-ups"; a standup has "yesterday/today/blockers."

**How:** Store templates as markdown files in a `.dahso/templates/meetings/` directory. Add a template picker when creating a meeting note (small popover on the calendar event tap, or a dropdown in the generated page header). The current `buildMeetingNoteContent` becomes one template among several.

### Recommendation 3: Design a "During Meeting" State

**What:** When a meeting is happening right now (based on calendar start/end time), give the meeting note page a distinct visual treatment: a subtle recording-style indicator in the page header, a floating "meeting in progress" badge, and quick-access buttons for the conference link and attendee list.

**Why:** Char's entire design centers on the "during meeting" experience. Dahso doesn't need audio recording to benefit from this — just acknowledging that the user is currently in a meeting and surfacing relevant context (join link, attendees, agenda) creates a more intentional experience.

**How:** Check if `Date()` falls between `event.startDate` and `event.endDate`. If so, show a compact meeting bar at the top of the note page with: a pulsing dot + "In Progress", a "Join" button (links to conferenceURL), and collapsible attendee chips. After the meeting ends, this bar transitions to "Meeting ended — review your notes" with a prompt to add action items.

### Recommendation 4: Add Source-Linked AI Summaries

**What:** After a user finishes writing meeting notes, offer a "Summarize" action that uses Dahso's existing AiService to generate a structured summary from the raw notes. Display the summary in a distinct section with visual differentiation (lighter background, different typography) and link each summary point back to the source paragraph.

**Why:** Char's source verification pattern (hover to see the exact transcript quote) is their most trust-building feature. Even without transcription, applying this to user-written notes adds value: the AI highlights key points, and the user can verify each one traces back to what they actually wrote.

**How:** Add a "Summarize Notes" button to meeting pages. Generate a summary using AiService, render it in a collapsible section below the user's notes with a subtle border or background. Each bullet links to the source paragraph anchor. Include "Regenerate" and "Dismiss" controls.

### Recommendation 5: Improve the Calendar-to-Note Transition

**What:** When tapping a calendar event, instead of immediately navigating to a full page, show a compact event detail popover with: title, time, attendees, join link, and a prominent "Open Notes" or "Create Notes" button. For events that already have linked notes, show a 2-line preview of the notes content.

**Why:** Char's session preview cards (hover to see title, date, participants, content preview with gradient fade) create a lightweight discovery layer before committing to a full view. Dahso currently jumps straight from calendar event to full page, which breaks flow when you're scanning your calendar.

**How:** Add a popover on event tap (instead of immediate navigation) using the existing CalendarEvent data. Show metadata, attendee avatars/initials, join link button, and either "Create Meeting Note" or a preview of existing linked notes. The user clicks through to the full page only when ready.

---

## 6. Design Principles to Borrow

Beyond specific features, Char embodies a few design principles worth adopting:

- **State awareness:** The UI acknowledges what phase of a meeting the user is in (before, during, after) and adapts accordingly. Dahso currently treats all meetings the same regardless of temporal context.

- **Progressive disclosure:** Char shows a minimal floating button during recording, tabs for different content types, and expandable metadata. Information appears when relevant, not all at once.

- **Trust through transparency:** Source verification, edit approval flows, and the diff view for AI changes all reinforce user control. Any AI features Dahso adds to meetings should follow this pattern.

- **Keyboard-first navigation:** Alt+M/S/T for tab switching, Cmd+\ for sidebar. Meeting workflows benefit from keeping hands on keyboard.

---

## Sources

- [Char website](https://char.com)
- [Char GitHub repo](https://github.com/fastrepl/char) (8k+ stars, Tauri + React + Rust)
- [Char on Product Hunt](https://www.producthunt.com/products/hyprnote)
- [Char on Y Combinator](https://www.ycombinator.com/companies/char)
- [Char blog — AI Meeting Summary Tools](https://char.com/blog/ai-meeting-summary-tools/)
- [Char blog — Open Source Meeting Transcription](https://char.com/blog/open-source-meeting-transcription-software/)
- [Char template gallery](https://char.com/gallery/)
