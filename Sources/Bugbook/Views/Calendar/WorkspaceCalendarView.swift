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
    @State private var selectedCalendarEvent: CalendarEvent?

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
                onDatabaseItemTapped: handleDatabaseItemTapped,
                onCreateEvent: handleDragCreateEvent
            )
        case .week:
            CalendarWeekView(
                days: calendarVM.daysInView,
                events: visibleEvents,
                databaseItems: calendarService.databaseItems,
                calendarVM: calendarVM,
                calendarSources: calendarService.sources,
                onEventTapped: handleEventTapped,
                onDatabaseItemTapped: handleDatabaseItemTapped,
                onCreateEvent: handleDragCreateEvent
            )
        case .month:
            CalendarMonthView(
                selectedDate: calendarVM.selectedDate,
                events: visibleEvents,
                databaseItems: calendarService.databaseItems,
                calendarVM: calendarVM,
                calendarSources: calendarService.sources,
                onEventTapped: handleEventTapped,
                onDatabaseItemTapped: handleDatabaseItemTapped
            )
        }
    }

    // MARK: - Header

    private var calendarHeader: some View {
        let connectedEmail = appState.settings.googleConnectedEmail
        return HStack(spacing: 8) {
            // Account avatar
            if !connectedEmail.isEmpty {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(connectedEmail.prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .help(connectedEmail)
            }

            // Inline date info
            Text("\(Calendar.current.component(.day, from: calendarVM.selectedDate))")
                .font(.system(size: 20, design: .monospaced).weight(.bold))
                .foregroundStyle(Calendar.current.isDateInToday(calendarVM.selectedDate) ? Color.red.opacity(0.8) : .primary)

            VStack(alignment: .leading, spacing: 0) {
                Text(calendarVM.selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 12, weight: .medium))
                Text(calendarVM.selectedDate.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

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

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
    }


    private static let eventDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let eventTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private func eventDateTimeString(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return Self.eventDayFormatter.string(from: event.startDate)
        }
        let startDay = Self.eventDayFormatter.string(from: event.startDate)
        let startTime = Self.eventTimeFormatter.string(from: event.startDate)
        let endTime = Self.eventTimeFormatter.string(from: event.endDate)
        return "\(startDay) · \(startTime)–\(endTime)"
    }

    private func calendarSourceColor(_ hex: String) -> Color {
        if hex.hasPrefix("#") {
            return Color(hex: String(hex.dropFirst()))
        }
        return TagColor.color(for: hex)
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
        selectedCalendarEvent = event
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
            await appState.withGoogleSettings { settings in
                await calendarService.syncAllGoogleAccounts(workspace: workspace, settings: &settings)
            }
            await calendarService.loadDatabaseOverlayItems(workspace: workspace)
        }
    }

    private func handleDragCreateEvent(startDate: Date, endDate: Date) {
        guard appState.settings.googleConfigured, appState.settings.googleConnected else {
            appState.showSettings = true
            appState.selectedSettingsTab = "google"
            return
        }
        createEventDraft = CalendarEventDraft(
            startDate: startDate,
            endDate: endDate,
            calendarId: "primary"
        )
        createEventError = nil
        showCreateEventSheet = true
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
        guard let accountEmail = appState.settings.activeGoogleAccount?.email, !accountEmail.isEmpty else {
            createEventError = "No active Google account. Connect one in Settings."
            return
        }
        createEventError = nil
        isCreatingEvent = true

        Task {
            defer { isCreatingEvent = false }

            do {
                let createdEvent = try await appState.withValidGoogleToken(
                    for: accountEmail,
                    scopes: GoogleScopeSet.calendar
                ) { token in
                    try await calendarService.createGoogleEvent(
                        workspace: workspace,
                        accountEmail: accountEmail,
                        token: token,
                        draft: createEventDraft
                    )
                }
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

                recurrencePicker

                VStack(alignment: .leading, spacing: 6) {
                    Text("Block Profile")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Work", text: blockProfileNameBinding)
                        .textFieldStyle(.roundedBorder)
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

    // MARK: - Recurrence Picker

    @State private var showCustomRrule = false
    @State private var customRruleText = ""

    @ViewBuilder
    private var recurrencePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repeat")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Repeat", selection: recurrencePickerBinding) {
                Text("Does not repeat").tag("none")
                Divider()
                ForEach(RecurrenceFrequency.allCases) { freq in
                    Text(freq.label).tag(freq.rawValue)
                }
                Divider()
                Text("Custom…").tag("custom")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showCustomRrule {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("FREQ=WEEKLY;BYDAY=MO,WE,FR", text: $customRruleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: customRruleText) { _, value in
                            draft.recurrence = .custom(value)
                        }
                    Text("Enter an RRULE value (without the RRULE: prefix).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recurrencePickerBinding: Binding<String> {
        Binding(
            get: {
                switch draft.recurrence {
                case .none: return "none"
                case .preset(let freq): return freq.rawValue
                case .custom: return "custom"
                }
            },
            set: { newTag in
                showCustomRrule = false
                switch newTag {
                case "none":
                    draft.recurrence = .none
                case "custom":
                    showCustomRrule = true
                    if case .custom(let raw) = draft.recurrence {
                        customRruleText = raw
                    } else {
                        customRruleText = ""
                    }
                    draft.recurrence = .custom(customRruleText)
                default:
                    if let freq = RecurrenceFrequency(rawValue: newTag) {
                        draft.recurrence = .preset(freq)
                    }
                }
            }
        )
    }

    private var blockProfileNameBinding: Binding<String> {
        Binding(
            get: {
                draft.blockProfile?.name ?? ""
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.blockProfile = trimmed.isEmpty ? nil : CalendarBlockProfile(name: trimmed)
            }
        )
    }
}
