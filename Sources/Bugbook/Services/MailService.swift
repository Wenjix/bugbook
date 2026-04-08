import Foundation

@MainActor
@Observable
final class MailService {
    var mailboxThreads: [MailMailbox: [MailThreadSummary]] = [:]
    var threadDetails: [String: MailThreadDetail] = [:]
    var selectedMailbox: MailMailbox = .inbox
    var selectedThreadID: String?
    var searchState = MailSearchState()
    var searchResults: [MailThreadSummary] = []
    var composer = MailDraft()
    var isComposing = false
    var isLoadingMailbox = false
    var isLoadingThread = false
    var isSearching = false
    var isSending = false
    var error: String?
    var lastSyncDate: Date?

    @ObservationIgnored private let cacheStore: MailCacheStore
    @ObservationIgnored private var activeAccountEmail: String?

    init(cacheStore: MailCacheStore = MailCacheStore()) {
        self.cacheStore = cacheStore
    }

    var visibleThreads: [MailThreadSummary] {
        searchState.isActive ? searchResults : (mailboxThreads[selectedMailbox] ?? [])
    }

    var selectedThread: MailThreadDetail? {
        guard let selectedThreadID else { return nil }
        return threadDetails[selectedThreadID]
    }

    func loadCachedData(accountEmail: String) {
        activeAccountEmail = accountEmail
        mailboxThreads = [:]
        threadDetails = [:]
        searchState = MailSearchState()
        searchResults = []
        selectedThreadID = nil
        lastSyncDate = nil

        guard let snapshot = cacheStore.load(accountEmail: accountEmail) else { return }
        mailboxThreads = snapshot.mailboxThreads
        threadDetails = snapshot.threadDetails
        lastSyncDate = snapshot.savedAt
        if selectedThreadID == nil {
            selectedThreadID = mailboxThreads[selectedMailbox]?.first?.id
        }
    }

    func selectMailbox(_ mailbox: MailMailbox) {
        selectedMailbox = mailbox
        searchState = MailSearchState()
        searchResults = []
        selectedThreadID = mailboxThreads[mailbox]?.first?.id
        error = nil
    }

    func clearSearch() {
        searchState = MailSearchState()
        searchResults = []
    }

    func presentNewComposer() {
        composer = MailDraft()
        isComposing = true
    }

    func dismissComposer() {
        composer = MailDraft()
        isComposing = false
    }

    func prepareReplyDraft(thread: MailThreadDetail, connectedEmail: String, replyAll: Bool) {
        guard let source = thread.messages.last(where: { !$0.isDraft }) ?? thread.messages.last else { return }
        let sourceEmail = connectedEmail.lowercased()
        let toRecipients = source.from.map { [$0.email] } ?? []
        let ccRecipients: [String]

        if replyAll {
            let replyAllAddresses = (source.to + source.cc)
                .map(\.email)
                .filter { $0.caseInsensitiveCompare(sourceEmail) != .orderedSame }
                .filter { !toRecipients.contains($0) }
            ccRecipients = uniqueStrings(replyAllAddresses)
        } else {
            ccRecipients = []
        }

        composer = MailDraft(
            mode: replyAll ? .replyAll : .reply,
            to: toRecipients.joined(separator: ", "),
            cc: ccRecipients.joined(separator: ", "),
            bcc: "",
            subject: MailService.replySubject(for: thread.subject),
            body: "",
            threadId: thread.id,
            replyToMessageID: source.messageIDHeader,
            referencesHeader: source.referencesHeader ?? source.messageIDHeader
        )
        isComposing = true
    }

    func prepareForwardDraft(thread: MailThreadDetail) {
        guard let source = thread.messages.last(where: { !$0.isDraft }) ?? thread.messages.last else { return }
        let subject = MailService.forwardSubject(for: thread.subject)
        let quotedBody = "\n\n---------- Forwarded message ----------\nFrom: \(source.from?.displayName ?? "")\nDate: \(source.date?.formatted(date: .abbreviated, time: .shortened) ?? "")\nSubject: \(thread.subject)\n\n\(source.bodyText)"

        composer = MailDraft(
            mode: .forward,
            to: "",
            cc: "",
            bcc: "",
            subject: subject,
            body: quotedBody,
            threadId: nil,
            replyToMessageID: nil,
            referencesHeader: nil
        )
        isComposing = true
    }

    static func forwardSubject(for subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("fwd:") else { return trimmed }
        return trimmed.isEmpty ? "Fwd:" : "Fwd: \(trimmed)"
    }

    func loadMailbox(_ mailbox: MailMailbox, token: GoogleOAuthToken, forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = mailboxThreads[mailbox], !cached.isEmpty {
            selectedThreadID = selectedThreadID ?? cached.first?.id
            return
        }

        isLoadingMailbox = true
        error = nil
        defer { isLoadingMailbox = false }

        do {
            let threadIDs = try await GmailMailAPI.listThreadIDs(
                labelIDs: mailbox.gmailLabelIDs,
                query: nil,
                token: token
            )
            let summaries = try await GmailMailAPI.fetchThreadSummaries(
                ids: threadIDs,
                mailbox: mailbox,
                token: token
            )
            mailboxThreads[mailbox] = summaries.sorted(by: MailService.threadSort)
            if selectedMailbox == mailbox {
                selectedThreadID = mailboxThreads[mailbox]?.first?.id
            }
            persistSnapshot()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshSelectedMailbox(token: GoogleOAuthToken) async {
        await loadMailbox(selectedMailbox, token: token, forceRefresh: true)
    }

    func performSearch(query: String, token: GoogleOAuthToken) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchState.query = query
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        error = nil
        defer { isSearching = false }

        do {
            let threadIDs = try await GmailMailAPI.listThreadIDs(labelIDs: [], query: trimmed, token: token)
            let summaries = try await GmailMailAPI.fetchThreadSummaries(ids: threadIDs, mailbox: nil, token: token)
            searchResults = summaries.sorted(by: MailService.threadSort)
            selectedThreadID = searchResults.first?.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadThread(id: String, mailbox: MailMailbox?, token: GoogleOAuthToken, forceRefresh: Bool = false) async {
        if !forceRefresh, threadDetails[id] != nil {
            selectedThreadID = id
            return
        }

        isLoadingThread = true
        error = nil
        defer { isLoadingThread = false }

        do {
            let detail = try await GmailMailAPI.fetchThreadDetail(id: id, mailbox: mailbox, token: token)
            threadDetails[id] = detail
            selectedThreadID = id
            updateSummary(for: detail)
            persistSnapshot()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchThreadDetailSnapshot(id: String, mailbox: MailMailbox?, token: GoogleOAuthToken) async throws -> MailThreadDetail {
        if let cached = threadDetails[id] {
            return cached
        }

        let detail = try await GmailMailAPI.fetchThreadDetail(id: id, mailbox: mailbox, token: token)
        threadDetails[id] = detail
        updateSummary(for: detail)
        persistSnapshot()
        return detail
    }

    func apply(action: MailThreadAction, to threadID: String, token: GoogleOAuthToken) async {
        isLoadingThread = true
        error = nil
        defer { isLoadingThread = false }

        let previousMailboxThreads = mailboxThreads
        let previousSearchResults = searchResults
        let previousDetail = threadDetails[threadID]
        let mailboxHint = previousDetail?.mailbox ?? selectedMailbox
        applyLocal(action: action, threadID: threadID)

        do {
            try await GmailMailAPI.apply(action: action, threadID: threadID, token: token)
            let refreshed = try await GmailMailAPI.fetchThreadDetail(id: threadID, mailbox: mailboxHint, token: token)
            threadDetails[threadID] = refreshed
            updateSummary(for: refreshed)
            persistSnapshot()
        } catch {
            mailboxThreads = previousMailboxThreads
            searchResults = previousSearchResults
            if let previousDetail {
                threadDetails[threadID] = previousDetail
            }
            self.error = error.localizedDescription
        }
    }

    func sendComposer(connectedEmail: String, token: GoogleOAuthToken) async -> Bool {
        let draft = composer
        guard !draft.to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "At least one recipient is required."
            return false
        }
        guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Email body cannot be empty."
            return false
        }

        isSending = true
        error = nil
        defer { isSending = false }

        do {
            _ = try await GmailMailAPI.send(draft: draft, connectedEmail: connectedEmail, token: token)
            dismissComposer()

            // Refresh mailbox data opportunistically so the thread list stays close to Gmail.
            await loadMailbox(.sent, token: token, forceRefresh: true)
            if selectedMailbox == .inbox || selectedMailbox == .drafts {
                await loadMailbox(selectedMailbox, token: token, forceRefresh: true)
            }
            if let threadID = draft.threadId {
                await loadThread(id: threadID, mailbox: selectedMailbox, token: token, forceRefresh: true)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func updateSummary(for detail: MailThreadDetail) {
        let updated = MailThreadSummary(
            id: detail.id,
            mailbox: detail.mailbox,
            subject: detail.subject,
            snippet: detail.snippet,
            participants: detail.participants,
            date: detail.lastDate,
            messageCount: detail.messages.count,
            labelIds: detail.labelIds,
            historyId: detail.historyId,
            annotation: detail.annotation
        )

        for mailbox in MailMailbox.allCases {
            var list = mailboxThreads[mailbox] ?? []
            let matches = MailThreadLabelReducer.mailbox(mailbox, contains: detail.labelIds)

            if let index = list.firstIndex(where: { $0.id == detail.id }) {
                if matches {
                    var mailboxSummary = updated
                    mailboxSummary.mailbox = mailbox
                    list[index] = mailboxSummary
                } else {
                    list.remove(at: index)
                }
            } else if matches {
                var mailboxSummary = updated
                mailboxSummary.mailbox = mailbox
                list.insert(mailboxSummary, at: 0)
            }

            mailboxThreads[mailbox] = list.sorted(by: MailService.threadSort)
        }

        if let index = searchResults.firstIndex(where: { $0.id == detail.id }) {
            searchResults[index] = updated
            searchResults.sort(by: MailService.threadSort)
        }
    }

    private func applyLocal(action: MailThreadAction, threadID: String) {
        for mailbox in MailMailbox.allCases {
            guard var list = mailboxThreads[mailbox],
                  let index = list.firstIndex(where: { $0.id == threadID }) else { continue }
            let nextLabels = MailThreadLabelReducer.mutatedLabels(list[index].labelIds, action: action)
            if MailThreadLabelReducer.mailbox(mailbox, contains: nextLabels) {
                list[index].labelIds = nextLabels
                mailboxThreads[mailbox] = list
            } else {
                list.remove(at: index)
                mailboxThreads[mailbox] = list
            }
        }

        if let index = searchResults.firstIndex(where: { $0.id == threadID }) {
            searchResults[index].labelIds = MailThreadLabelReducer.mutatedLabels(searchResults[index].labelIds, action: action)
        }

        if var detail = threadDetails[threadID] {
            detail.labelIds = MailThreadLabelReducer.mutatedLabels(detail.labelIds, action: action)
            for index in detail.messages.indices {
                detail.messages[index].labelIds = MailThreadLabelReducer.mutatedLabels(detail.messages[index].labelIds, action: action)
            }
            threadDetails[threadID] = detail
        }
    }

    private func persistSnapshot() {
        guard let activeAccountEmail else { return }
        let snapshot = MailCacheSnapshot(
            mailboxThreads: mailboxThreads,
            threadDetails: threadDetails,
            savedAt: Date()
        )
        cacheStore.save(snapshot, accountEmail: activeAccountEmail)
        lastSyncDate = snapshot.savedAt
    }

    private static func threadSort(lhs: MailThreadSummary, rhs: MailThreadSummary) -> Bool {
        let lhsDate = lhs.date ?? .distantPast
        let rhsDate = rhs.date ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
    }

    static func replySubject(for subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix("re:") else { return trimmed }
        return trimmed.isEmpty ? "Re:" : "Re: \(trimmed)"
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    func applyIntelligenceRecords(_ records: [String: MailThreadIntelligenceRecord]) {
        for record in records.values {
            applyIntelligenceRecord(record)
        }
    }

    func applyIntelligenceRecord(_ record: MailThreadIntelligenceRecord) {
        for mailbox in MailMailbox.allCases {
            guard var list = mailboxThreads[mailbox] else { continue }
            guard let index = list.firstIndex(where: { $0.id == record.threadID }) else { continue }
            list[index].annotation = record.annotation
            mailboxThreads[mailbox] = list
        }

        if let index = searchResults.firstIndex(where: { $0.id == record.threadID }) {
            searchResults[index].annotation = record.annotation
        }

        if var detail = threadDetails[record.threadID] {
            detail.annotation = record.annotation
            detail.draftSuggestion = record.draftSuggestion
            detail.senderContext = record.senderContext
            threadDetails[record.threadID] = detail
            updateSummary(for: detail)
        }
    }
}

enum MailThreadLabelReducer {
    static func mutatedLabels(_ labels: [String], action: MailThreadAction) -> [String] {
        var next = Set(labels)
        switch action {
        case .archive:
            next.remove("INBOX")
        case .trash:
            next.insert("TRASH")
        case .untrash:
            next.remove("TRASH")
            next.insert("INBOX")
        case .setStarred(let starred):
            if starred {
                next.insert("STARRED")
            } else {
                next.remove("STARRED")
            }
        case .setUnread(let unread):
            if unread {
                next.insert("UNREAD")
            } else {
                next.remove("UNREAD")
            }
        }
        return Array(next).sorted()
    }

    static func mailbox(_ mailbox: MailMailbox, contains labels: [String]) -> Bool {
        let labelSet = Set(labels)
        return mailbox.gmailLabelIDs.allSatisfy(labelSet.contains)
    }
}

enum MailComposerEncoder {
    static func buildRawMessage(draft: MailDraft, connectedEmail: String) -> String {
        var lines: [String] = [
            "From: \(connectedEmail)",
            "To: \(draft.to)",
        ]

        if !draft.cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Cc: \(draft.cc)")
        }
        if !draft.bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Bcc: \(draft.bcc)")
        }
        lines.append("Subject: \(draft.subject)")
        if let replyToMessageID = draft.replyToMessageID, !replyToMessageID.isEmpty {
            lines.append("In-Reply-To: \(replyToMessageID)")
        }
        if let referencesHeader = draft.referencesHeader, !referencesHeader.isEmpty {
            lines.append("References: \(referencesHeader)")
        }
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: 8bit")
        lines.append("")
        lines.append(draft.body)

        let message = lines.joined(separator: "\r\n")
        let data = Data(message.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum GmailMailAPI {
    private static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!
    private static let listMaxResults = 25

    static func listThreadIDs(labelIDs: [String], query: String?, token: GoogleOAuthToken) async throws -> [String] {
        var components = URLComponents(url: baseURL.appendingPathComponent("threads"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "maxResults", value: "\(listMaxResults)")]
        queryItems.append(contentsOf: labelIDs.map { URLQueryItem(name: "labelIds", value: $0) })
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        let json = try await requestJSON(url: components.url!, token: token)
        let threads = json["threads"] as? [[String: Any]] ?? []
        return threads.compactMap { $0["id"] as? String }
    }

    static func fetchThreadSummaries(ids: [String], mailbox: MailMailbox?, token: GoogleOAuthToken) async throws -> [MailThreadSummary] {
        if ids.isEmpty { return [] }
        return try await withThrowingTaskGroup(of: MailThreadSummary.self) { group in
            for id in ids {
                group.addTask {
                    try await fetchThreadSummary(id: id, mailbox: mailbox, token: token)
                }
            }

            var summaries: [MailThreadSummary] = []
            for try await summary in group {
                summaries.append(summary)
            }
            return summaries
        }
    }

    static func fetchThreadSummary(id: String, mailbox: MailMailbox?, token: GoogleOAuthToken) async throws -> MailThreadSummary {
        let thread = try await fetchThreadResource(
            id: id,
            queryItems: [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "Subject"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Date"),
            ],
            token: token
        )

        let messages = thread["messages"] as? [[String: Any]] ?? []
        let newestMessage = messages.last ?? messages.first ?? [:]
        let newestHeaders = headerMap(from: newestMessage)
        let participants = uniqueValues(messages.compactMap {
            recipientDisplayName(from: headerMap(from: $0)["From"])
        })

        return MailThreadSummary(
            id: id,
            mailbox: mailbox,
            subject: newestHeaders["Subject"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(No Subject)",
            snippet: (thread["snippet"] as? String) ?? "",
            participants: participants,
            date: parseRFC2822Date(newestHeaders["Date"]),
            messageCount: messages.count,
            labelIds: thread["labelIds"] as? [String] ?? [],
            historyId: thread["historyId"] as? String,
            annotation: nil
        )
    }

    static func fetchThreadDetail(id: String, mailbox: MailMailbox?, token: GoogleOAuthToken) async throws -> MailThreadDetail {
        let thread = try await fetchThreadResource(
            id: id,
            queryItems: [URLQueryItem(name: "format", value: "full")],
            token: token
        )

        let rawMessages = thread["messages"] as? [[String: Any]] ?? []
        let messages = rawMessages.compactMap { parseMessage($0, threadID: id) }
        let participants = uniqueValues(messages.compactMap { $0.from?.displayName })
        let subject = messages.last?.subject
            ?? messages.first?.subject
            ?? "(No Subject)"

        return MailThreadDetail(
            id: id,
            mailbox: mailbox,
            subject: subject,
            snippet: (thread["snippet"] as? String) ?? "",
            participants: participants,
            messages: messages,
            labelIds: thread["labelIds"] as? [String] ?? [],
            historyId: thread["historyId"] as? String,
            annotation: nil,
            draftSuggestion: nil,
            senderContext: nil
        )
    }

    static func apply(action: MailThreadAction, threadID: String, token: GoogleOAuthToken) async throws {
        switch action {
        case .trash:
            _ = try await postJSON(path: "threads/\(threadID)/trash", body: [:], token: token)
        case .untrash:
            _ = try await postJSON(path: "threads/\(threadID)/untrash", body: [:], token: token)
        case .archive:
            _ = try await postJSON(
                path: "threads/\(threadID)/modify",
                body: ["removeLabelIds": ["INBOX"]],
                token: token
            )
        case .setStarred(let starred):
            _ = try await postJSON(
                path: "threads/\(threadID)/modify",
                body: starred ? ["addLabelIds": ["STARRED"]] : ["removeLabelIds": ["STARRED"]],
                token: token
            )
        case .setUnread(let unread):
            _ = try await postJSON(
                path: "threads/\(threadID)/modify",
                body: unread ? ["addLabelIds": ["UNREAD"]] : ["removeLabelIds": ["UNREAD"]],
                token: token
            )
        }
    }

    static func send(draft: MailDraft, connectedEmail: String, token: GoogleOAuthToken) async throws -> String {
        let rawMessage = MailComposerEncoder.buildRawMessage(draft: draft, connectedEmail: connectedEmail)
        var body: [String: Any] = ["raw": rawMessage]
        if let threadID = draft.threadId, !threadID.isEmpty {
            body["threadId"] = threadID
        }
        let response = try await postJSON(path: "messages/send", body: body, token: token)
        return response["id"] as? String ?? ""
    }

    private static func fetchThreadResource(
        id: String,
        queryItems: [URLQueryItem],
        token: GoogleOAuthToken
    ) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appendingPathComponent("threads/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return try await requestJSON(url: components.url!, token: token)
    }

    private static func requestJSON(url: URL, token: GoogleOAuthToken) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MailServiceError.apiError("No response from Gmail.")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw MailServiceError.apiError("Gmail error \(http.statusCode): \(message)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MailServiceError.apiError("Invalid Gmail response.")
        }
        return json
    }

    private static func postJSON(path: String, body: [String: Any], token: GoogleOAuthToken) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MailServiceError.apiError("No response from Gmail.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw MailServiceError.apiError("Gmail error \(http.statusCode): \(message)")
        }
        guard !data.isEmpty else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func headerMap(from message: [String: Any]) -> [String: String] {
        let payload = message["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: Any]] ?? []
        return headers.reduce(into: [String: String]()) { result, header in
            guard let name = header["name"] as? String,
                  let value = header["value"] as? String,
                  result[name] == nil else { return }
            result[name] = value
        }
    }

    private static func parseMessage(_ json: [String: Any], threadID: String) -> MailMessage? {
        guard let id = json["id"] as? String else { return nil }
        let headers = headerMap(from: json)
        let payload = json["payload"] as? [String: Any] ?? [:]
        let body = extractBodies(from: payload)

        return MailMessage(
            id: id,
            threadId: threadID,
            subject: headers["Subject"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(No Subject)",
            snippet: json["snippet"] as? String ?? "",
            labelIds: json["labelIds"] as? [String] ?? [],
            from: parseSingleRecipient(from: headers["From"]),
            to: parseRecipients(from: headers["To"]),
            cc: parseRecipients(from: headers["Cc"]),
            bcc: parseRecipients(from: headers["Bcc"]),
            date: parseRFC2822Date(headers["Date"]),
            plainBody: body.plain,
            htmlBody: body.html,
            messageIDHeader: headers["Message-ID"],
            referencesHeader: headers["References"]
        )
    }

    private static func extractBodies(from payload: [String: Any]) -> (plain: String, html: String?) {
        var plainBody: String?
        var htmlBody: String?

        func visit(_ part: [String: Any]) {
            let mimeType = (part["mimeType"] as? String ?? "").lowercased()
            let filename = part["filename"] as? String ?? ""
            let body = part["body"] as? [String: Any] ?? [:]
            let encodedData = body["data"] as? String

            if filename.isEmpty, let encodedData, let decoded = decodeBase64URL(encodedData) {
                if mimeType == "text/plain" {
                    plainBody = plainBody ?? decoded
                } else if mimeType == "text/html" {
                    htmlBody = htmlBody ?? decoded
                } else if mimeType.isEmpty {
                    plainBody = plainBody ?? decoded
                }
            }

            let parts = part["parts"] as? [[String: Any]] ?? []
            for child in parts {
                visit(child)
            }
        }

        visit(payload)
        return (plainBody ?? "", htmlBody)
    }

    private static func parseSingleRecipient(from header: String?) -> MailMessageRecipient? {
        parseRecipients(from: header).first
    }

    private static func parseRecipients(from header: String?) -> [MailMessageRecipient] {
        guard let header, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return header
            .split(separator: ",")
            .compactMap { chunk in
                let value = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }

                if let start = value.lastIndex(of: "<"),
                   let end = value.lastIndex(of: ">"),
                   start < end {
                    let name = value[..<start]
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\" ").union(.whitespacesAndNewlines))
                    let email = value[value.index(after: start)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                    return MailMessageRecipient(name: name.isEmpty ? nil : name, email: email)
                }

                return MailMessageRecipient(name: nil, email: value)
            }
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseRFC2822Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        for formatter in MailDateParsers.all {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func recipientDisplayName(from header: String?) -> String? {
        parseSingleRecipient(from: header)?.displayName
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}

enum MailServiceError: LocalizedError {
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return message
        }
    }
}

private enum MailDateParsers {
    static let all: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss z",
            "d MMM yyyy HH:mm:ss z",
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}

struct MailCacheStore {
    private let fileManager: FileManager
    private let baseDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(accountEmail: String) -> MailCacheSnapshot? {
        let fileURL = cacheFileURL(for: accountEmail)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(MailCacheSnapshot.self, from: data)
    }

    func save(_ snapshot: MailCacheSnapshot, accountEmail: String) {
        do {
            try ensureBaseDirectoryExists()
            let data = try encoder.encode(snapshot)
            try data.write(to: cacheFileURL(for: accountEmail), options: .atomic)
        } catch {
            Log.mail.error("Failed to save mail cache: \(error.localizedDescription)")
        }
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private func cacheFileURL(for accountEmail: String) -> URL {
        let sanitized = accountEmail
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = sanitized.isEmpty ? "mail-cache" : sanitized
        return baseDirectory.appendingPathComponent("\(filename).json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Bugbook", isDirectory: true)
            .appendingPathComponent("MailCache", isDirectory: true)
    }
}
