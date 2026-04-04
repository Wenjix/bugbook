import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct MobileTodayView: View {
    var workspace: MobileWorkspaceService
    @Environment(\.scenePhase) private var scenePhase

    @State private var captureText = ""
    @State private var dailyNotePreview: String?
    @State private var recentNotes: [MobileNoteFile] = []
    @State private var showCaptureOptions = false
    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickCaptureSection
                    dailyNoteCard
                    recentFilesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .navigationTitle("Today")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refresh() }
            }
        }
    }

    // MARK: - Quick Capture

    private var quickCaptureSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Capture a thought...", text: $captureText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit { submitCapture() }

                // "+" button with progressive disclosure
                Menu {
                    Button { submitCapture() } label: {
                        Label("Add Note", systemImage: "note.text")
                    }
                    .disabled(captureText.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button { showPhotosPicker = true } label: {
                        Label("Photo from Library", systemImage: "photo")
                    }

                    Button { showCamera = true } label: {
                        Label("Take Photo", systemImage: "camera")
                    }

                    Button { captureQuickNote() } label: {
                        Label("New Page", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            // Quick action pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickActionPill(icon: "checklist", label: "Task") {
                        captureText = "- [ ] "
                    }
                    QuickActionPill(icon: "list.bullet", label: "List") {
                        captureText = "- "
                    }
                    QuickActionPill(icon: "photo", label: "Photo") {
                        showPhotosPicker = true
                    }
                    QuickActionPill(icon: "doc.badge.plus", label: "New Page") {
                        captureQuickNote()
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            if let newItem {
                Task { await handlePhotoSelection(newItem) }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            MobileCameraView { image in
                saveImageToWorkspace(image)
            }
        }
        #endif
    }

    // MARK: - Daily Note Card

    private var dailyNoteCard: some View {
        NavigationLink {
            MobilePageEditorView(note: dailyNoteFile(), workspace: workspace)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(todayDateString)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mobileTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mobileTextMuted)
                }

                if let preview = dailyNotePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mobileTextSecondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Tap to start today's note")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.mobileTextSecondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mobileCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Files

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENTLY MODIFIED")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.mobileTextMuted)
                .tracking(0.6)

            if recentNotes.isEmpty {
                Text("No recent notes")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mobileTextSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentNotes) { note in
                        NavigationLink {
                            if note.isDatabase {
                                MobileDatabaseView(dbPath: note.path)
                            } else {
                                MobilePageEditorView(note: note, workspace: workspace)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = note.icon, !icon.isEmpty {
                                    Text(icon).font(.system(size: 14))
                                } else {
                                    Image(systemName: note.isDatabase ? "tablecells" : "doc.text")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mobileTextSecondary)
                                        .frame(width: 18)
                                }
                                Text(note.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.mobileTextPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if let date = note.modifiedAt {
                                    Text(relativeTime(from: date))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mobileTextMuted)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if note.id != recentNotes.last?.id {
                            Divider().foregroundStyle(Color.mobileDivider)
                        }
                    }
                }
                .mobileCard(padding: 12)
            }
        }
    }

    // MARK: - Actions

    private func submitCapture() {
        let text = captureText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let note = workspace.openOrCreateDailyNote() else { return }

        var content = workspace.loadFile(at: note.path)
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += text + "\n"
        workspace.saveFile(at: note.path, content: content)

        captureText = ""
        refresh()
    }

    private func captureQuickNote() {
        _ = workspace.createNote()
        refresh()
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        saveImageData(data)
    }

    #if os(iOS)
    private func saveImageToWorkspace(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        saveImageData(data)
    }
    #endif

    private func saveImageData(_ data: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "capture-\(formatter.string(from: Date())).jpg"

        let imagesDir = (workspace.workspacePath as NSString).appendingPathComponent("Attachments")
        try? FileManager.default.createDirectory(atPath: imagesDir, withIntermediateDirectories: true)

        let imagePath = (imagesDir as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: imagePath))

        // Embed in daily note
        guard let note = workspace.openOrCreateDailyNote() else { return }
        var content = workspace.loadFile(at: note.path)
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "![capture](Attachments/\(filename))\n"
        workspace.saveFile(at: note.path, content: content)

        refresh()
    }

    // MARK: - Helpers

    private func refresh() {
        workspace.refreshFiles()
        loadDailyNotePreview()
        loadRecentFiles()
    }

    private func dailyNotePath() -> String {
        workspace.dailyNotePath()
    }

    private func dailyNoteFile() -> MobileNoteFile {
        workspace.openOrCreateDailyNote() ?? MobileNoteFile(path: dailyNotePath(), name: todayDateString)
    }

    private func loadDailyNotePreview() {
        let path = dailyNotePath()
        guard FileManager.default.fileExists(atPath: path) else {
            dailyNotePreview = nil
            return
        }
        let content = workspace.loadFile(at: path)
        let lines = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(4)
        dailyNotePreview = lines.joined(separator: "\n")
    }

    private func loadRecentFiles() {
        recentNotes = workspace.recentFiles(limit: 8)
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

// MARK: - Quick Action Pill

private struct QuickActionPill: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.mobileBgTertiary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Camera View

#if os(iOS)
struct MobileCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif
