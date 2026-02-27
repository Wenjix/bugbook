import SwiftUI

struct MobileNotesView: View {
    @ObservedObject var workspace: MobileWorkspaceService

    var body: some View {
        NavigationStack {
            List(workspace.files) { note in
                NavigationLink {
                    MobilePageEditorView(note: note, workspace: workspace)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.name)
                            .font(.system(size: 16, weight: .medium))
                        Text(note.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem {
                    Button {
                        _ = workspace.createNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                workspace.refreshFiles()
            }
        }
    }
}
