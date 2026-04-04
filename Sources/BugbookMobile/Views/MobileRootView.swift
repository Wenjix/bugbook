import SwiftUI

struct MobileRootView: View {
    @State private var workspace = MobileWorkspaceService()
    @State private var showSearch = false
    @State private var selectedTab: MobileTab = .today

    enum MobileTab: String {
        case today, notes, databases, agents, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileTodayView(workspace: workspace)
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(MobileTab.today)

            MobileNotesView(workspace: workspace)
                .tabItem {
                    Label("Notes", systemImage: "doc.text")
                }
                .tag(MobileTab.notes)

            MobileDatabaseListView(workspacePath: workspace.workspacePath)
                .tabItem {
                    Label("Databases", systemImage: "tablecells")
                }
                .tag(MobileTab.databases)

            MobileAgentHubView(workspacePath: workspace.workspacePath)
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
                .tag(MobileTab.agents)

            MobileSettingsView(workspace: workspace)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(MobileTab.settings)
        }
    }
}
