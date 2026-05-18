import SwiftUI
import BugbookCore

@MainActor
enum MeetingNavigationCoordinator {
    static func openCreatedMeetingPage(
        _ path: String,
        appState: AppState,
        navigateToFile: (String) -> Void
    ) {
        appState.currentView = .editor
        appState.showSettings = false
        appState.pendingAutoRecordPath = path
        navigateToFile(path)
    }

    static func focusActiveRecordingPage(
        session: ActiveMeetingSession,
        appState: AppState,
        navigateToFile: (String) -> Void
    ) {
        appState.currentView = .editor
        appState.showSettings = false
        navigateToFile(session.meetingPagePath)
    }

    static func stopActiveRecordingFromFloatingPill(
        session: ActiveMeetingSession,
        appState: AppState,
        navigateToFile: (String) -> Void,
        postStopNotification: () -> Void
    ) {
        session.stopRequested = true
        focusActiveRecordingPage(
            session: session,
            appState: appState,
            navigateToFile: navigateToFile
        )
        postStopNotification()
    }
}

/// Daily-driver meeting pane. Recording happens in `MeetingPageView`; this pane
/// creates the meeting row and routes into that page with auto-record armed.
struct MeetingsView: View {
    var appState: AppState
    @Bindable var viewModel: MeetingsViewModel
    var meetingNoteService: MeetingNoteService
    var fileSystem: FileSystemService
    var onNavigateToFile: (String) -> Void

    @State private var databasePath: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.fallbackEditorBg)
        .onAppear {
            ensureMeetingsDatabase()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Meetings")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button(action: createNewMeeting) {
                Label("Record Meeting", systemImage: "record.circle")
                    .font(.system(size: Typography.caption, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("meetings-record-meeting-button")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let databasePath {
            DatabaseFullPageView(dbPath: databasePath)
                .id(databasePath)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Failed to load meetings")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: ensureMeetingsDatabase)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView("Loading meetings...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func ensureMeetingsDatabase() {
        guard let workspace = appState.workspacePath else { return }

        Task { @MainActor in
            do {
                let location = try await fileSystem.ensureMeetingsHubInBackground(in: workspace)
                guard !Task.isCancelled else { return }
                databasePath = location.databasePath
                errorMessage = nil
                viewModel.scan(workspace: workspace)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createNewMeeting() {
        guard let workspace = appState.workspacePath else { return }

        let effectiveTitle = "New Meeting"

        Task { @MainActor in
            guard let path = await meetingNoteService.createAdHocMeetingPageAsync(
                title: effectiveTitle,
                date: Date(),
                workspace: workspace,
                fileSystem: fileSystem
            ) else { return }

            if let databasePath {
                postDatabaseChangeNotification(dbPath: databasePath, origin: "meetings.recordMeeting")
            }
            MeetingNavigationCoordinator.openCreatedMeetingPage(
                path,
                appState: appState,
                navigateToFile: onNavigateToFile
            )
            viewModel.scan(workspace: workspace)
        }
    }
}
