# Dahso Smoke Test Checklist

## Workspace & File Management
- [ ] Open workspace folder via menu
- [ ] Recent workspaces appear and are clickable
- [ ] Default workspace created on first launch
- [ ] File tree shows folders, notes, databases, canvases
- [ ] Create new note (Cmd+N)
- [ ] Create new folder (context menu)
- [ ] Create new database (context menu)
- [ ] Create new canvas (context menu)
- [ ] Rename file (context menu)
- [ ] Delete file (context menu) — confirm dialog appears
- [ ] Deleted note closes its open tab
- [ ] Duplicate file (context menu)

## Editor
- [ ] Open a note — content loads correctly
- [ ] Type in title block — no extra dots/lines appear
- [ ] Create new blocks: paragraph, headings 1-3, bullet list, numbered list, todo, toggle, code block
- [ ] Block type shortcuts (Cmd+Shift+0-9) work
- [ ] Drag handle appears on hover
- [ ] Drag handle click opens block menu (not color picker)
- [ ] Block menu: delete, duplicate, turn-into work
- [ ] Shift+click selects range of blocks
- [ ] Cmd+A selects all blocks
- [ ] Backspace deletes selected blocks
- [ ] Markdown shortcuts work: #, ##, ###, -, 1., [], ```, >
- [ ] Inline formatting: bold (Cmd+B), italic (Cmd+I), code, strikethrough
- [ ] Save (Cmd+S) persists changes

## Tabs & Navigation
- [ ] Open multiple tabs
- [ ] Close tab (Cmd+W)
- [ ] Switch tabs by clicking
- [ ] Tab bar matches main body color (2-tone, not 3)
- [ ] Back/Forward navigation (Cmd+[, Cmd+])
- [ ] Quick Open (Cmd+K or Cmd+P)
- [ ] Breadcrumb shows file hierarchy

## Canvas
- [ ] Create and open a canvas
- [ ] Double-click background creates text node
- [ ] Add text node via toolbar
- [ ] Add page node via toolbar file picker
- [ ] Paste image onto canvas
- [ ] Drag nodes to reposition
- [ ] Resize nodes via handle
- [ ] Drag anchor dots to create edges
- [ ] Click edge to select it
- [ ] Delete selected node/edge (Delete or Backspace)
- [ ] Shift+click for multi-node selection
- [ ] Pan canvas by dragging background
- [ ] Cmd+scroll to zoom
- [ ] Pinch to zoom
- [ ] Zoom controls in toolbar work
- [ ] Undo/redo (Cmd+Z / Cmd+Shift+Z)
- [ ] Dot grid background visible and scales with zoom
- [ ] Auto-save triggers on changes
- [ ] Double-click file node navigates to file

## Database
- [ ] Create and open a database
- [ ] Table view shows rows and columns
- [ ] Add new row
- [ ] Edit cell values
- [ ] Add/remove columns
- [ ] Sort and filter

## AI Features
- [ ] Open AI panel (Cmd+I)
- [ ] Send a chat message
- [ ] AI response appears
- [ ] Reference files show note titles (not paths)
- [ ] App icon (DahsoLogo) shown in chat

## Agent Hub
- [ ] Open Agent Hub (Cmd+Shift+J)
- [ ] Workspace name shown (not full path)
- [ ] Empty state message is clean

## Templates
- [ ] Template picker opens
- [ ] Templates folder auto-created if missing
- [ ] Save note as template works
- [ ] Apply template to new note

## Settings
- [ ] Open settings (Cmd+,)
- [ ] General settings load
- [ ] Appearance settings load
- [ ] Theme toggle works (Cmd+Shift+L)

## Dark Mode
- [ ] App uses 2-tone color scheme (not 3)
- [ ] Accent color is blue (not red)
- [ ] All text is readable against backgrounds
- [ ] Sidebar and editor backgrounds are consistent

## Keyboard Shortcuts
- [ ] Cmd+N — new note
- [ ] Cmd+T — new tab
- [ ] Cmd+W — close tab
- [ ] Cmd+S — save
- [ ] Cmd+K / Cmd+P — quick open
- [ ] Cmd+. — toggle sidebar
- [ ] Cmd+I — AI panel
- [ ] Cmd+Shift+J — Agent Hub
- [ ] Cmd+Shift+D — daily note
- [ ] Cmd+Shift+G — graph view
- [ ] Cmd+Shift+L — toggle theme
- [ ] Cmd+[ / Cmd+] — back/forward

## Graph View
- [ ] Open graph view
- [ ] Nodes represent notes
- [ ] Edges represent links/backlinks
- [ ] Click node navigates to note

## Performance
- [ ] App launches within 3 seconds
- [ ] Opening a note loads within 500ms
- [ ] Typing has no perceptible lag
- [ ] Canvas panning/zooming is smooth
- [ ] File tree expands/collapses smoothly
