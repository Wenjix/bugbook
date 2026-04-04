import SwiftUI

struct MobilePageEditorView: View {
    let note: MobileNoteFile

    var workspace: MobileWorkspaceService
    @Environment(\.scenePhase) private var scenePhase

    @State private var content: String = ""
    @State private var blocks: [EditableBlock] = []
    @State private var frontmatter: String = ""  // preserved on edit, prepended on save
    @State private var isLoaded = false
    @State private var isEditing = false
    @State private var hasUnsavedChanges = false
    @State private var debounceTimer: Timer?
    @State private var focusedBlockId: UUID?

    private var pageTitle: String {
        let filename = (note.path as NSString).lastPathComponent
        if filename.hasSuffix(".md") {
            return String(filename.dropLast(3))
        }
        return filename
    }

    var body: some View {
        Group {
            if !isLoaded {
                ProgressView()
            } else if isEditing {
                VStack(spacing: 0) {
                    ScrollView {
                        MobileBlockEditorView(
                            blocks: $blocks,
                            onBlocksChanged: { scheduleSave() }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    BlockEditingToolbar(
                        blocks: $blocks,
                        focusedBlockId: focusedBlockId,
                        onBlocksChanged: { scheduleSave() }
                    )
                }
            } else {
                ScrollView {
                    MobileMarkdownView(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    enterEditMode()
                }
            }
        }
        .navigationTitle(pageTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if isEditing {
                        exitEditMode()
                    } else {
                        enterEditMode()
                    }
                } label: {
                    Label(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                }
                .help(isEditing ? "Finish editing" : "Edit page")
            }
        }
        .onAppear {
            content = workspace.loadFile(at: note.path)
            frontmatter = extractFrontmatter(from: content)
            blocks = BlockMarkdownConverter.parse(content)
            isLoaded = true
        }
        .onDisappear {
            saveNow()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                saveNow()
            }
        }
    }

    private func enterEditMode() {
        blocks = BlockMarkdownConverter.parse(content)
        isEditing = true
    }

    private func exitEditMode() {
        saveNow()
        content = BlockMarkdownConverter.serialize(blocks)
        isEditing = false
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            saveNow()
        }
    }

    private func saveNow() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let body = BlockMarkdownConverter.serialize(blocks)
        let serialized = frontmatter.isEmpty ? body : frontmatter + "\n" + body
        content = serialized
        workspace.saveFile(at: note.path, content: serialized)
    }

    /// Extract YAML frontmatter + HTML comments from the start of a file
    private func extractFrontmatter(from text: String) -> String {
        var lines: [String] = []
        let allLines = text.components(separatedBy: .newlines)
        var i = 0

        // YAML frontmatter
        if i < allLines.count && allLines[i].trimmingCharacters(in: .whitespaces) == "---" {
            lines.append(allLines[i])
            i += 1
            while i < allLines.count {
                lines.append(allLines[i])
                if allLines[i].trimmingCharacters(in: .whitespaces) == "---" { i += 1; break }
                i += 1
            }
        }

        // HTML comments
        while i < allLines.count && allLines[i].trimmingCharacters(in: .whitespaces).hasPrefix("<!--") {
            lines.append(allLines[i])
            i += 1
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }
}
