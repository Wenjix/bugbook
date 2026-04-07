import Foundation
import WebKit

@MainActor
struct BrowserAgentService {
    struct SaveResult {
        let record: SavedWebPageRecord
        let notePath: String
    }

    private let savedPageStore: SavedWebPageStore

    init(savedPageStore: SavedWebPageStore = SavedWebPageStore()) {
        self.savedPageStore = savedPageStore
    }

    func listTabs(browserManager: BrowserManager) -> [BrowserTabState] {
        browserManager.sessions.values
            .flatMap(\.tabs)
            .filter { !$0.urlString.isEmpty || $0.title != "New Tab" }
    }

    func listReadLater(in workspacePath: String) -> [SavedWebPageRecord] {
        savedPageStore.records(in: workspacePath).filter { $0.status == .unread }
    }

    func openURL(_ url: URL, in paneID: UUID, browserManager: BrowserManager, newTab: Bool) {
        browserManager.openURL(url, in: paneID, newTab: newTab)
    }

    func extractPageContent(from paneID: UUID, tabID: UUID, browserManager: BrowserManager) async -> String {
        let webView = browserManager.ensureWebView(for: paneID, tabID: tabID)
        let script = """
        (() => {
          const title = document.title || '';
          const text = (document.body && document.body.innerText ? document.body.innerText : '').trim();
          return JSON.stringify({ title, text, url: location.href });
        })()
        """

        guard let raw = try? await evaluateJavaScript(script, in: webView),
              let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PageExtractionPayload.self, from: data) else {
            return ""
        }

        return payload.text
    }

    func saveTab(
        from paneID: UUID,
        tabID: UUID,
        browserManager: BrowserManager,
        fileSystem: FileSystemService,
        workspacePath: String,
        settings: AppSettings,
        aiService: AiService?
    ) async throws -> SaveResult {
        let webView = browserManager.ensureWebView(for: paneID, tabID: tabID)
        let payload = try await extractPayload(from: webView)

        if let existing = savedPageStore.record(forURL: payload.url.absoluteString, in: workspacePath) {
            browserManager.session(for: paneID).updateSavedRecordID(existing.id, for: tabID)
            return SaveResult(record: existing, notePath: existing.notePath)
        }

        let folderPath = resolvedSaveFolder(settings.browserDefaultSaveFolder, workspacePath: workspacePath)
        if !FileManager.default.fileExists(atPath: folderPath) {
            try fileSystem.createFolder(at: folderPath)
        }

        let title = sanitizedTitle(payload.title.isEmpty ? payload.url.host ?? "Web Page" : payload.title)
        let notePath = try fileSystem.createNewFile(in: folderPath, name: title)
        let summary = await summarizePage(payload, workspacePath: workspacePath, aiService: aiService)
        let content = noteContent(title: title, payload: payload, summary: summary, status: .unread)
        try fileSystem.saveFile(at: notePath, content: content)

        let record = SavedWebPageRecord(
            title: title,
            urlString: payload.url.absoluteString,
            folderPath: folderPath,
            notePath: notePath,
            status: .unread,
            summary: summary
        )
        savedPageStore.upsert(record, in: workspacePath)
        browserManager.session(for: paneID).updateSavedRecordID(record.id, for: tabID)
        return SaveResult(record: record, notePath: notePath)
    }

    func unsave(recordID: UUID, workspacePath: String) {
        savedPageStore.remove(recordID: recordID, in: workspacePath)
    }

    func proposeCleanup(for paneID: UUID, browserManager: BrowserManager, workspacePath: String?) -> [BrowserCleanupProposal] {
        let session = browserManager.session(for: paneID)
        let savedURLs = Set((workspacePath.map { savedPageStore.records(in: $0) } ?? []).map(\.urlString))
        var seenURLs: Set<String> = []

        return session.tabs.compactMap { tab in
            guard !tab.urlString.isEmpty else {
                return BrowserCleanupProposal(
                    tabID: tab.id,
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    decision: .close,
                    reason: "Blank tab"
                )
            }

            if !seenURLs.insert(tab.urlString).inserted {
                return BrowserCleanupProposal(
                    tabID: tab.id,
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    decision: .close,
                    reason: "Duplicate tab"
                )
            }

            if savedURLs.contains(tab.urlString) {
                return BrowserCleanupProposal(
                    tabID: tab.id,
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    decision: .close,
                    reason: "Already saved to Bugbook"
                )
            }

            if tab.urlString.contains("mail.google.com") || tab.urlString.contains("calendar.google.com") {
                return BrowserCleanupProposal(
                    tabID: tab.id,
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    decision: .close,
                    reason: "Covered by a dedicated Bugbook pane"
                )
            }

            if tab.urlString.contains("github.com") || tab.urlString.contains("developer.apple.com") {
                return BrowserCleanupProposal(
                    tabID: tab.id,
                    title: tab.displayTitle,
                    urlString: tab.urlString,
                    decision: .readLater,
                    reason: "Looks worth keeping for later review"
                )
            }

            return BrowserCleanupProposal(
                tabID: tab.id,
                title: tab.displayTitle,
                urlString: tab.urlString,
                decision: .keep,
                reason: "No strong cleanup signal"
            )
        }
    }

    func applyCleanup(
        _ proposals: [BrowserCleanupProposal],
        paneID: UUID,
        browserManager: BrowserManager,
        fileSystem: FileSystemService,
        workspacePath: String,
        settings: AppSettings,
        aiService: AiService?
    ) async -> String {
        var saved = 0
        var closed = 0
        var queued = 0

        for proposal in proposals {
            switch proposal.decision {
            case .save:
                if (try? await saveTab(
                    from: paneID,
                    tabID: proposal.tabID,
                    browserManager: browserManager,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    settings: settings,
                    aiService: aiService
                )) != nil {
                    saved += 1
                }
            case .readLater:
                if let result = try? await saveTab(
                    from: paneID,
                    tabID: proposal.tabID,
                    browserManager: browserManager,
                    fileSystem: fileSystem,
                    workspacePath: workspacePath,
                    settings: settings,
                    aiService: aiService
                ) {
                    savedPageStore.markStatus(.unread, for: result.record.id, in: workspacePath)
                    queued += 1
                }
            case .close:
                browserManager.session(for: paneID).closeTab(proposal.tabID)
                closed += 1
            case .keep:
                break
            }
        }

        return "Saved \(saved), queued \(queued), closed \(closed)"
    }

    private func extractPayload(from webView: WKWebView) async throws -> PageExtractionPayload {
        let script = """
        (() => {
          const title = document.title || '';
          const text = (document.body && document.body.innerText ? document.body.innerText : '').trim().slice(0, 20000);
          return JSON.stringify({ title, text, url: location.href });
        })()
        """

        let raw = try await evaluateJavaScript(script, in: webView)
        guard let data = raw.data(using: .utf8) else {
            throw BrowserAgentError.invalidPagePayload
        }
        let payload = try JSONDecoder().decode(PageExtractionPayload.self, from: data)
        guard URL(string: payload.urlString) != nil else {
            throw BrowserAgentError.invalidPagePayload
        }
        return payload
    }

    private func summarizePage(_ payload: PageExtractionPayload, workspacePath: String, aiService: AiService?) async -> String {
        let trimmedText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "Saved from \(payload.url.host ?? payload.url.absoluteString)." }

        guard let aiService else {
            return fallbackSummary(from: trimmedText)
        }

        let status = await aiService.ensureDetectedEngines()
        guard status.claudeAvailable || status.codexAvailable else {
            return fallbackSummary(from: trimmedText)
        }

        let prompt = """
        Summarize this web page in 3 short bullet points. Focus on what it is and why it matters.

        Title: \(payload.title)
        URL: \(payload.url.absoluteString)
        Content:
        \(trimmedText.prefix(4000))
        """

        if let response = try? await aiService.chatWithNotes(
            engine: .auto,
            workspacePath: workspacePath,
            question: prompt
        ) {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return fallbackSummary(from: trimmedText)
    }

    private func fallbackSummary(from text: String) -> String {
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sentences.prefix(3).map { "- \($0)" }.joined(separator: "\n")
    }

    private func noteContent(title: String, payload: PageExtractionPayload, summary: String, status: SavedWebPageStatus) -> String {
        """
        # \(title)

        - URL: \(payload.url.absoluteString)
        - Saved: \(Date.now.formatted(date: .abbreviated, time: .shortened))
        - Status: \(status.rawValue)

        ## Summary

        \(summary)

        ## Excerpt

        \(payload.text.prefix(6000))
        """
    }

    private func resolvedSaveFolder(_ value: String, workspacePath: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return workspacePath }
        if trimmed.hasPrefix("/") { return trimmed }
        return (workspacePath as NSString).appendingPathComponent(trimmed)
    }

    private func sanitizedTitle(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Saved Page" : String(sanitized.prefix(80))
    }

    private func evaluateJavaScript(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: BrowserAgentError.invalidPagePayload)
                }
            }
        }
    }
}

private struct PageExtractionPayload: Codable {
    var title: String
    var text: String
    var urlString: String

    var url: URL {
        URL(string: urlString) ?? URL(string: "about:blank")!
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case text
        case urlString = "url"
    }
}

private enum BrowserAgentError: Error {
    case invalidPagePayload
}
