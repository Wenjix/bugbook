import SwiftUI
import PhotosUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct MobileRootView: View {
    @State private var workspace = MobileWorkspaceService()
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showAgents = false
    @State private var showAllFavorites = false
    @State private var fileTree: [MobileNoteFile] = []
    @State private var recentItems: [MobileRecentItem] = []
    @State private var favorites: [MobileNoteFile] = []
    @State private var showPhotoPicker = false
    @State private var showPhotoSourceOptions = false
    @State private var showCameraCapture = false
    @State private var showNoteComposer = false
    @State private var showLinkComposer = false
    @State private var showAudioRecorder = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCaptureMenu = false
    @State private var didOpenMenuFromLongPress = false
    @State private var pendingPhotoCapture: PendingPhotoCapture?
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    @Environment(\.scenePhase) private var scenePhase

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    private var todayString: String {
        Self.todayFormatter.string(from: Date())
    }

    private var displayedFavorites: [MobileNoteFile] {
        Array(favorites.prefix(4))
    }

    var body: some View {
        NavigationStack {
            configuredRootContent
                .onAppear { Task { await refresh() } }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await refresh() }
                    }
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
                .sheet(isPresented: $showAllFavorites) {
                    MobileFavoritesSheet(favorites: favorites, workspace: workspace)
                }
                .sheet(isPresented: $showNoteComposer) {
                    MobileQuickNoteSheet(
                        onSubmit: { text in
                            createQuickNote(text)
                        },
                        onCreatePhotoAttachment: { data in
                            imageAttachmentMarkdown(from: data)
                        },
                        onCreateAudioAttachment: { recordingURL in
                            audioAttachmentMarkdown(from: recordingURL)
                        }
                    )
                }
                .sheet(isPresented: $showLinkComposer) {
                    MobileLinkCaptureSheet { url, title in
                        captureLink(urlString: url, title: title)
                    }
                }
                .sheet(isPresented: $showAudioRecorder) {
                    MobileAudioRecorderSheet { recordingURL in
                        handleRecordedAudio(recordingURL)
                    }
                }
                .sheet(item: $pendingPhotoCapture) { capture in
                    MobilePhotoCaptureSheet(imageData: capture.data) { caption in
                        persistImageCapture(data: capture.data, caption: caption)
                        pendingPhotoCapture = nil
                    }
                }
                #if canImport(UIKit)
                .sheet(isPresented: $showCameraCapture) {
                    MobileCameraCaptureView(
                        onCapture: { image in
                            showCameraCapture = false
                            handleCapturedImage(image)
                        },
                        onCancel: {
                            showCameraCapture = false
                        }
                    )
                    .ignoresSafeArea()
                }
                #endif
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
                .onChange(of: selectedPhoto) { _, newItem in
                    if let newItem {
                        Task { await handlePhotoSelection(newItem) }
                    }
                }
                .confirmationDialog("Add photo", isPresented: $showPhotoSourceOptions, titleVisibility: .visible) {
                    #if canImport(UIKit)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") {
                            showCameraCapture = true
                        }
                    }
                    #endif

                    Button("Choose from Library") {
                        showPhotoPicker = true
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Create a photo capture or choose an existing image.")
                }
                .alert(alertTitle, isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(alertMessage)
                }
        }
    }

    private var rootContent: some View {
        ZStack(alignment: .bottom) {
            Color.mobileBgPrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                        .padding(.bottom, 16)

                    todayCard
                        .padding(.bottom, 20)

                    favoritesSection
                        .padding(.bottom, 24)

                    recentSection
                        .padding(.bottom, fileTree.isEmpty ? 0 : 24)

                    if !fileTree.isEmpty {
                        allFilesSection
                    }
                }
                .padding(.horizontal, HomeLayout.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, showCaptureMenu ? 236 : 128)
                .animation(captureMenuAnimation, value: showCaptureMenu)
            }
            .blur(radius: showCaptureMenu ? 1.4 : 0)
            .allowsHitTesting(!showCaptureMenu)

            if showCaptureMenu {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        closeCaptureMenu()
                    }
            }

            bottomActionBar
        }
    }

    @ViewBuilder
    private var configuredRootContent: some View {
        let searchable = presentedSearchContent(rootContent)

        #if os(iOS)
        searchable
            .toolbar(.hidden, for: .navigationBar)
        #else
        searchable
        #endif
    }

    @ViewBuilder
    private func presentedSearchContent<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $showSearch) {
            MobileSearchView(workspacePath: workspace.workspacePath, workspace: workspace)
        }
        #else
        content.sheet(isPresented: $showSearch) {
            MobileSearchView(workspacePath: workspace.workspacePath, workspace: workspace)
        }
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(greeting)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.mobileTextPrimary)

            Spacer(minLength: 12)

            Menu {
                Button {
                    closeCaptureMenu()
                    showLinkComposer = true
                } label: {
                    Label("Add link", systemImage: "link")
                }

                Button {
                    closeCaptureMenu()
                    showAgents = true
                } label: {
                    Label("Agents", systemImage: "cpu")
                }

                Button {
                    closeCaptureMenu()
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                utilityIcon("ellipsis.circle")
            }
        }
    }

    private var todayCard: some View {
        let preview = dailyNotePreview()

        return NavigationLink {
            let note = workspace.openOrCreateDailyNote() ?? MobileNoteFile(
                path: workspace.dailyNotePath(),
                name: todayString
            )
            MobilePageEditorView(note: note, workspace: workspace)
        } label: {
            homeCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(todayString)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.mobileTextPrimary)

                        Text(preview.isEmpty ? "Start today's note" : preview)
                            .font(.system(size: 15))
                            .foregroundStyle(preview.isEmpty ? Color.mobileTextMuted : Color.mobileTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mobileUtilityIcon)
                }
                .padding(HomeLayout.cardPadding)
            }
        }
        .buttonStyle(.plain)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Favorites")

            homeCard(accent: Color.mobileWarmAccent) {
                if displayedFavorites.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.mobileTextMuted)

                        Text("Pin your most-used pages from the desktop sidebar")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mobileTextMuted)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(HomeLayout.cardPadding)
                } else {
                    VStack(spacing: 0) {
                        ForEach(displayedFavorites) { file in
                            NavigationLink {
                                destination(for: file)
                            } label: {
                                HStack(spacing: 12) {
                                    favoriteIcon(for: file)

                                    Text(displayName(for: file))
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.mobileTextPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: 12)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.mobileUtilityIcon)
                                }
                                .padding(.horizontal, HomeLayout.cardPadding)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if file.id != displayedFavorites.last?.id {
                                Divider()
                                    .overlay(Color.mobileDivider)
                                    .padding(.leading, HomeLayout.cardPadding)
                            }
                        }
                    }
                }
            }

            if favorites.count > displayedFavorites.count {
                Button("See all") {
                    showAllFavorites = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color.mobileTextMuted)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent")

            homeCard {
                if recentItems.isEmpty {
                    Text("Capture a note, photo, or voice memo to see it here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mobileTextMuted)
                        .padding(HomeLayout.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recentItems) { item in
                            NavigationLink {
                                MobilePageEditorView(note: item.note, workspace: workspace)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    recentLeadingView(for: item)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Color.mobileTextPrimary)
                                            .lineLimit(1)

                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.mobileTextMuted)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                    Spacer(minLength: 12)

                                    Text(recentTimestamp(from: item.modifiedAt))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.mobileTextMuted)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.horizontal, HomeLayout.cardPadding)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if item.id != recentItems.last?.id {
                                Divider()
                                    .overlay(Color.mobileDivider)
                                    .padding(.leading, HomeLayout.cardPadding)
                            }
                        }
                    }
                }
            }
        }
    }

    private var allFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("All files")

            homeCard {
                VStack(spacing: 0) {
                    ForEach(fileTree) { file in
                        NavigationLink {
                            destination(for: file)
                        } label: {
                            HStack(spacing: 12) {
                                favoriteIcon(for: file)

                                Text(displayName(for: file))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.mobileTextPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.mobileUtilityIcon)
                            }
                            .padding(.horizontal, HomeLayout.cardPadding)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if file.id != fileTree.last?.id {
                            Divider()
                                .overlay(Color.mobileDivider)
                                .padding(.leading, HomeLayout.cardPadding)
                        }
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                Button {
                    closeCaptureMenu()
                    showSearch = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Search...")
                            .font(.system(size: 15))
                        Spacer(minLength: 8)
                    }
                    .foregroundStyle(Color.mobileTextSecondary)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.mobileBgPrimary)
                    .clipShape(.capsule)
                    .overlay {
                        Capsule()
                            .stroke(Color.mobileBorder, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Search")

                Color.clear
                    .frame(width: 56, height: 56)
            }
            .padding(12)
            .background(Color.mobileCardBg.opacity(0.98))
            .clipShape(.rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.mobileBorder, lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)

            ZStack(alignment: .bottomTrailing) {
                ForEach(Array(QuickCaptureAction.allCases.enumerated()), id: \.element) { index, action in
                    Button {
                        trigger(action)
                    } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.mobileFloatingActionBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.10), radius: 8, y: 2)
                    .offset(showCaptureMenu ? action.offset : .zero)
                    .scaleEffect(showCaptureMenu ? 1 : 0.72, anchor: .bottomTrailing)
                    .opacity(showCaptureMenu ? 1 : 0)
                    .animation(
                        captureMenuAnimation.delay(Double(index) * 0.02),
                        value: showCaptureMenu
                    )
                    .accessibilityLabel(action.label)
                }

                Button {
                    if didOpenMenuFromLongPress {
                        didOpenMenuFromLongPress = false
                        return
                    }
                    toggleCaptureMenu()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(showCaptureMenu ? 45 : 0))
                        .frame(width: 56, height: 56)
                        .background(showCaptureMenu ? Color.mobileFloatingActionBg : Color.mobileActionBlue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 2)
                .onLongPressGesture(minimumDuration: 0.2) {
                    didOpenMenuFromLongPress = true
                    openCaptureMenu()
                }
                .accessibilityLabel(showCaptureMenu ? "Close capture menu" : "Open capture menu")
            }
            .padding(12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func destination(for file: MobileNoteFile) -> some View {
        if file.isDatabase {
            MobileDatabaseView(dbPath: file.path)
        } else {
            MobilePageEditorView(note: file, workspace: workspace)
        }
    }

    private func utilityIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(Color.mobileTextPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.mobileTextPrimary)
    }

    private func homeCard<Content: View>(
        accent: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mobileCardBg)
        .clipShape(.rect(cornerRadius: HomeLayout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: HomeLayout.cardRadius)
                .stroke(Color.mobileBorder, lineWidth: 0.5)
        }
        .overlay(alignment: .leading) {
            if let accent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 1)
                    .padding(.leading, 1)
            }
        }
    }

    @ViewBuilder
    private func favoriteIcon(for file: MobileNoteFile) -> some View {
        if let icon = file.icon,
           !icon.isEmpty,
           icon.unicodeScalars.first?.properties.isEmoji == true {
            Text(icon)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: file.isDatabase ? "tablecells" : (file.isDirectory ? "folder" : "doc.text"))
                .font(.system(size: 16))
                .foregroundStyle(Color.mobileTextSecondary)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private func recentLeadingView(for item: MobileRecentItem) -> some View {
        switch item.kind {
        case .photo(let thumbnailPath):
            MobileRecentThumbnail(path: thumbnailPath)
        case .note:
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Color.mobileTextSecondary)
                .frame(width: 40, height: 40)
        case .audio:
            Image(systemName: "mic")
                .font(.system(size: 16))
                .foregroundStyle(Color.mobileTextSecondary)
                .frame(width: 40, height: 40)
        }
    }

    private var captureMenuAnimation: Animation {
        .spring(response: 0.18, dampingFraction: 0.82, blendDuration: 0.02)
    }

    private func toggleCaptureMenu() {
        if showCaptureMenu {
            closeCaptureMenu()
        } else {
            openCaptureMenu()
        }
    }

    private func openCaptureMenu() {
        guard !showCaptureMenu else { return }
        withAnimation(captureMenuAnimation) {
            showCaptureMenu = true
        }
    }

    private func closeCaptureMenu() {
        guard showCaptureMenu else { return }
        withAnimation(captureMenuAnimation) {
            showCaptureMenu = false
        }
    }

    private func trigger(_ action: QuickCaptureAction) {
        closeCaptureMenu()

        switch action {
        case .note:
            showNoteComposer = true
        case .photo:
            openPhotoCapture()
        case .audio:
            showAudioRecorder = true
        }
    }

    private func openPhotoCapture() {
        showPhotoSourceOptions = true
    }

    private func createQuickNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard createCaptureFile(displayName: "Note", content: trimmed + "\n") != nil else {
            presentAlert(title: "Couldn't Save Note", message: "Bugbook couldn't create that quick note.")
            return
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            selectedPhoto = nil
            pendingPhotoCapture = PendingPhotoCapture(data: data)
        }
    }

    #if canImport(UIKit)
    private func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            presentAlert(title: "Couldn't Save Photo", message: "Bugbook couldn't turn that image into an attachment.")
            return
        }

        pendingPhotoCapture = PendingPhotoCapture(data: data)
    }
    #endif

    private func persistImageCapture(data: Data, caption: String = "") {
        guard let markdown = imageAttachmentMarkdown(from: data) else {
            presentAlert(title: "Couldn't Save Photo", message: "Bugbook couldn't write the image into your workspace.")
            return
        }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = ([markdown] + (trimmedCaption.isEmpty ? [] : [trimmedCaption]))
            .joined(separator: "\n\n") + "\n"

        guard createCaptureFile(
            displayName: "Photo",
            content: content
        ) != nil else {
            presentAlert(title: "Couldn't Save Photo", message: "Bugbook couldn't create the photo entry.")
            return
        }
    }

    private func handleRecordedAudio(_ recordingURL: URL) {
        guard let markdown = audioAttachmentMarkdown(from: recordingURL) else {
            presentAlert(title: "Couldn't Save Audio", message: "Bugbook couldn't move the voice memo into your workspace.")
            return
        }

        guard createCaptureFile(
            displayName: "Voice memo",
            content: markdown + "\n"
        ) != nil else {
            presentAlert(title: "Couldn't Save Audio", message: "Bugbook couldn't create the voice memo entry.")
            return
        }
    }

    private func captureLink(urlString: String, title: String) -> Bool {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return false }

        let normalized = normalizeURLString(trimmedURL)
        guard let parsedURL = URL(string: normalized), parsedURL.scheme != nil else {
            presentAlert(title: "Invalid Link", message: "Enter a complete URL like https://example.com.")
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkTitle = trimmedTitle.isEmpty ? (parsedURL.host ?? normalized) : trimmedTitle

        guard createCaptureFile(
            displayName: "Link",
            content: "[\(linkTitle)](\(normalized))\n"
        ) != nil else {
            presentAlert(title: "Couldn't Save Link", message: "Bugbook couldn't create the link entry.")
            return false
        }

        return true
    }

    private func createCaptureFile(displayName: String, content: String) -> MobileNoteFile? {
        let inboxPath = (workspace.workspacePath as NSString).appendingPathComponent("Inbox")
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: inboxPath, withIntermediateDirectories: true)

            let safeTitle = displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            let baseName = "\(safeTitle) \(Self.captureNameFormatter.string(from: Date()))"

            var index = 1
            var candidate = "\(baseName).md"
            var filePath = (inboxPath as NSString).appendingPathComponent(candidate)

            while fm.fileExists(atPath: filePath) {
                index += 1
                candidate = "\(baseName) \(index).md"
                filePath = (inboxPath as NSString).appendingPathComponent(candidate)
            }

            try content.write(toFile: filePath, atomically: true, encoding: .utf8)

            let note = MobileNoteFile(
                path: filePath,
                name: String(candidate.dropLast(3)),
                modifiedAt: Date()
            )
            Task { await refresh() }
            return note
        } catch {
            return nil
        }
    }

    private func persistAttachment(data: Data, prefix: String, fileExtension: String) -> String? {
        let attachmentsDir = (workspace.workspacePath as NSString).appendingPathComponent("Attachments")
        do {
            try FileManager.default.createDirectory(atPath: attachmentsDir, withIntermediateDirectories: true)
            let filename = "\(prefix)-\(attachmentTimestamp()).\(fileExtension)"
            let path = (attachmentsDir as NSString).appendingPathComponent(filename)
            try data.write(to: URL(fileURLWithPath: path))
            return filename
        } catch {
            return nil
        }
    }

    private func imageAttachmentMarkdown(from data: Data) -> String? {
        guard let filename = persistAttachment(data: data, prefix: "capture", fileExtension: "jpg") else {
            return nil
        }
        return "![Photo](Attachments/\(filename))"
    }

    private func audioAttachmentMarkdown(from recordingURL: URL) -> String? {
        guard let data = try? Data(contentsOf: recordingURL) else { return nil }

        let ext = recordingURL.pathExtension.isEmpty ? "m4a" : recordingURL.pathExtension
        guard let filename = persistAttachment(data: data, prefix: "audio", fileExtension: ext) else {
            return nil
        }
        return "[Audio note](Attachments/\(filename))"
    }

    private func attachmentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    private func normalizeURLString(_ urlString: String) -> String {
        if urlString.contains("://") {
            return urlString
        }
        return "https://\(urlString)"
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func refresh() async {
        async let tree = workspace.buildHierarchicalFileTree()
        async let recent = workspace.recentFiles(limit: 16)
        let (builtTree, recentFiles) = await (tree, recent)
        fileTree = homeScreenFiles(from: builtTree)
        recentItems = buildRecentItems(from: recentFiles)
        loadFavorites()
    }

    private func homeScreenFiles(from nodes: [MobileNoteFile]) -> [MobileNoteFile] {
        nodes.flatMap { node in
            if node.isDirectory && !node.isDatabase {
                return homeScreenFiles(from: node.children ?? [])
            }
            return [node]
        }
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
            let modDate = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date

            return MobileNoteFile(
                path: path,
                name: name,
                isDirectory: isDir.boolValue,
                isDatabase: isDb,
                icon: icon,
                modifiedAt: modDate
            )
        }
    }

    private func buildRecentItems(from files: [MobileNoteFile]) -> [MobileRecentItem] {
        let dailyPath = workspace.dailyNotePath()

        return files.compactMap { file in
            guard !file.isDatabase, !file.isDirectory, file.path != dailyPath else { return nil }

            let content = workspace.loadFile(at: file.path)
            let rawLines = meaningfulMarkdownLines(from: content)
            let previewLines = contentPreviewLines(for: file, content: content)
            let modifiedAt = file.modifiedAt ?? Date()

            if let firstLine = rawLines.first,
               let imagePath = attachmentPath(in: firstLine, matching: Self.imageExtensions) {
                return MobileRecentItem(
                    note: file,
                    kind: .photo(thumbnailPath: imagePath),
                    title: "Photo",
                    subtitle: previewLines.first,
                    modifiedAt: modifiedAt
                )
            }

            if let firstLine = rawLines.first,
               let audioPath = attachmentPath(in: firstLine, matching: Self.audioExtensions) {
                let duration = audioDuration(at: audioPath)
                let title = duration.map { "Voice memo — \(formattedDuration($0))" } ?? "Voice memo"
                return MobileRecentItem(
                    note: file,
                    kind: .audio,
                    title: title,
                    subtitle: previewLines.first,
                    modifiedAt: modifiedAt
                )
            }

            let title = displayName(for: file)
            let subtitle = previewLines.first

            return MobileRecentItem(
                note: file,
                kind: .note,
                title: title,
                subtitle: subtitle,
                modifiedAt: modifiedAt
            )
        }
    }

    private func dailyNotePreview() -> String {
        let path = workspace.dailyNotePath()
        guard FileManager.default.fileExists(atPath: path) else { return "" }

        let note = MobileNoteFile(
            path: path,
            name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        )

        return contentPreviewLines(for: note, content: workspace.loadFile(at: note.path))
            .prefix(2)
            .joined(separator: " ")
    }

    private func contentPreviewLines(for file: MobileNoteFile, content: String) -> [String] {
        let previewLines = plainTextPreviewLines(from: content)
        let titleVariants = previewTitleVariants(for: file)

        return Array(
            previewLines.drop(while: { line in
                isPreviewHeading(line, matchingAnyOf: titleVariants)
            })
        )
    }

    private func meaningfulMarkdownLines(from content: String) -> [String] {
        var lines: [String] = []
        var inFrontmatter = false
        var hasSeenContent = false

        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" && !hasSeenContent {
                inFrontmatter.toggle()
                continue
            }
            if inFrontmatter || trimmed.isEmpty || trimmed.hasPrefix("<!--") {
                continue
            }
            hasSeenContent = true
            lines.append(trimmed)
        }

        return lines
    }

    private func plainTextPreviewLines(from content: String) -> [String] {
        meaningfulMarkdownLines(from: content).compactMap { line in
            let cleaned = plainText(from: line)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func plainText(from markdownLine: String) -> String {
        if attachmentPath(in: markdownLine, matching: Self.imageExtensions) != nil {
            return ""
        }
        if attachmentPath(in: markdownLine, matching: Self.audioExtensions) != nil {
            return ""
        }

        var line = markdownLine
        line = line.replacingOccurrences(of: #"<!--.*?-->"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^\s*-\s\[[ xX]\]\s*"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^\s*\d+\.\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^\s*>\s*"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        line = stripInternalIdentifiers(from: line)

        guard !line.isEmpty, line != "---" else { return "" }
        return line
    }

    private func previewTitleVariants(for file: MobileNoteFile) -> Set<String> {
        let cleanedName = stripInternalIdentifiers(from: file.name)
        let display = displayName(for: file)

        return Set(
            [cleanedName, display]
                .map(normalizedPreviewComparison)
                .filter { !$0.isEmpty }
        )
    }

    private func isPreviewHeading(_ line: String, matchingAnyOf candidates: Set<String>) -> Bool {
        let normalizedLine = normalizedPreviewComparison(line)
        guard !normalizedLine.isEmpty else { return false }
        return candidates.contains(normalizedLine)
    }

    private func normalizedPreviewComparison(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func attachmentPath(in markdownLine: String, matching allowedExtensions: Set<String>) -> String? {
        guard let start = markdownLine.lastIndex(of: "("),
              let end = markdownLine.lastIndex(of: ")"),
              start < end else {
            return nil
        }

        let target = String(markdownLine[markdownLine.index(after: start)..<end])
        guard target.hasPrefix("Attachments/") else { return nil }

        let ext = (target as NSString).pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return nil }

        return (workspace.workspacePath as NSString).appendingPathComponent(target)
    }

    private func audioDuration(at path: String) -> TimeInterval? {
        guard let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let seconds = player.duration
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func displayName(for file: MobileNoteFile) -> String {
        let cleaned = stripInternalIdentifiers(from: file.name)
        if cleaned.count == 10, cleaned.dropFirst(4).first == "-", cleaned.dropFirst(7).first == "-",
           let date = Self.isoDateFormatter.date(from: cleaned) {
            return Self.todayFormatter.string(from: date)
        }
        return cleaned
    }

    private func stripInternalIdentifiers(from text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: #"\s*\([A-Za-z0-9_-]{5,}\)$"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+[a-f0-9]{8,}$"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recentTimestamp(from date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))

        if elapsed < 3_600 {
            return "\(max(1, elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(elapsed / 3_600)h ago"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return Self.monthDayFormatter.string(from: date)
    }

    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let captureNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h.mm a"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    private static let audioExtensions: Set<String> = ["m4a", "aac", "wav", "mp3", "caf"]

    private enum QuickCaptureAction: CaseIterable, Identifiable {
        case note
        case photo
        case audio

        var id: Self { self }

        var label: String {
            switch self {
            case .note: return "Add note"
            case .photo: return "Add photo"
            case .audio: return "Record audio"
            }
        }

        var icon: String {
            switch self {
            case .note: return "square.and.pencil"
            case .photo: return "camera"
            case .audio: return "mic"
            }
        }

        var offset: CGSize {
            switch self {
            case .note:
                return CGSize(width: -24, height: -130)
            case .photo:
                return CGSize(width: -78, height: -88)
            case .audio:
                return CGSize(width: -132, height: -46)
            }
        }
    }
}

private enum HomeLayout {
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 12
}

private struct MobileRecentItem: Identifiable {
    enum Kind: Hashable {
        case note
        case photo(thumbnailPath: String)
        case audio
    }

    var id: String { note.id }

    let note: MobileNoteFile
    let kind: Kind
    let title: String
    let subtitle: String?
    let modifiedAt: Date
}

private struct PendingPhotoCapture: Identifiable {
    let id = UUID()
    let data: Data
}

private struct MobileDraftAttachment: Identifiable, Hashable {
    enum Kind: Hashable {
        case photo
        case audio

        var iconName: String {
            switch self {
            case .photo: return "camera"
            case .audio: return "mic"
            }
        }

        var label: String {
            switch self {
            case .photo: return "Photo attached"
            case .audio: return "Voice memo attached"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let markdown: String
}

private struct MobileFavoritesSheet: View {
    let favorites: [MobileNoteFile]
    var workspace: MobileWorkspaceService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(favorites) { file in
                NavigationLink {
                    if file.isDatabase {
                        MobileDatabaseView(dbPath: file.path)
                    } else {
                        MobilePageEditorView(note: file, workspace: workspace)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let icon = file.icon,
                           !icon.isEmpty,
                           icon.unicodeScalars.first?.properties.isEmoji == true {
                            Text(icon)
                                .font(.system(size: 16))
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: file.isDatabase ? "tablecells" : (file.isDirectory ? "folder" : "doc.text"))
                                .font(.system(size: 16))
                                .foregroundStyle(Color.mobileTextSecondary)
                                .frame(width: 20, height: 20)
                        }

                        Text(file.name)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mobileTextPrimary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Favorites")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MobileRecentThumbnail: View {
    let path: String

    var body: some View {
        #if canImport(UIKit)
        Group {
            if let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: 8))
        #else
        fallback
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 8))
        #endif
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.mobileBgSecondary)
            Image(systemName: "camera")
                .font(.system(size: 15))
                .foregroundStyle(Color.mobileTextSecondary)
        }
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

    /// True if this is a .md file that also has children (companion folder pattern)
    private var isPageWithChildren: Bool {
        !node.isDirectory && !node.isDatabase && node.children != nil && !node.children!.isEmpty
    }

    /// True if this is a plain directory (not a database, not a companion folder)
    private var isFolderWithChildren: Bool {
        node.isDirectory && !node.isDatabase
    }

    var body: some View {
        if isPageWithChildren {
            // Page with companion folder children: tappable page + expandable children
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    MobilePageEditorView(note: node, workspace: workspace)
                } label: {
                    rowLabel
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if let children = node.children, !children.isEmpty {
                    DisclosureGroup(isExpanded: $isExpanded) {
                        ForEach(children) { child in
                            UnifiedFileRow(node: child, workspace: workspace)
                        }
                    } label: {
                        Text("\(children.count) sub-page\(children.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mobileTextMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
        } else if isFolderWithChildren {
            // Regular folder: expandable
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
            // Leaf: database or standalone page
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

private struct MobileQuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteFieldFocused: Bool

    @State private var noteText = ""
    @State private var attachments: [MobileDraftAttachment] = []
    @State private var showPhotoPicker = false
    @State private var showPhotoSourceOptions = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCameraCapture = false
    @State private var showAudioRecorder = false
    @State private var errorMessage: String?

    let onSubmit: (String) -> Void
    let onCreatePhotoAttachment: (Data) -> String?
    let onCreateAudioAttachment: (URL) -> String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.mobileTextPrimary)

                Text("Capture a thought first, then add a photo or voice memo without leaving the draft.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mobileTextSecondary)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.mobileCardBg)

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.mobileBorder, lineWidth: 0.5)

                    TextEditor(text: $noteText)
                        .focused($noteFieldFocused)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mobileTextPrimary)

                    if noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("What's on your mind?")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.mobileTextMuted)
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 220)

                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { attachment in
                                attachmentChip(attachment)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.mobileBgPrimary)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                attachmentToolbar
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSubmit(composedNote())
                        dismiss()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            if let newItem {
                Task { await handlePhotoSelection(newItem) }
            }
        }
        .confirmationDialog("Add photo", isPresented: $showPhotoSourceOptions, titleVisibility: .visible) {
            #if canImport(UIKit)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    showCameraCapture = true
                }
            }
            #endif

            Button("Choose from Library") {
                showPhotoPicker = true
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Take a new photo or attach one from your library.")
        }
        .sheet(isPresented: $showAudioRecorder) {
            MobileAudioRecorderSheet { recordingURL in
                appendAudioAttachment(from: recordingURL)
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showCameraCapture) {
            MobileCameraCaptureView(
                onCapture: { image in
                    showCameraCapture = false
                    handleCapturedImage(image)
                },
                onCancel: {
                    showCameraCapture = false
                    refocusEditor()
                }
            )
            .ignoresSafeArea()
        }
        #endif
        .alert("Couldn't Add Attachment", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Bugbook couldn't save that attachment.")
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                noteFieldFocused = true
            }
        }
    }

    private var attachmentToolbar: some View {
        HStack(spacing: 18) {
            attachmentButton(systemName: "camera", label: "Add photo") {
                openPhotoAttachment()
            }

            attachmentButton(systemName: "mic", label: "Add audio") {
                showAudioRecorder = true
            }

            Spacer(minLength: 12)

            if !attachments.isEmpty {
                Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mobileTextMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color.mobileBgPrimary)
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color.mobileDivider)
        }
    }

    private func attachmentButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.mobileTextSecondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func attachmentChip(_ attachment: MobileDraftAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind.iconName)
                .font(.system(size: 12, weight: .semibold))
            Text(attachment.kind.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.mobileTextPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.mobileCardBg)
        .clipShape(.capsule)
        .overlay(
            Capsule()
                .stroke(Color.mobileBorder, lineWidth: 0.5)
        )
    }

    private func composedNote() -> String {
        let trimmedText = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        if !trimmedText.isEmpty {
            sections.append(trimmedText)
        }

        sections.append(contentsOf: attachments.map(\.markdown))
        return sections.joined(separator: "\n\n")
    }

    private func openPhotoAttachment() {
        showPhotoSourceOptions = true
    }

    private func appendPhotoAttachment(from data: Data) {
        guard let markdown = onCreatePhotoAttachment(data) else {
            errorMessage = "Bugbook couldn't save that photo into your workspace."
            return
        }

        attachments.append(MobileDraftAttachment(kind: .photo, markdown: markdown))
        refocusEditor()
    }

    private func appendAudioAttachment(from recordingURL: URL) {
        guard let markdown = onCreateAudioAttachment(recordingURL) else {
            errorMessage = "Bugbook couldn't save that voice memo into your workspace."
            return
        }

        attachments.append(MobileDraftAttachment(kind: .audio, markdown: markdown))
        refocusEditor()
    }

    private func refocusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            noteFieldFocused = true
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            appendPhotoAttachment(from: data)
            selectedPhoto = nil
        }
    }

    #if canImport(UIKit)
    private func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            errorMessage = "Bugbook couldn't turn that image into an attachment."
            return
        }

        appendPhotoAttachment(from: data)
    }
    #endif
}

private struct MobilePhotoCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var captionFocused: Bool

    @State private var caption = ""

    let imageData: Data
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a caption")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.mobileTextPrimary)

                Text("Capture why this photo matters before it disappears into the stream.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mobileTextSecondary)

                imagePreview

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.mobileCardBg)

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.mobileBorder, lineWidth: 0.5)

                    TextEditor(text: $caption)
                        .focused($captionFocused)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mobileTextPrimary)

                    if caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Why did you take this?")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.mobileTextMuted)
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 150)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.mobileBgPrimary)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSubmit(caption)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                captionFocused = true
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.mobileCardBg)
                .frame(height: 180)
                .overlay {
                    Label("Preview unavailable", systemImage: "photo")
                        .foregroundStyle(Color.mobileTextSecondary)
                }
        }
        #else
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.mobileCardBg)
            .frame(height: 180)
            .overlay {
                Label("Preview unavailable", systemImage: "photo")
                    .foregroundStyle(Color.mobileTextSecondary)
            }
        #endif
    }
}

private struct MobileLinkCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var urlText = ""
    @State private var titleText = ""

    let onSubmit: (String, String) -> Bool

    private enum Field: Hashable {
        case url
        case title
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a link")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.mobileTextPrimary)

                Text("Save a URL as a quick capture. Add an optional title if you want cleaner link text.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mobileTextSecondary)

                VStack(spacing: 12) {
                    field(title: "URL", placeholder: "https://example.com", text: $urlText, focus: .url)
                    field(title: "Title", placeholder: "Optional title", text: $titleText, focus: .title)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.mobileBgPrimary)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSubmit(urlText, titleText) {
                            dismiss()
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.fraction(0.34), .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focusedField = .url
            }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.mobileTextSecondary)

            configuredField(placeholder: placeholder, text: text, focus: focus)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.mobileCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.mobileBorder, lineWidth: 0.5)
                )
                .foregroundStyle(Color.mobileTextPrimary)
        }
    }

    @ViewBuilder
    private func configuredField(placeholder: String, text: Binding<String>, focus: Field) -> some View {
        #if os(iOS)
        if focus == .url {
            TextField(placeholder, text: text)
                .focused($focusedField, equals: focus)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } else {
            TextField(placeholder, text: text)
                .focused($focusedField, equals: focus)
        }
        #else
        TextField(placeholder, text: text)
            .focused($focusedField, equals: focus)
        #endif
    }
}

private enum MobileAudioPermissionState {
    case checking
    case granted
    case denied
}

#if os(iOS)
private struct MobileAudioRecorderSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var permissionState: MobileAudioPermissionState = .checking
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var isRecording = false
    @State private var statusMessage = "Checking microphone access..."
    @State private var timer: Timer?

    let onSave: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Record audio")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.mobileTextPrimary)

                    Text(statusMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mobileTextSecondary)
                        .multilineTextAlignment(.center)
                }

                Text(elapsedLabel)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.mobileTextPrimary)
                    .monospacedDigit()

                waveformView

                ZStack {
                    Circle()
                        .stroke(recorderActionColor.opacity(isRecording ? 0.18 : 0.10), lineWidth: 16)
                        .frame(width: 126, height: 126)
                        .scaleEffect(innerPulseScale)

                    Circle()
                        .stroke(recorderActionColor.opacity(isRecording ? 0.10 : 0.05), lineWidth: 26)
                        .frame(width: 150, height: 150)
                        .scaleEffect(outerPulseScale)

                    Button {
                        toggleRecording()
                    } label: {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                            .background(recorderActionColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(permissionState != .granted)
                    .shadow(color: recorderActionColor.opacity(0.24), radius: 18, y: 10)
                    .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
                }
                .animation(.easeInOut(duration: 0.18), value: elapsedSeconds)

                if permissionState == .denied {
                    Button("Open Settings") {
                        openAppSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else if recordingURL != nil, !isRecording {
                    VStack(spacing: 10) {
                        Button("Save") {
                            saveRecording()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Record again") {
                            resetRecording()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.mobileBgPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.52), .medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            refreshPermissionState()
        }
        .onDisappear {
            stopTimer()
            if isRecording {
                audioRecorder?.stop()
            }
            audioRecorder = nil
            if let recordingURL {
                try? FileManager.default.removeItem(at: recordingURL)
            }
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    private var elapsedLabel: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var recorderActionColor: Color {
        isRecording ? .red : .mobileActionBlue
    }

    private var innerPulseScale: CGFloat {
        guard isRecording else { return 1 }
        return 1.03 + CGFloat((sin(elapsedSeconds * 4.6) + 1) * 0.06)
    }

    private var outerPulseScale: CGFloat {
        guard isRecording else { return 1 }
        return 1.08 + CGFloat((sin(elapsedSeconds * 4.6 + 1.2) + 1) * 0.09)
    }

    private var waveformView: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(recorderActionColor.opacity(isRecording ? 0.92 : 0.34))
                    .frame(width: 7, height: waveformHeight(for: index))
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.16), value: elapsedSeconds)
    }

    private func refreshPermissionState() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            permissionState = .granted
            statusMessage = recordingURL == nil ? "Tap the mic to start recording." : "Voice memo ready to save."
        case .denied:
            permissionState = .denied
            statusMessage = "Microphone access is off for Bugbook."
        case .undetermined:
            statusMessage = "Requesting microphone access..."
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    permissionState = granted ? .granted : .denied
                    statusMessage = granted
                        ? "Tap the mic to start recording."
                        : "Microphone access is off for Bugbook."
                }
            }
        @unknown default:
            permissionState = .denied
            statusMessage = "Microphone access is unavailable."
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if recordingURL != nil {
            saveRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bugbook-audio-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
            )

            recorder.record()
            audioRecorder = recorder
            recordingURL = url
            elapsedSeconds = 0
            isRecording = true
            statusMessage = "Recording..."
            startTimer()
        } catch {
            permissionState = .denied
            statusMessage = "Bugbook couldn't start recording right now."
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        stopTimer()
        statusMessage = "Voice memo captured."
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func resetRecording() {
        if isRecording {
            stopRecording()
        }
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        elapsedSeconds = 0
        statusMessage = "Tap the mic to start recording."
    }

    private func saveRecording() {
        guard let recordingURL else { return }
        onSave(recordingURL)
        dismiss()
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let idleHeights: [CGFloat] = [12, 22, 18, 30, 40, 30, 18, 22, 12]
        guard isRecording else { return idleHeights[index] }

        let phase = elapsedSeconds * 7 + Double(index) * 0.82
        let wave = (sin(phase) + sin(phase * 0.63 + 1.4) + 2) / 4
        return 14 + CGFloat(wave) * 30
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            elapsedSeconds += 0.18
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
#else
private struct MobileAudioRecorderSheet: View {
    let onSave: (URL) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Record audio")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.mobileTextPrimary)

                Text("Audio capture is only available on iPhone and iPad.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mobileTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}
#endif

#if canImport(UIKit)
private struct MobileCameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: MobileCameraCaptureView

        init(parent: MobileCameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
#endif
