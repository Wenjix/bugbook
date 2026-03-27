import SwiftUI
import BugbookCore
import UniformTypeIdentifiers

struct WorkspaceCalendarView: View {
    var appState: AppState
    var calendarService: CalendarService
    @Bindable var calendarVM: CalendarViewModel
    var meetingNoteService: MeetingNoteService
    var aiService: AiService
    var onNavigateToFile: (String) -> Void

    @State private var transcriptionService = TranscriptionService()
    @State private var showImportRecording = false

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.fallbackEditorBg)
        .animation(.easeInOut(duration: 0.15), value: calendarVM.viewMode)
        .onAppear {
            if let workspace = appState.workspacePath {
                calendarService.loadCachedData(workspace: workspace)
                Task {
                    await calendarService.loadDatabaseOverlayItems(workspace: workspace)
                }
            }
        }
    }

    // MARK: - Calendar Content

    @ViewBuilder
    private var calendarContent: some View {
        switch calendarVM.viewMode {
        case .day:
            CalendarDayView(
                date: calendarVM.selectedDate,
                events: visibleEvents,
                databaseItems: calendarService.databaseItems,
                calendarVM: calendarVM,
                onEventTapped: handleEventTapped,
                onDatabaseItemTapped: handleDatabaseItemTapped
            )
        case .week:
            CalendarWeekView(
                days: calendarVM.daysInView,
                events: visibleEvents,
                databaseItems: calendarService.databaseItems,
                calendarVM: calendarVM,
                onEventTapped: handleEventTapped,
                onDatabaseItemTapped: handleDatabaseItemTapped
            )
        case .month:
            CalendarMonthView(
                selectedDate: calendarVM.selectedDate,
                events: visibleEvents,
                databaseItems: calendarService.databaseItems,
                calendarVM: calendarVM,
                onEventTapped: handleEventTapped,
                onDatabaseItemTapped: handleDatabaseItemTapped
            )
        }
    }

    // MARK: - Header

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            // Title
            Text(calendarVM.headerTitle)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            // Sync indicator
            if calendarService.isSyncing {
                ProgressView()
                    .controlSize(.small)
            }

            // View mode dropdown (NSPopUpButton workaround to avoid blue Menu label)
            ViewModePickerButton(viewMode: $calendarVM.viewMode)

            // Today button
            Button(action: { calendarVM.goToToday() }) {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Navigation arrows
            HStack(spacing: 2) {
                Button(action: calendarVM.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: calendarVM.goForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            // Sources toggle
            Button(action: { calendarVM.showSourcePicker.toggle() }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $calendarVM.showSourcePicker) {
                CalendarSourcePicker(
                    sources: calendarService.sources,
                    overlays: calendarService.overlays,
                    onToggleSource: { id in
                        if let workspace = appState.workspacePath {
                            calendarService.toggleSourceVisibility(id: id, workspace: workspace)
                        }
                    },
                    onToggleOverlay: { id in
                        if let workspace = appState.workspacePath {
                            calendarService.toggleOverlayVisibility(id: id, workspace: workspace)
                        }
                    }
                )
            }

            // Import recording button
            Button(action: { showImportRecording = true }) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Import audio recording")
            .disabled(transcriptionService.isTranscribing)
            .fileImporter(
                isPresented: $showImportRecording,
                allowedContentTypes: [
                    UTType.audio,
                    UTType(filenameExtension: "m4a") ?? .audio,
                    UTType(filenameExtension: "mp3") ?? .audio,
                    UTType.wav,
                ],
                allowsMultipleSelection: false
            ) { result in
                handleImportedRecording(result)
            }

            // Sync button
            Button(action: syncCalendar) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(calendarService.isSyncing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Data

    private var visibleSourceIds: Set<String> {
        Set(calendarService.sources.filter(\.isVisible).map(\.id))
    }

    private var visibleEvents: [CalendarEvent] {
        calendarService.events.filter { event in
            visibleSourceIds.isEmpty || visibleSourceIds.contains(event.calendarId)
        }
    }

    // MARK: - Actions

    private func handleEventTapped(_ event: CalendarEvent) {
        guard let workspace = appState.workspacePath else { return }
        Task {
            if let pagePath = await meetingNoteService.createOrOpenMeetingNote(for: event, workspace: workspace) {
                calendarService.loadCachedData(workspace: workspace)
                onNavigateToFile(pagePath)
            }
        }
    }

    private func handleDatabaseItemTapped(_ item: CalendarDatabaseItem) {
        let path = DatabaseRowNavigationPath.make(dbPath: item.databasePath, rowId: item.rowId)
        onNavigateToFile(path)
    }

    private func handleImportedRecording(_ result: Result<[URL], Error>) {
        guard let workspace = appState.workspacePath else { return }
        guard case .success(let urls) = result, let fileURL = urls.first else { return }

        // Ensure we have access to the file
        guard fileURL.startAccessingSecurityScopedResource() else { return }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        Task {
            if let pagePath = await meetingNoteService.importRecording(
                fileURL: fileURL,
                workspace: workspace,
                transcriptionService: transcriptionService,
                aiService: aiService,
                apiKey: appState.settings.anthropicApiKey,
                model: appState.settings.anthropicModel
            ) {
                onNavigateToFile(pagePath)
            }
        }
    }

    private func syncCalendar() {
        guard let workspace = appState.workspacePath else { return }
        let token = loadGoogleToken()
        guard let token else {
            calendarService.error = "No Google Calendar credentials configured. Go to Settings > Calendar."
            return
        }
        Task {
            await calendarService.syncGoogleCalendar(workspace: workspace, token: token)
            await calendarService.loadDatabaseOverlayItems(workspace: workspace)
        }
    }

    private func loadGoogleToken() -> GoogleOAuthToken? {
        let settings = appState.settings
        guard !settings.googleCalendarRefreshToken.isEmpty else { return nil }
        return GoogleOAuthToken(
            accessToken: settings.googleCalendarAccessToken,
            refreshToken: settings.googleCalendarRefreshToken,
            expiresAt: Date(timeIntervalSince1970: settings.googleCalendarTokenExpiry)
        )
    }
}

// MARK: - Source Picker

struct CalendarSourcePicker: View {
    let sources: [CalendarSource]
    let overlays: [CalendarOverlay]
    var onToggleSource: (String) -> Void
    var onToggleOverlay: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !sources.isEmpty {
                Text("Calendars")
                    .font(.system(size: Typography.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(sources) { source in
                    Toggle(isOn: Binding(
                        get: { source.isVisible },
                        set: { _ in onToggleSource(source.id) }
                    )) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(calendarColor(source.color))
                                .frame(width: 8, height: 8)
                            Text(source.name)
                                .font(.system(size: Typography.body))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if !overlays.isEmpty {
                if !sources.isEmpty { Divider() }

                Text("Database Overlays")
                    .font(.system(size: Typography.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(overlays) { overlay in
                    Toggle(isOn: Binding(
                        get: { overlay.isVisible },
                        set: { _ in onToggleOverlay(overlay.id) }
                    )) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(TagColor.color(for: overlay.color))
                                .frame(width: 8, height: 8)
                            Text("\(overlay.databaseName) — \(overlay.datePropertyName)")
                                .font(.system(size: Typography.body))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if sources.isEmpty && overlays.isEmpty {
                Text("No calendars or overlays configured.\nSync with Google Calendar or add a database overlay in Settings.")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func calendarColor(_ hex: String) -> Color {
        if hex.hasPrefix("#") {
            return Color(hex: String(hex.dropFirst()))
        }
        return TagColor.color(for: hex)
    }
}
