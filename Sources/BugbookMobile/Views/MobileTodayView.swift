import SwiftUI

struct MobileTodayView: View {
    var workspace: MobileWorkspaceService
    @Environment(\.scenePhase) private var scenePhase

    @State private var captureText = ""
    @State private var dailyNotePreview: String?
    @State private var recentNotes: [MobileNoteFile] = []

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    quickCaptureField
                    dailyNoteCard
                    recentFilesSection
                }
                .padding()
            }
            .navigationTitle("Today")
            .onAppear { refresh() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refresh() }
            }
        }
    }

    // MARK: - Quick Capture

    private var quickCaptureField: some View {
        HStack(spacing: 10) {
            TextField("Quick capture...", text: $captureText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { submitCapture() }

            Button(action: submitCapture) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .disabled(captureText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

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

    // MARK: - Daily Note Card

    private var dailyNoteCard: some View {
        NavigationLink {
            MobilePageEditorView(note: dailyNoteFile(), workspace: workspace)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(todayDateString)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let preview = dailyNotePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Tap to start today's note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            #if os(iOS)
            .background(Color(.secondarySystemGroupedBackground))
            #else
            .background(Color(.windowBackgroundColor))
            #endif
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Files

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Modified")
                .font(.headline)

            if recentNotes.isEmpty {
                Text("No recent notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentNotes) { note in
                    NavigationLink {
                        MobilePageEditorView(note: note, workspace: workspace)
                    } label: {
                        HStack {
                            Text(note.name)
                                .font(.body).fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let date = note.modifiedAt {
                                Text(relativeTime(from: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
