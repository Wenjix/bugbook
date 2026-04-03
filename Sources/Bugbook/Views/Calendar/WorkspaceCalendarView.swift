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

    /// Tracks whether the user explicitly picked a view mode (overriding width-adaptive auto).
    @State private var userOverrodeViewMode = false
    @State private var lastAutoMode: CalendarViewMode?

    @State private var transcriptionService = TranscriptionService()
    @State private var showImportRecording = false
    @State private var showCreateEventSheet = false
    @State private var createEventDraft = CalendarEventDraft(
        startDate: Date(),
        endDate: Date().addingTimeInterval(3600)
    )
    @State private var isCreatingEvent = false
    @State private var createEventError: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                calendarHeader
                if let error = calendarService.error, !error.isEmpty {
                    calendarErrorBanner(error)
                }
                calendarContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: geo.size.width) { _, newWidth in
                applyWidthAdaptiveMode(width: newWidth)
            }
            .onAppear {
                applyWidthAdaptiveMode(width: geo.size.width)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.fallbackEditorBg)
        .animation(.easeInOut(duration: 0.15), value: calendarVM.viewMode)
        .onChange(of: calendarVM.viewMode) { oldValue, newValue in
            // If the mode changed and it wasn't from our auto-switch, mark as user override
            if newValue != lastAutoMode {
                userOverrodeViewMode = true
            }
        }
        .sheet(isPresented: $showCreateEventSheet) {
            CalendarEventComposerSheet(
                draft: $createEventDraft,
                connectedEmail: appState.settings.googleConnectedEmail,
                isSaving: isCreatingEvent,
                errorMessage: createEventError,
                onCancel: {
                    showCreateEventSheet = false
                    createEventError = nil
                },
                onSave: createCalendarEvent
            )
        }
        .onAppear {
            if let workspace = appState.workspacePath {
                calendarService.loadCachedData(workspace: workspace)
                Task {
                    await calendarService.loadDatabaseOverlayItems(workspace: workspace)
                }
                if appState.settings.googleConnected,
                   calendarService.events.isEmpty,
                   calendarService.isSyncing == false {
                    syncCalendar()
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
                calendarSources: calendarService.sources,
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

            // Create event button
            Button(action: handleCreateEventButton) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(appState.settings.googleConnected ? "Create Google Calendar event" : "Connect Google Calendar to create events")

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

    private func calendarErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
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

    // MARK: - Width-Adaptive Mode

    /// Auto-switch between day and week based on available width.
    /// Month is never auto-selected. User override is respected until the pane
    /// crosses the threshold in the other direction.
    private func applyWidthAdaptiveMode(width: CGFloat) {
        guard !userOverrodeViewMode else { return }
        let preferred: CalendarViewMode = width > 700 ? .week : .day
        if calendarVM.viewMode != preferred, calendarVM.viewMode != .month {
            lastAutoMode = preferred
            calendarVM.viewMode = preferred
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
        Task {
            do {
                var settings = appState.settings
                let token = try await GoogleAuthService.validToken(using: &settings, requiredScopes: GoogleScopeSet.calendar)
                appState.settings = settings
                await calendarService.syncGoogleCalendar(workspace: workspace, token: token)
                await calendarService.loadDatabaseOverlayItems(workspace: workspace)
            } catch {
                calendarService.error = error.localizedDescription
            }
        }
    }

    private func handleCreateEventButton() {
        guard appState.settings.googleConfigured, appState.settings.googleConnected else {
            appState.showSettings = true
            appState.selectedSettingsTab = "google"
            return
        }

        createEventDraft = makeCreateEventDraft()
        createEventError = nil
        showCreateEventSheet = true
    }

    private func createCalendarEvent() {
        guard let workspace = appState.workspacePath, !isCreatingEvent else { return }
        createEventError = nil
        isCreatingEvent = true

        Task {
            defer { isCreatingEvent = false }

            do {
                var settings = appState.settings
                let token = try await GoogleAuthService.validToken(using: &settings, requiredScopes: GoogleScopeSet.calendar)
                let createdEvent = try await calendarService.createGoogleEvent(
                    workspace: workspace,
                    token: token,
                    draft: createEventDraft
                )
                appState.settings = settings
                calendarVM.selectedDate = createdEvent.startDate
                createEventDraft = makeCreateEventDraft()
                showCreateEventSheet = false
            } catch {
                createEventError = error.localizedDescription
            }
        }
    }

    private func makeCreateEventDraft() -> CalendarEventDraft {
        let calendar = Calendar.current
        let selectedDayStart = calendar.startOfDay(for: calendarVM.selectedDate)
        let now = Date()

        var startDate: Date
        switch calendarVM.viewMode {
        case .month:
            startDate = calendar.date(byAdding: .hour, value: 9, to: selectedDayStart) ?? selectedDayStart
        case .day, .week:
            let candidate = max(now, calendarVM.selectedDate)
            startDate = alignedToNextHalfHour(candidate)
            if calendar.isDate(startDate, inSameDayAs: selectedDayStart) == false {
                startDate = calendar.date(byAdding: .hour, value: 9, to: selectedDayStart) ?? selectedDayStart
            }
        }

        return CalendarEventDraft(
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            calendarId: "primary"
        )
    }

    private func alignedToNextHalfHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = components.minute ?? 0
        let remainder = minute % 30
        if remainder == 0, let exact = calendar.date(from: components) {
            return exact
        }
        components.minute = minute + (30 - remainder)
        components.second = 0
        return calendar.date(from: components) ?? date
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

struct CalendarEventComposerSheet: View {
    @Binding var draft: CalendarEventDraft
    let connectedEmail: String
    let isSaving: Bool
    let errorMessage: String?
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Event")
                    .font(.system(size: 18, weight: .semibold))

                if !connectedEmail.isEmpty {
                    Label(connectedEmail, systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Planning review", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("All-day", isOn: $draft.isAllDay)
                    .toggleStyle(.switch)

                if draft.isAllDay {
                    DatePicker("Starts", selection: $draft.startDate, displayedComponents: [.date])
                    DatePicker("Ends", selection: $draft.endDate, displayedComponents: [.date])

                    Text("All-day events end on the selected day in Bugbook and are sent to Google Calendar with the correct exclusive end date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker("Starts", selection: $draft.startDate)
                    DatePicker("Ends", selection: $draft.endDate)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Conference room or link", text: $draft.location)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 13))
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)

                Button(action: onSave) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Create Event")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: draft.isAllDay) { _, isAllDay in
            guard isAllDay else {
                if draft.endDate <= draft.startDate {
                    draft.endDate = draft.startDate.addingTimeInterval(3600)
                }
                return
            }

            let calendar = Calendar.current
            draft.startDate = calendar.startOfDay(for: draft.startDate)
            draft.endDate = calendar.startOfDay(for: max(draft.startDate, draft.endDate))
        }
    }
}
