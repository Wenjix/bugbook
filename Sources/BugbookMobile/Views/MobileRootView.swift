import SwiftUI

struct MobileRootView: View {
    @State private var workspace = MobileWorkspaceService()
    @State private var showSearch = false

    var body: some View {
        TabView {
            MobileTodayView(workspace: workspace)
                .tabItem {
                    Label("Today", systemImage: "house")
                }

            MobileNotesView(workspace: workspace)
                .tabItem {
                    Label("Notes", systemImage: "folder")
                }

            MobileDatabaseListView(workspacePath: workspace.workspacePath)
                .tabItem {
                    Label("Databases", systemImage: "tablecells")
                }

            MobileAgentHubView(workspacePath: workspace.workspacePath)
                .tabItem {
                    Label("Agent Hub", systemImage: "list.bullet.clipboard")
                }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            MobileSearchView(workspacePath: workspace.workspacePath, workspace: workspace)
        }
    }
}
