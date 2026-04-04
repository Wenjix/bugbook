import SwiftUI

struct MobileRootView: View {
    @State private var workspace = MobileWorkspaceService()
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showAgents = false
    @State private var captureText = ""
    @State private var fileTree: [MobileNoteFile] = []
    @State private var recentFiles: [MobileNoteFile] = []
    @State private var showCaptureExpanded = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    captureBar
                    recentSection
                    allFilesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .navigationTitle("Bugbook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: .constant(""), placement: .navigationBarDrawer(displayMode: .always), prompt: "Search notes...")
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { _ = workspace.createNote(); refresh() } label: {
                            Label("New Note", systemImage: "doc.badge.plus")
                        }
                        Divider()
                        Button { showAgents = true } label: {
                            Label("Agents", systemImage: "cpu")
                        }
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("More options")
                }
            }
            .onAppear { refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refresh() }
            }
            .sheet(isPresented: $showSettings) {
                MobileSettingsView(workspace: workspace)
            }
            .sheet(isPresented: $showAgents) {
                NavigationStack {
                    MobileAgentHubView(workspacePath: workspace.workspacePath)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showAgents = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showSearch) {
                MobileSearchView(workspacePath: workspace.workspacePath, workspace: workspace)
            }
        }
    }

    // MARK: - Quick Capture

    private var captureBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)

            TextField("Capture a thought...", text: $captureText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit { submitCapture() }

            if !captureText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    submitCapture()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }
                .help("Send to daily note")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.mobileCardBg)
        .clipShape(RoundedRectangle(cornerRadius: MobileRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: MobileRadius.lg)
                .stroke(Color.mobileBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Recent

    private var recentSection: some View {
        Group {
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.mobileTextMuted)
                        .tracking(0.6)
                        .padding(.leading, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Daily note card
                            NavigationLink {
                                let note = workspace.openOrCreateDailyNote() ?? MobileNoteFile(path: workspace.dailyNotePath(), name: todayDateString)
                                MobilePageEditorView(note: note, workspace: workspace)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Image(systemName: "sun.max")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.orange)
                                    Text("Today")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.mobileTextPrimary)
                                    Text(shortDateString)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.mobileTextMuted)
                                }
                                .frame(width: 90, alignment: .leading)
                                .mobileCard(padding: 10)
                            }
                            .buttonStyle(.plain)

                            ForEach(recentFiles.prefix(6)) { file in
                                NavigationLink {
                                    if file.isDatabase {
                                        MobileDatabaseView(dbPath: file.path)
                                    } else {
                                        MobilePageEditorView(note: file, workspace: workspace)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Image(systemName: file.isDatabase ? "tablecells" : "doc.text")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.mobileTextSecondary)
                                        Text(file.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Color.mobileTextPrimary)
                                            .lineLimit(1)
                                        if let date = file.modifiedAt {
                                            Text(relativeTime(from: date))
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color.mobileTextMuted)
                                        }
                                    }
                                    .frame(width: 90, alignment: .leading)
                                    .mobileCard(padding: 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - All Files

    private var allFilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALL FILES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.mobileTextMuted)
                .tracking(0.6)
                .padding(.leading, 4)

            if fileTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.mobileTextMuted)
                    Text("No files yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mobileTextSecondary)
                    Text("Capture a thought above to get started")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mobileTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(fileTree) { node in
                        UnifiedFileRow(node: node, workspace: workspace)

                        if node.id != fileTree.last?.id {
                            Divider().foregroundStyle(Color.mobileDivider)
                        }
                    }
                }
                .mobileCard(padding: 0)
            }
        }
    }

    // MARK: - Actions

    private func submitCapture() {
        let text = captureText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let note = workspace.openOrCreateDailyNote() else { return }

        var content = workspace.loadFile(at: note.path)
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        content += text + "\n"
        workspace.saveFile(at: note.path, content: content)

        captureText = ""
        refresh()
    }

    private func refresh() {
        workspace.refreshFiles()
        fileTree = workspace.buildHierarchicalFileTree()
        recentFiles = workspace.recentFiles(limit: 6)
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var shortDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(from date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Unified File Row

private struct UnifiedFileRow: View {
    let node: MobileNoteFile
    var workspace: MobileWorkspaceService

    @State private var isExpanded = false

    private var hasChildren: Bool {
        (node.isDirectory && !node.isDatabase) || (node.children != nil && !node.children!.isEmpty && !node.isDatabase)
    }

    var body: some View {
        if hasChildren {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        UnifiedFileRow(node: child, workspace: workspace)
                    }
                }
            } label: {
                rowLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else {
            NavigationLink {
                if node.isDatabase {
                    MobileDatabaseView(dbPath: node.path)
                } else {
                    MobilePageEditorView(note: node, workspace: workspace)
                }
            } label: {
                rowLabel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            if let icon = node.icon, !icon.isEmpty,
               icon.unicodeScalars.first?.properties.isEmoji == true {
                Text(icon).font(.system(size: 14))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mobileTextSecondary)
                    .frame(width: 18)
            }
            Text(node.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.mobileTextPrimary)
                .lineLimit(1)
        }
    }

    private var iconName: String {
        if node.isDatabase { return "tablecells" }
        if node.isDirectory { return "folder" }
        return "doc.text"
    }
}
