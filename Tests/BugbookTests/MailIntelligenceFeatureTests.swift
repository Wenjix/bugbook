import Foundation
import XCTest
@testable import Bugbook
import BugbookCore

@MainActor
final class MailIntelligenceFeatureTests: XCTestCase {
    func testMailModelProviderResolverPrefersAPIKeyInAutoMode() {
        var settings = AppSettings.default
        settings.preferredAIEngine = .auto
        settings.anthropicApiKey = "sk-ant-test"

        let resolved = MailModelProviderResolver.resolve(
            settings: settings,
            engineStatus: AiEngineStatus(claudeAvailable: true, claudeVersion: "1.0", codexAvailable: true, codexVersion: "1.0")
        )

        XCTAssertEqual(resolved, .anthropicAPI)
    }

    func testMailModelProviderResolverFallsBackToCodex() {
        var settings = AppSettings.default
        settings.preferredAIEngine = .auto

        let resolved = MailModelProviderResolver.resolve(
            settings: settings,
            engineStatus: AiEngineStatus(claudeAvailable: false, claudeVersion: nil, codexAvailable: true, codexVersion: "1.0")
        )

        XCTAssertEqual(resolved, .codexCLI)
    }

    func testMailIntelligenceStoreRoundTripsRecords() throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = MailIntelligenceStore(directoryURL: directoryURL)
        let snapshot = MailIntelligenceAccountSnapshot(
            threadRecords: ["thread-1": sampleRecord()],
            savedAt: Date(timeIntervalSince1970: 5_000)
        )

        store.save(snapshot, accountEmail: "Test.User+alias@gmail.com")
        let loaded = try XCTUnwrap(store.load(accountEmail: "Test.User+alias@gmail.com"))

        XCTAssertEqual(loaded, snapshot)
    }

    func testMailAgentSessionStoreRoundTripsWorkspaceSnapshot() throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let fixedDate = Date(timeIntervalSince1970: 100)
        let store = MailAgentSessionStore()
        let snapshot = MailWorkspaceIntelligenceSnapshot(
            priorityOverrides: [
                MailPriorityOverride(
                    senderEmail: "alice@example.com",
                    priority: .high,
                    note: "Founder emails are urgent",
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ],
            memories: [
                MailMemory(
                    kind: .writingStyle,
                    title: "Tone",
                    detail: "Keep replies concise.",
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ],
            agentSessions: [
                MailAgentSession(
                    id: "session-1",
                    threadID: "thread-1",
                    proposals: [MailAgentActionProposal(id: "proposal-1", kind: .createTask, title: "Create Task", detail: "Turn this into work.")],
                    entries: [MailAgentSessionEntry(id: "entry-1", role: .system, content: "Started", createdAt: fixedDate)],
                    createdAt: fixedDate,
                    updatedAt: fixedDate
                )
            ]
        )

        store.save(snapshot, workspacePath: workspace.path)
        let loaded = store.load(workspacePath: workspace.path)

        XCTAssertEqual(loaded, snapshot)
    }

    func testMailServiceApplyIntelligenceRecordAnnotatesThreadState() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let service = MailService(cacheStore: MailCacheStore(directoryURL: directoryURL))
        let snapshot = sampleSnapshot(savedAt: Date(timeIntervalSince1970: 200))
        service.mailboxThreads = snapshot.mailboxThreads
        service.threadDetails = snapshot.threadDetails

        let record = sampleRecord()
        service.applyIntelligenceRecord(record)

        XCTAssertEqual(service.mailboxThreads[.inbox]?.first?.annotation?.suggestedPriority, .high)
        XCTAssertEqual(service.threadDetails["thread-1"]?.annotation?.statusFlags, [.needsReply])
        XCTAssertEqual(service.threadDetails["thread-1"]?.draftSuggestion?.body, "Thanks for the update. I can take this on.")
        XCTAssertEqual(service.threadDetails["thread-1"]?.senderContext?.senderEmail, "alice@example.com")
    }

    func testMailIntelligenceServiceLearnsFromSentDraftAndPersistsWorkspaceMemory() {
        let cacheDirectory = temporaryDirectory()
        let intelligenceDirectory = temporaryDirectory()
        let workspaceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: cacheDirectory)
            try? FileManager.default.removeItem(at: intelligenceDirectory)
            try? FileManager.default.removeItem(at: workspaceDirectory)
        }

        let service = MailIntelligenceService(
            accountStore: MailIntelligenceStore(directoryURL: intelligenceDirectory),
            workspaceStore: MailAgentSessionStore(),
            fileSystem: FileSystemService(),
            agentWorkspaceStore: AgentWorkspaceStore()
        )
        let mailService = MailService(cacheStore: MailCacheStore(directoryURL: cacheDirectory))
        service.load(accountEmail: "me@example.com", workspacePath: workspaceDirectory.path, mailService: mailService)
        service.records["thread-1"] = sampleRecord()

        service.learnFromSentDraft(threadID: "thread-1", subject: "Hello", finalBody: "Thanks. I will handle this today.")

        XCTAssertEqual(service.records["thread-1"]?.annotation.draftStatus, .edited)
        XCTAssertEqual(service.memories.first?.kind, .writingStyle)
        XCTAssertTrue(service.memories.first?.detail.contains("Thanks. I will handle this today.") ?? false)

        let reloaded = MailAgentSessionStore().load(workspacePath: workspaceDirectory.path)
        XCTAssertEqual(reloaded.memories.first?.kind, .writingStyle)
    }

    private func sampleRecord() -> MailThreadIntelligenceRecord {
        let fixedDate = Date(timeIntervalSince1970: 100)
        return MailThreadIntelligenceRecord(
            threadID: "thread-1",
            sourceSignature: "history-1",
            annotation: MailThreadAnnotation(
                analysisStatus: .complete,
                analysisUpdatedAt: fixedDate,
                suggestedPriority: .high,
                statusFlags: [.needsReply],
                draftStatus: .suggested,
                hasSenderContext: true
            ),
            analysis: MailThreadAnalysis(
                priority: .high,
                reason: "This thread is asking for a direct response.",
                suggestedAction: "Reply with next steps.",
                flags: [.needsReply],
                shouldGenerateDraft: true,
                prefersReplyAll: false,
                analyzedAt: fixedDate
            ),
            draftSuggestion: MailDraftSuggestion(
                id: "draft-1",
                threadID: "thread-1",
                subject: "Re: Hello",
                body: "Thanks for the update. I can take this on.",
                rationale: "Direct and concise.",
                generatedAt: fixedDate
            ),
            senderContext: MailSenderContext(
                threadID: "thread-1",
                senderName: "Alice",
                senderEmail: "alice@example.com",
                summary: "Alice is tied to roadmap work.",
                references: [MailSenderContextReference(id: "ref-1", path: "/tmp/roadmap.md", excerpt: "Alice owns roadmap planning.")],
                generatedAt: fixedDate
            ),
            acceptedDraftBody: "Thanks for the update.",
            editedDraftBody: nil,
            updatedAt: fixedDate
        )
    }

    private func sampleSnapshot(savedAt: Date) -> MailCacheSnapshot {
        let sender = MailMessageRecipient(name: "Alice", email: "alice@example.com")
        let message = MailMessage(
            id: "message-1",
            threadId: "thread-1",
            subject: "Hello",
            snippet: "Test snippet",
            labelIds: ["INBOX", "UNREAD"],
            from: sender,
            to: [MailMessageRecipient(name: "Me", email: "me@example.com")],
            cc: [],
            bcc: [],
            date: Date(timeIntervalSince1970: 100),
            plainBody: "Hello world",
            htmlBody: nil,
            messageIDHeader: "<message-1@example.com>",
            referencesHeader: nil
        )

        let detail = MailThreadDetail(
            id: "thread-1",
            mailbox: .inbox,
            subject: "Hello",
            snippet: "Test snippet",
            participants: [sender.displayName],
            messages: [message],
            labelIds: ["INBOX", "UNREAD"],
            historyId: "history-1",
            annotation: nil,
            draftSuggestion: nil,
            senderContext: nil
        )

        let summary = MailThreadSummary(
            id: "thread-1",
            mailbox: .inbox,
            subject: "Hello",
            snippet: "Test snippet",
            participants: [sender.displayName],
            date: Date(timeIntervalSince1970: 100),
            messageCount: 1,
            labelIds: ["INBOX", "UNREAD"],
            historyId: "history-1",
            annotation: nil
        )

        return MailCacheSnapshot(
            mailboxThreads: [.inbox: [summary]],
            threadDetails: ["thread-1": detail],
            savedAt: savedAt
        )
    }

    private func temporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
