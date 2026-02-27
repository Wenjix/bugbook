import SwiftUI

struct MobileRootView: View {
    @StateObject private var workspace = MobileWorkspaceService()

    var body: some View {
        TabView {
            MobileNotesView(workspace: workspace)
                .tabItem {
                    Label("Notes", systemImage: "doc.text")
                }

            MobileAgentHubView(workspacePath: workspace.workspacePath)
                .tabItem {
                    Label("Agent Hub", systemImage: "list.bullet.clipboard")
                }
        }
    }
}
