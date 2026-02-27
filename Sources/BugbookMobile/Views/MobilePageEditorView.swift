import SwiftUI

struct MobilePageEditorView: View {
    let note: MobileNoteFile

    @ObservedObject var workspace: MobileWorkspaceService
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $content)
                .padding(12)
                .font(.system(size: 16, design: .default))
        }
        .navigationTitle(note.name)
        .toolbar {
            ToolbarItem {
                Button("Save") {
                    workspace.saveFile(at: note.path, content: content)
                    workspace.refreshFiles()
                }
            }
        }
        .onAppear {
            content = workspace.loadFile(at: note.path)
        }
        .onDisappear {
            workspace.saveFile(at: note.path, content: content)
            workspace.refreshFiles()
        }
    }
}
