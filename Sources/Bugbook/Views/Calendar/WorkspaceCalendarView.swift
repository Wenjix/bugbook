import SwiftUI
import BugbookCore

struct WorkspaceCalendarView: View {
    @Bindable var appState: AppState
    var calendarService: CalendarService
    @Bindable var calendarVM: CalendarViewModel
    var meetingNoteService: MeetingNoteService
    var aiService: AiService
    var onNavigateToFile: (String) -> Void

    @State private var isSigningIn = false
    @State private var signInError: String?

    private var isConnected: Bool {
        !appState.settings.googleCalendarRefreshToken.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
            if !isConnected && !appState.settings.googleCalendarBannerDismissed {
                googleSignInBanner
            }
            calendarContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

            // Record meeting button
            Button(action: { calendarVM.showRecordMeetingPopover = true }) {
                HStack(spacing: 4) {
                    Image(systemName: meetingNoteService.isProcessingTranscript ? "waveform" : "record.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(meetingNoteService.isProcessingTranscript ? .red : .secondary)
                    Text("Record")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(meetingNoteService.isProcessingTranscript)
            .popover(isPresented: $calendarVM.showRecordMeetingPopover) {
                RecordMeetingPopover(
                    events: currentDayEvents,
                    onRecord: { event, transcription in
                        calendarVM.showRecordMeetingPopover = false
                        handleRecordMeeting(event: event, transcription: transcription)
                    }
                )
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

    // MARK: - Google Sign-In Banner

    private var googleSignInBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Google Calendar?")
                    .font(.system(size: 13, weight: .medium))
                Text("See your events alongside database dates, or keep using the calendar without it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSigningIn {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Sign in with Google") {
                    Task { await signInWithGoogle() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button(action: { appState.settings.googleCalendarBannerDismissed = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .bottom) {
            if let signInError {
                Text(signInError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 2)
            }
        }
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            let result = try await GoogleOAuthFlow.signIn()
            appState.settings.googleCalendarAccessToken = result.accessToken
            appState.settings.googleCalendarRefreshToken = result.refreshToken
            appState.settings.googleCalendarTokenExpiry = result.expiresAt.timeIntervalSince1970
            appState.settings.googleCalendarConnectedEmail = result.email
            // Auto-sync after connecting
            syncCalendar()
        } catch {
            signInError = error.localizedDescription
        }
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

    private var currentDayEvents: [CalendarEvent] {
        calendarVM.events(for: calendarVM.selectedDate, from: visibleEvents)
    }

    // MARK: - Actions

    private func handleRecordMeeting(event: CalendarEvent?, transcription: TranscriptionResult) {
        guard let workspace = appState.workspacePath else { return }
        let apiKey = appState.settings.anthropicApiKey
        Task {
            if let pagePath = await meetingNoteService.createMeetingNoteWithTranscript(
                transcription: transcription,
                event: event,
                workspace: workspace,
                aiService: aiService,
                apiKey: apiKey
            ) {
                calendarService.loadCachedData(workspace: workspace)
                onNavigateToFile(pagePath)
            }
        }
    }

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

    private func syncCalendar() {
        guard let workspace = appState.workspacePath else { return }
        guard let token = loadGoogleToken() else { return }
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

// MARK: - Record Meeting Popover

struct RecordMeetingPopover: View {
    let events: [CalendarEvent]
    var onRecord: (CalendarEvent?, TranscriptionResult) -> Void

    @State private var selectedEventId: String?
    @State private var transcriptText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Meeting")
                .font(.system(size: Typography.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if !events.isEmpty {
                Text("Link to event (optional)")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.secondary)

                Picker("Event", selection: $selectedEventId) {
                    Text("No event").tag(String?.none)
                    ForEach(events) { event in
                        Text(event.title).tag(Optional(event.id))
                    }
                }
                .labelsHidden()
            }

            Text("Paste transcript")
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(.secondary)

            TextEditor(text: $transcriptText)
                .font(.system(size: Typography.body))
                .frame(height: 160)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )

            Button(action: submit) {
                Text("Create Meeting Note")
                    .font(.system(size: Typography.body, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func submit() {
        let selectedEvent = events.first { $0.id == selectedEventId }
        let text = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = TranscriptionResult(fullText: text, timestampedText: text)
        onRecord(selectedEvent, result)
    }
}
