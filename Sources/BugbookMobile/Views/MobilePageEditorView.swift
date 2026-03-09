import SwiftUI

struct MobilePageEditorView: View {
    let note: MobileNoteFile

    var workspace: MobileWorkspaceService
    @Environment(\.scenePhase) private var scenePhase

    @State private var content: String = ""
    @State private var isLoaded = false
    @State private var isEditing = false
    @State private var hasUnsavedChanges = false
    @State private var debounceTimer: Timer?

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
                TextEditor(text: $content)
                    .padding(12)
                    .font(.body)
                    .onChange(of: content) { _, _ in
                        scheduleSave()
                    }
            } else {
                ScrollView {
                    MobileMarkdownView(content: content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
        .navigationTitle(pageTitle)
        .toolbar {
            ToolbarItem {
                Button {
                    if isEditing { saveNow() }
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "Preview" : "Edit", systemImage: isEditing ? "pencil.slash" : "pencil")
                }
            }
        }
        .onAppear {
            content = workspace.loadFile(at: note.path)
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
        workspace.saveFile(at: note.path, content: content)
    }
}
