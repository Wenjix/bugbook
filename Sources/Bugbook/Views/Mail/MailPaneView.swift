import SwiftUI
import WebKit

struct MailPaneView: View {
    var appState: AppState
    @Bindable var mailService: MailService

    @State private var searchText = ""
    @State private var activeFilter: MailFilter = .all
    @State private var selectedThreadIDs: Set<String> = []
    @State private var isHoveredThreadID: String?
    @State private var selectAllToggle = false

    var body: some View {
        VStack(spacing: 0) {
            if !appState.settings.googleConfigured {
                setupState(
                    title: "Configure Google access",
                    message: "Add your Google OAuth client ID and secret in Settings before connecting Mail."
                )
            } else if !appState.settings.googleConnected {
                setupState(
                    title: "Connect Gmail",
                    message: "Sign in once and Bugbook will use that Google account for both Mail and Calendar."
                )
            } else if mailService.selectedThread != nil || mailService.isLoadingThread {
                // Full-screen thread view — no filter tabs, just the thread
                detailPane
            } else {
                ZStack {
                    VStack(spacing: 0) {
                        mailFilterTabs
                        batchToolbar
                        Divider()
                        threadList
                    }

                    if mailService.isComposing && mailService.composer.threadId == nil {
                        floatingComposeCard
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.fallbackEditorBg)
        .onAppear {
            searchText = mailService.searchState.query
            if let accountEmail = configuredAccountEmail {
                mailService.loadCachedData(accountEmail: accountEmail)
                if (mailService.mailboxThreads[mailService.selectedMailbox] ?? []).isEmpty {
                    refreshSelectedMailbox(force: false)
                }
            }
        }
        .onChange(of: appState.settings.googleConnectedEmail) { _, newEmail in
            guard !newEmail.isEmpty else { return }
            mailService.loadCachedData(accountEmail: newEmail)
            refreshSelectedMailbox(force: false)
        }
        .task {
            // Auto-refresh inbox every 60 seconds while the mail pane is visible.
            // SwiftUI cancels this task automatically when the view disappears.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                guard appState.settings.googleConnected else { continue }
                refreshSelectedMailbox(force: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Mail")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { submitSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        mailService.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
            .frame(maxWidth: 320)

            if mailService.isSearching || mailService.isLoadingMailbox || mailService.isLoadingThread || mailService.isSending {
                ProgressView()
                    .controlSize(.small)
            }

            if let accountEmail = configuredAccountEmail {
                Label(accountEmail, systemImage: "person.crop.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var mailFilterTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Filter tabs with blue underline
                HStack(spacing: 16) {
                    ForEach(MailFilter.allCases) { filter in
                        Button {
                            activeFilter = filter
                            mailService.selectMailbox(filter.mailbox)
                            refreshSelectedMailbox(force: false)
                        } label: {
                            VStack(spacing: 4) {
                                Text(filter.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(activeFilter == filter ? Color.accentColor : Color.primary.opacity(0.3))

                                Rectangle()
                                    .fill(activeFilter == filter ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Inline search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { submitSearch() }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            mailService.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .clipShape(.rect(cornerRadius: 6))
                .frame(maxWidth: 200)

                if mailService.isSearching || mailService.isLoadingMailbox || mailService.isLoadingThread {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
        }
    }

    private var batchToolbar: some View {
        HStack(spacing: 4) {
            Toggle(isOn: $selectAllToggle) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .onChange(of: selectAllToggle) { _, newValue in
                if newValue {
                    selectedThreadIDs = Set(mailService.visibleThreads.map(\.id))
                } else {
                    selectedThreadIDs.removeAll()
                }
            }

            Menu {
                Button("All") { selectAllToggle = true; selectedThreadIDs = Set(mailService.visibleThreads.map(\.id)) }
                Button("None") { selectAllToggle = false; selectedThreadIDs.removeAll() }
                Divider()
                Button("Read") { selectedThreadIDs = Set(mailService.visibleThreads.filter { !$0.isUnread }.map(\.id)); selectAllToggle = false }
                Button("Unread") { selectedThreadIDs = Set(mailService.visibleThreads.filter { $0.isUnread }.map(\.id)); selectAllToggle = false }
                Button("Starred") { selectedThreadIDs = Set(mailService.visibleThreads.filter { $0.isStarred }.map(\.id)); selectAllToggle = false }
                Button("Unstarred") { selectedThreadIDs = Set(mailService.visibleThreads.filter { !$0.isStarred }.map(\.id)); selectAllToggle = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { refreshSelectedMailbox(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!appState.settings.googleConnected || mailService.isLoadingMailbox)

            Menu {
                Button("Mark as read") { }
                Button("Mark as unread") { }
                Divider()
                Button("Archive") { }
                Button("Move to trash") { }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 34)
    }

    private var mailboxRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { mailService.presentNewComposer() }) {
                Label("Compose", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            ForEach(MailMailbox.allCases) { mailbox in
                Button {
                    mailService.selectMailbox(mailbox)
                    refreshSelectedMailbox(force: false)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: mailbox.systemImage)
                            .frame(width: 18)
                        Text(mailbox.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        let count = mailService.mailboxThreads[mailbox]?.count ?? 0
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mailService.selectedMailbox == mailbox ? Color.primary.opacity(0.08) : Color.clear)
                    .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                appState.showSettings = true
                appState.selectedSettingsTab = "google"
            } label: {
                Label("Google Settings", systemImage: "person.badge.key")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var threadList: some View {
        VStack(spacing: 0) {
            if let error = mailService.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            if mailService.visibleThreads.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No threads" : "No search results",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Refresh Gmail to load messages for \(mailService.selectedMailbox.displayName)." : "Try a different Gmail query.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(mailService.visibleThreads) { thread in
                            Button {
                                openThread(thread)
                            } label: {
                                threadRow(thread)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(Color.fallbackEditorBg)
    }

    private var floatingComposeCard: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("New Message")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    mailService.dismissComposer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            composeView(title: "")
        }
        .frame(width: 450, height: 520)
        .background(Color.fallbackEditorBg)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.fallbackChromeBorder, lineWidth: 0.5))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let thread = mailService.selectedThread {
            VStack(spacing: 0) {
                threadToolbar(thread)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(thread.messages) { message in
                            messageCard(message)
                        }

                        if mailService.isComposing, mailService.composer.threadId == thread.id {
                            composeView(title: mailService.composer.mode == .replyAll ? "Reply All" : "Reply")
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mailService.isLoadingThread {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Select a thread",
                systemImage: "envelope.open",
                description: Text("Choose a message from \(mailService.selectedMailbox.displayName) to read or reply.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func setupState(title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Open Google Settings") {
                appState.showSettings = true
                appState.selectedSettingsTab = "google"
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func threadRow(_ thread: MailThreadSummary) -> some View {
        let isSelected = selectedThreadIDs.contains(thread.id)
        let isHovered = isHoveredThreadID == thread.id
        let unread = thread.isUnread

        return HStack(spacing: 0) {
            // Unread indicator dot
            Circle()
                .fill(unread ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.trailing, 6)

            // Checkbox
            Button {
                if isSelected {
                    selectedThreadIDs.remove(thread.id)
                } else {
                    selectedThreadIDs.insert(thread.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.15))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            // Sender
            Text(senderDisplayName(thread.participants.first ?? "Unknown"))
                .font(.system(size: 14, weight: unread ? .bold : .medium))
                .foregroundColor(Color(nsColor: .labelColor))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 8)

            // Subject
            Text(thread.subject)
                .font(.system(size: 13, weight: unread ? .semibold : .regular))
                .foregroundColor(Color(nsColor: .labelColor))
                .lineLimit(1)
                .layoutPriority(1)

            // Separator + snippet
            if !thread.snippet.isEmpty {
                Text(" — ")
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                Text(thread.snippet)
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Date
            if let date = thread.date {
                Text(relativeDate(date))
                    .font(.system(size: 12, weight: unread ? .medium : .regular))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background {
            if mailService.selectedThreadID == thread.id {
                Color.primary.opacity(Opacity.light)
            } else if isHovered {
                Color.primary.opacity(Opacity.subtle)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveredThreadID = hovering ? thread.id : nil
        }
    }

    /// Clean sender display name — strip email addresses, angle brackets
    private func senderDisplayName(_ raw: String) -> String {
        // If it's "Name <email>", extract just the name
        if let angleBracket = raw.firstIndex(of: "<") {
            let name = raw[raw.startIndex..<angleBracket].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? raw : name
        }
        return raw
    }

    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let pastFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? Self.todayFormatter.string(from: date)
            : Self.pastFormatter.string(from: date)
    }

    private func threadToolbar(_ thread: MailThreadDetail) -> some View {
        HStack(spacing: 10) {
            Button(action: { mailService.selectedThreadID = nil }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Back to inbox")

            VStack(alignment: .leading, spacing: 4) {
                Text(thread.subject)
                    .font(.system(size: 16, weight: .semibold))
                Text(thread.participants.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Reply") {
                mailService.prepareReplyDraft(thread: thread, connectedEmail: appState.settings.googleConnectedEmail, replyAll: false)
            }
            .buttonStyle(.bordered)

            Button("Reply All") {
                mailService.prepareReplyDraft(thread: thread, connectedEmail: appState.settings.googleConnectedEmail, replyAll: true)
            }
            .buttonStyle(.bordered)

            Button(action: { applyThreadAction(thread.isStarred ? .setStarred(false) : .setStarred(true), threadID: thread.id) }) {
                Image(systemName: thread.isStarred ? "star.fill" : "star")
                    .foregroundStyle(thread.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: { applyThreadAction(thread.isUnread ? .setUnread(false) : .setUnread(true), threadID: thread.id) }) {
                Image(systemName: thread.isUnread ? "envelope.open" : "envelope.badge")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { applyThreadAction(thread.mailbox == .trash ? .untrash : .trash, threadID: thread.id) }) {
                Image(systemName: thread.mailbox == .trash ? "arrow.uturn.left.circle" : "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if thread.mailbox != .trash {
                Button(action: { applyThreadAction(.archive, threadID: thread.id) }) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func messageCard(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String((message.from?.name ?? message.from?.email ?? "?").prefix(1)).uppercased())
                            .font(.system(size: 13, weight: .semibold))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(message.from?.displayName ?? "(Unknown Sender)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(recipientLine(for: message))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let date = message.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }

            if let htmlBody = message.htmlBody,
               !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MailHTMLView(html: htmlBody)
                    .frame(minHeight: 220)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            } else {
                Text(message.bodyText.isEmpty ? message.snippet : message.bodyText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.03))
        .clipShape(.rect(cornerRadius: 14))
    }

    private func composeView(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button("Discard") {
                        mailService.dismissComposer()
                    }
                    .buttonStyle(.borderless)
                }
            }

            composeField("To", text: $mailService.composer.to)
            composeField("Cc", text: $mailService.composer.cc)
            composeField("Bcc", text: $mailService.composer.bcc)
            composeField("Subject", text: $mailService.composer.subject)

            TextEditor(text: $mailService.composer.body)
                .font(.system(size: 13))
                .frame(minHeight: 180)
                .padding(8)
                .background(Color.primary.opacity(0.04))
                .clipShape(.rect(cornerRadius: 10))

            HStack {
                Spacer()
                Button("Send") {
                    sendComposer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(mailService.isSending)
            }
        }
        .padding(20)
    }

    private func composeField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func recipientLine(for message: MailMessage) -> String {
        let toLine = message.to.map(\.displayName).joined(separator: ", ")
        if toLine.isEmpty {
            return "No recipients"
        }
        return "To: \(toLine)"
    }

    private var configuredAccountEmail: String? {
        let value = appState.settings.googleConnectedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mailService.clearSearch()
            return
        }
        withMailToken { token in
            await mailService.performSearch(query: trimmed, token: token)
        }
    }

    private func refreshSelectedMailbox(force: Bool) {
        withMailToken { token in
            await mailService.loadMailbox(mailService.selectedMailbox, token: token, forceRefresh: force)
        }
    }

    private func openThread(_ thread: MailThreadSummary) {
        withMailToken { token in
            await mailService.loadThread(id: thread.id, mailbox: thread.mailbox, token: token)
            // Mark as read when opened
            if thread.isUnread {
                await mailService.apply(action: .setUnread(false), to: thread.id, token: token)
            }
        }
    }

    private func applyThreadAction(_ action: MailThreadAction, threadID: String) {
        withMailToken { token in
            await mailService.apply(action: action, to: threadID, token: token)
        }
    }

    private func sendComposer() {
        withMailToken { token in
            _ = await mailService.sendComposer(
                connectedEmail: appState.settings.googleConnectedEmail,
                token: token
            )
        }
    }

    private func withMailToken(_ operation: @escaping (GoogleOAuthToken) async -> Void) {
        Task {
            do {
                var settings = appState.settings
                let token = try await GoogleAuthService.validToken(using: &settings, requiredScopes: GoogleScopeSet.mail)
                appState.settings = settings
                await operation(token)
            } catch {
                mailService.error = error.localizedDescription
            }
        }
    }
}

private enum MailFilter: String, CaseIterable, Identifiable {
    case all, unread, starred, sent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .starred: return "Starred"
        case .sent: return "Sent"
        }
    }

    var mailbox: MailMailbox {
        switch self {
        case .all, .unread: return .inbox
        case .starred: return .starred
        case .sent: return .sent
        }
    }
}

private struct MailHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.isInspectable = true
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let wrapped = wrappedHTML(html)
        guard context.coordinator.lastLoadedHTML != wrapped else { return }
        context.coordinator.lastLoadedHTML = wrapped
        nsView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastLoadedHTML: String = ""
    }

    private func wrappedHTML(_ body: String) -> String {
        """
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              font-size: 14px;
              line-height: 1.5;
              color: #1f2937;
              background: transparent;
            }
            img {
              max-width: 100%;
              height: auto;
            }
            pre {
              white-space: pre-wrap;
            }
          </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
