import SwiftUI
import PhotosUI

struct MobileRootView: View {
    @State private var workspace = MobileWorkspaceService()
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showAgents = false
    @State private var captureText = ""
    @State private var fileTree: [MobileNoteFile] = []
    @State private var recentFiles: [MobileNoteFile] = []
    @State private var favorites: [MobileNoteFile] = []
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var captureFieldFocused: Bool

    private var filteredRecentFiles: [MobileNoteFile] {
        let dailyPath = workspace.dailyNotePath()
        return recentFiles.filter { $0.path != dailyPath }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5: return "Late night"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var todayString: String {
        Self.todayFormatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    captureZone
                    todayCard
                    favoritesSection
                    if !filteredRecentFiles.isEmpty {
                        recentSection
                    }
                    if !fileTree.isEmpty {
                        allFilesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.mobileBgPrimary)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(greeting)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mobileTextPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                    }
                    .help("Search")
                }
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
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                    }
                    .help("More")
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.mobileBgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
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
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, newItem in
                if let newItem {
                    Task { await handlePhotoSelection(newItem) }
                }
            }
        }
    }

    // MARK: - 1. Capture Zone (Priority #1)

    private var captureZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("What's on your mind?", text: $captureText, axis: .vertical)
                .font(.system(size: 17))
                .lineLimit(2...6)
                .focused($captureFieldFocused)
                .submitLabel(.send)
                .onSubmit { submitCapture() }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, captureText.trimmingCharacters(in: .whitespaces).isEmpty && !captureFieldFocused ? 14 : 8)

            // Media icons + send button — visible when focused or has text
            if captureFieldFocused || !captureText.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Button { showPhotoPicker = true } label: {
                            Image(systemName: "camera")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mobileTextMuted)
                        }
                        .help("Attach photo")
                        Button { /* TODO: voice recording */ } label: {
                            Image(systemName: "mic")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mobileTextMuted)
                        }
                        .help("Voice note")
                        Button { /* TODO: link paste */ } label: {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.mobileTextMuted)
                        }
                        .help("Paste link")
                    }

                    Spacer()

                    if !captureText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { submitCapture() } label: {
                            Text("Add to today")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color.mobileCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(captureFieldFocused ? Color.accentColor.opacity(0.4) : Color.mobileBorder, lineWidth: captureFieldFocused ? 1.5 : 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: captureFieldFocused)
    }

    // MARK: - Today Card

    private var todayCard: some View {
        NavigationLink {
            let note = workspace.openOrCreateDailyNote() ?? MobileNoteFile(path: workspace.dailyNotePath(), name: todayString)
            MobilePageEditorView(note: note, workspace: workspace)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todayString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mobileTextPrimary)
                    let preview = dailyNotePreview()
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mobileTextSecondary)
                            .lineLimit(2)
                    } else {
                        Text("Start today's note")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.mobileTextMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.mobileTextSecondary)
            }
            .mobileCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Favorites (Priority #2)

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mobileTextPrimary)
                .padding(.leading, 2)

            if favorites.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mobileTextMuted)
                    Text("Pin your most-used pages from the desktop sidebar")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mobileTextMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mobileCardBg)
                .clipShape(RoundedRectangle(cornerRadius: MobileRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: MobileRadius.lg)
                        .stroke(Color.mobileBorder, lineWidth: 0.5)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favorites.prefix(4)) { file in
                            NavigationLink {
                                if file.isDatabase {
                                    MobileDatabaseView(dbPath: file.path)
                                } else {
                                    MobilePageEditorView(note: file, workspace: workspace)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if let icon = file.icon, !icon.isEmpty {
                                        Text(icon).font(.system(size: 13))
                                    } else {
                                        Image(systemName: file.isDatabase ? "tablecells" : "doc.text")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.mobileTextSecondary)
                                    }
                                    Text(file.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.mobileTextPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.mobileCardBg)
                                .clipShape(RoundedRectangle(cornerRadius: MobileRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MobileRadius.md)
                                        .stroke(Color.mobileBorder, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Recent (Priority #3)

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mobileTextPrimary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(filteredRecentFiles) { file in
                    NavigationLink {
                        if file.isDatabase {
                            MobileDatabaseView(dbPath: file.path)
                        } else {
                            MobilePageEditorView(note: file, workspace: workspace)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = file.icon, !icon.isEmpty {
                                Text(icon).font(.system(size: 14))
                                    .frame(width: 22)
                            } else {
                                Image(systemName: file.isDatabase ? "tablecells" : "doc.text")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mobileTextSecondary)
                                    .frame(width: 22)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: file))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.mobileTextPrimary)
                                    .lineLimit(1)
                                if let preview = firstLinePreview(for: file), !preview.isEmpty {
                                    Text(preview)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mobileTextMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let date = file.modifiedAt {
                                Text(relativeTime(from: date))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mobileTextMuted)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)

                    if file.id != filteredRecentFiles.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color.mobileCardBg)
            .clipShape(RoundedRectangle(cornerRadius: MobileRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: MobileRadius.lg)
                    .stroke(Color.mobileBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - All Files

    private var allFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All files")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.mobileTextPrimary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(fileTree) { node in
                    UnifiedFileRow(node: node, workspace: workspace)

                    if node.id != fileTree.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .background(Color.mobileCardBg)
            .clipShape(RoundedRectangle(cornerRadius: MobileRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: MobileRadius.lg)
                    .stroke(Color.mobileBorder, lineWidth: 0.5)
            )
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
        captureFieldFocused = false
        refresh()
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "capture-\(formatter.string(from: Date())).jpg"

        let imagesDir = (workspace.workspacePath as NSString).appendingPathComponent("Attachments")
        try? FileManager.default.createDirectory(atPath: imagesDir, withIntermediateDirectories: true)
        let imagePath = (imagesDir as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: imagePath))

        guard let note = workspace.openOrCreateDailyNote() else { return }
        var content = workspace.loadFile(at: note.path)
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        content += "![capture](Attachments/\(filename))\n"
        workspace.saveFile(at: note.path, content: content)

        await MainActor.run { refresh() }
    }

    private func refresh() {
        fileTree = workspace.buildHierarchicalFileTree()
        recentFiles = workspace.recentFiles(limit: 8)
        loadFavorites()
    }

    private func loadFavorites() {
        let key = "favorites_\(workspace.workspacePath)"
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        favorites = paths.compactMap { path -> MobileNoteFile? in
            let fm = FileManager.default
            guard fm.fileExists(atPath: path) else { return nil }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            let isDb = fm.fileExists(atPath: (path as NSString).appendingPathComponent("_schema.json"))
            let icon = isDir.boolValue ? nil : workspace.loadFileIcon(at: path)
            return MobileNoteFile(path: path, name: name, isDirectory: isDir.boolValue, isDatabase: isDb, icon: icon)
        }
    }

    private func dailyNotePreview() -> String {
        let path = workspace.dailyNotePath()
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        let content = workspace.loadFile(at: path)
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .prefix(2)
            .joined(separator: " ")
    }

    private func firstLinePreview(for file: MobileNoteFile) -> String? {
        guard !file.isDatabase, !file.isDirectory else { return nil }
        let content = workspace.loadFile(at: file.path)
        guard let line = content.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("<!--") }),
              !line.isEmpty else { return nil }
        return line.count > 80 ? String(line.prefix(80)) + "..." : line
    }

    private func displayName(for file: MobileNoteFile) -> String {
        let name = file.name
        if name.count == 10, name.dropFirst(4).first == "-", name.dropFirst(7).first == "-" {
            if let date = Self.isoDateFormatter.date(from: name) {
                return Self.todayFormatter.string(from: date)
            }
        }
        return name
    }

    // MARK: - Helpers

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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
                    .frame(width: 22)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mobileTextSecondary)
                    .frame(width: 22)
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
