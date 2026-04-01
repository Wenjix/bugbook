import Foundation
import BugbookCore

enum MailIntelligenceError: LocalizedError {
    case noModelProvider
    case missingWorkspace
    case missingCalendarToken
    case noSelectedThread

    var errorDescription: String? {
        switch self {
        case .noModelProvider:
            return "Configure an AI engine before using Mail intelligence."
        case .missingWorkspace:
            return "Open a workspace to use Bugbook-linked mail actions."
        case .missingCalendarToken:
            return "Connect Google Calendar before creating events from Mail."
        case .noSelectedThread:
            return "Select a thread first."
        }
    }
}

enum MailModelExecutionPath: String, Equatable {
    case anthropicAPI
    case claudeCLI
    case codexCLI
    case unavailable
}

struct MailModelProviderResolver {
    static func resolve(settings: AppSettings, engineStatus: AiEngineStatus) -> MailModelExecutionPath {
        let hasAPIKey = !settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch settings.preferredAIEngine {
        case .claudeAPI:
            return hasAPIKey ? .anthropicAPI : .unavailable
        case .claude:
            return engineStatus.claudeAvailable ? .claudeCLI : .unavailable
        case .codex:
            return engineStatus.codexAvailable ? .codexCLI : .unavailable
        case .auto:
            if hasAPIKey { return .anthropicAPI }
            if engineStatus.claudeAvailable { return .claudeCLI }
            if engineStatus.codexAvailable { return .codexCLI }
            return .unavailable
        }
    }
}

@MainActor
protocol MailModelProvider {
    func executionPath(using settings: AppSettings) async -> MailModelExecutionPath
    func generate(systemPrompt: String, userPrompt: String, workspacePath: String?, settings: AppSettings, maxTokens: Int) async throws -> String
}

@MainActor
final class AiServiceMailModelProvider: MailModelProvider {
    private let aiService: AiService

    init(aiService: AiService) {
        self.aiService = aiService
    }

    func executionPath(using settings: AppSettings) async -> MailModelExecutionPath {
        let status = await aiService.ensureDetectedEngines()
        return MailModelProviderResolver.resolve(settings: settings, engineStatus: status)
    }

    func generate(
        systemPrompt: String,
        userPrompt: String,
        workspacePath: String?,
        settings: AppSettings,
        maxTokens: Int = 2048
    ) async throws -> String {
        let path = await executionPath(using: settings)
        let engine: PreferredAIEngine

        switch path {
        case .anthropicAPI:
            engine = .claudeAPI
        case .claudeCLI:
            engine = .claude
        case .codexCLI:
            engine = .codex
        case .unavailable:
            throw MailIntelligenceError.noModelProvider
        }

        return try await aiService.executePrompt(
            engine: engine,
            workspacePath: workspacePath,
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            apiKey: settings.anthropicApiKey,
            model: settings.anthropicModel,
            maxTokens: maxTokens
        )
    }
}

@MainActor
@Observable
final class MailIntelligenceService {
    var records: [String: MailThreadIntelligenceRecord] = [:]
    var priorityOverrides: [MailPriorityOverride] = []
    var memories: [MailMemory] = []
    var agentSessions: [String: MailAgentSession] = [:]
    var isAnalyzing = false
    var isGeneratingDraft = false
    var isLoadingContext = false
    var isRunningAgentAction = false
    var lastSavedAt: Date?
    var error: String?

    @ObservationIgnored private let accountStore: MailIntelligenceStore
    @ObservationIgnored private let workspaceStore: MailAgentSessionStore
    @ObservationIgnored private let fileSystem: FileSystemService
    @ObservationIgnored private let agentWorkspaceStore: AgentWorkspaceStore

    private var activeAccountEmail: String?
    private var activeWorkspacePath: String?

    init(
        accountStore: MailIntelligenceStore = MailIntelligenceStore(),
        workspaceStore: MailAgentSessionStore = MailAgentSessionStore(),
        fileSystem: FileSystemService? = nil,
        agentWorkspaceStore: AgentWorkspaceStore = AgentWorkspaceStore()
    ) {
        self.accountStore = accountStore
        self.workspaceStore = workspaceStore
        self.fileSystem = fileSystem ?? FileSystemService()
        self.agentWorkspaceStore = agentWorkspaceStore
    }

    func load(accountEmail: String, workspacePath: String?, mailService: MailService) {
        let normalizedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if activeAccountEmail != normalizedEmail {
            records = [:]
            lastSavedAt = nil
        }

        activeAccountEmail = normalizedEmail
        if let snapshot = accountStore.load(accountEmail: normalizedEmail) {
            records = snapshot.threadRecords
            lastSavedAt = snapshot.savedAt
        }

        if let workspacePath {
            activeWorkspacePath = workspacePath
            let snapshot = workspaceStore.load(workspacePath: workspacePath)
            priorityOverrides = snapshot.priorityOverrides
            memories = snapshot.memories
            agentSessions = Dictionary(uniqueKeysWithValues: snapshot.agentSessions.map { ($0.threadID, $0) })
        } else {
            activeWorkspacePath = nil
            priorityOverrides = []
            memories = []
            agentSessions = [:]
        }

        mailService.applyIntelligenceRecords(records)
    }

    func record(for threadID: String) -> MailThreadIntelligenceRecord? {
        records[threadID]
    }

    func session(for thread: MailThreadDetail) -> MailAgentSession {
        if let existing = agentSessions[thread.id] {
            return existing
        }

        let newSession = MailAgentSession(
            threadID: thread.id,
            proposals: defaultProposals(for: thread),
            entries: [
                MailAgentSessionEntry(
                    role: .system,
                    content: "Mail agent session started for \(thread.subject). Actions stay local to this workspace."
                )
            ]
        )
        agentSessions[thread.id] = newSession
        persistWorkspaceStateIfPossible()
        return newSession
    }

    func runBackgroundAnalysis(
        mailService: MailService,
        token: GoogleOAuthToken,
        settings: AppSettings,
        workspacePath: String?,
        aiService: AiService
    ) async {
        guard settings.mailBackgroundAnalysisEnabled else { return }
        let provider = AiServiceMailModelProvider(aiService: aiService)
        guard await provider.executionPath(using: settings) != .unavailable else { return }

        let inboxThreads = mailService.mailboxThreads[.inbox] ?? []
        let candidates = inboxThreads.filter { shouldRefresh(thread: $0) }
        guard !candidates.isEmpty else { return }

        isAnalyzing = true
        error = nil
        defer {
            isAnalyzing = false
            persistAccountStateIfPossible()
        }

        for threadSummary in candidates {
            do {
                let detail = try await mailService.fetchThreadDetailSnapshot(
                    id: threadSummary.id,
                    mailbox: threadSummary.mailbox ?? .inbox,
                    token: token
                )
                let record = try await analyze(thread: detail, summary: threadSummary, workspacePath: workspacePath, settings: settings, provider: provider)
                upsert(record, into: mailService)

                if settings.mailBackgroundDraftGenerationEnabled,
                   let analysis = record.analysis,
                   analysis.shouldGenerateDraft {
                    try await generateDraftIfNeeded(for: detail, mailService: mailService, settings: settings, workspacePath: workspacePath, provider: provider)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func ensureThreadArtifacts(
        for thread: MailThreadDetail,
        mailService: MailService,
        settings: AppSettings,
        workspacePath: String?,
        aiService: AiService
    ) async {
        let provider = AiServiceMailModelProvider(aiService: aiService)
        if record(for: thread.id)?.analysis == nil,
           settings.mailBackgroundAnalysisEnabled,
           await provider.executionPath(using: settings) != .unavailable {
            do {
                let syntheticSummary = MailThreadSummary(
                    id: thread.id,
                    mailbox: thread.mailbox,
                    subject: thread.subject,
                    snippet: thread.snippet,
                    participants: thread.participants,
                    date: thread.lastDate,
                    messageCount: thread.messages.count,
                    labelIds: thread.labelIds,
                    historyId: thread.historyId
                )
                let record = try await analyze(thread: thread, summary: syntheticSummary, workspacePath: workspacePath, settings: settings, provider: provider)
                upsert(record, into: mailService)
            } catch {
                self.error = error.localizedDescription
            }
        }

        if settings.mailBackgroundDraftGenerationEnabled,
           let analysis = records[thread.id]?.analysis,
           analysis.shouldGenerateDraft,
           records[thread.id]?.draftSuggestion == nil,
           await provider.executionPath(using: settings) != .unavailable {
            do {
                try await generateDraftIfNeeded(for: thread, mailService: mailService, settings: settings, workspacePath: workspacePath, provider: provider)
            } catch {
                self.error = error.localizedDescription
            }
        }

        if settings.mailSenderLookupEnabled, records[thread.id]?.senderContext == nil {
            do {
                let context = try await buildSenderContext(for: thread, workspacePath: workspacePath, settings: settings, provider: provider)
                var record = records[thread.id] ?? MailThreadIntelligenceRecord(threadID: thread.id)
                record.senderContext = context
                record.annotation.hasSenderContext = true
                record.updatedAt = Date()
                upsert(record, into: mailService)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func refineDraft(
        for thread: MailThreadDetail,
        instruction: String,
        mailService: MailService,
        settings: AppSettings,
        workspacePath: String?,
        aiService: AiService
    ) async {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else { return }

        let provider = AiServiceMailModelProvider(aiService: aiService)
        guard await provider.executionPath(using: settings) != .unavailable else {
            error = MailIntelligenceError.noModelProvider.localizedDescription
            return
        }

        guard var record = records[thread.id], let draft = record.draftSuggestion else { return }

        isGeneratingDraft = true
        error = nil
        defer {
            isGeneratingDraft = false
            persistAccountStateIfPossible()
        }

        do {
            let systemPrompt = """
            You refine an email reply draft for a human user. Return only JSON with keys:
            body, rationale.
            Keep the same intent unless the instruction explicitly changes it.
            """
            let prompt = """
            Thread subject: \(thread.subject)

            Existing draft:
            \(draft.body)

            Refinement instruction:
            \(trimmedInstruction)
            """
            let response = try await provider.generate(
                systemPrompt: systemPrompt,
                userPrompt: prompt,
                workspacePath: workspacePath,
                settings: settings,
                maxTokens: 1400
            )
            let payload = try decodeJSON(response, as: DraftRefinementPayload.self)
            let refinement = MailDraftRefinement(instruction: trimmedInstruction, body: payload.body)
            record.draftSuggestion?.body = payload.body
            record.draftSuggestion?.rationale = payload.rationale
            record.draftSuggestion?.status = .suggested
            record.draftSuggestion?.refinementHistory.append(refinement)
            record.annotation.draftStatus = .suggested
            record.updatedAt = Date()
            upsert(record, into: mailService)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func acceptDraft(for thread: MailThreadDetail, connectedEmail: String, mailService: MailService) {
        guard var record = records[thread.id], var draftSuggestion = record.draftSuggestion else { return }
        mailService.prepareReplyDraft(
            thread: thread,
            connectedEmail: connectedEmail,
            replyAll: record.analysis?.prefersReplyAll ?? false
        )
        mailService.composer.subject = draftSuggestion.subject
        mailService.composer.body = draftSuggestion.body
        draftSuggestion.status = .accepted
        record.draftSuggestion = draftSuggestion
        record.acceptedDraftBody = draftSuggestion.body
        record.annotation.draftStatus = .accepted
        record.updatedAt = Date()
        upsert(record, into: mailService)
    }

    func recordDraftEditIfNeeded(for threadID: String, finalBody: String) {
        guard var record = records[threadID] else { return }
        let normalizedFinal = finalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFinal.isEmpty else { return }
        record.editedDraftBody = normalizedFinal
        if normalizedFinal != record.acceptedDraftBody?.trimmingCharacters(in: .whitespacesAndNewlines) {
            record.annotation.draftStatus = .edited
            record.draftSuggestion?.status = .edited
        }
        record.updatedAt = Date()
        records[threadID] = record
        persistAccountStateIfPossible()
    }

    func learnFromSentDraft(threadID: String, subject: String, finalBody: String) {
        let trimmedBody = finalBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }

        recordDraftEditIfNeeded(for: threadID, finalBody: trimmedBody)

        let senderEmail = activeAccountEmail
        let senderDomain = senderEmail?.split(separator: "@").last.map(String.init)
        let excerpt = trimmedBody
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(3)
            .joined(separator: " ")

        memories.insert(
            MailMemory(
                kind: .writingStyle,
                title: "Sent style: \(subject)",
                detail: excerpt.isEmpty ? trimmedBody : excerpt,
                senderEmail: senderEmail,
                senderDomain: senderDomain
            ),
            at: 0
        )
        persistWorkspaceStateIfPossible()
    }

    func recordPriorityOverride(
        _ priority: MailPriority,
        note: String,
        for thread: MailThreadDetail,
        mailService: MailService
    ) {
        let subjectToken = subjectHint(for: thread.subject)
        let senderEmail = thread.messages.last?.from?.email.lowercased()
        let senderDomain = senderEmail?.split(separator: "@").last.map(String.init)

        let override = MailPriorityOverride(
            senderEmail: senderEmail,
            senderDomain: senderDomain,
            subjectContains: subjectToken,
            priority: priority,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        priorityOverrides.insert(override, at: 0)

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memories.insert(
                MailMemory(
                    kind: .priorityPreference,
                    title: "Priority override for \(thread.subject)",
                    detail: note,
                    senderEmail: senderEmail,
                    senderDomain: senderDomain
                ),
                at: 0
            )
        }

        var record = records[thread.id] ?? MailThreadIntelligenceRecord(threadID: thread.id)
        record.annotation.suggestedPriority = priority
        record.analysis?.priority = priority
        record.updatedAt = Date()
        upsert(record, into: mailService)
        persistWorkspaceStateIfPossible()
    }

    func createManualMemory(title: String, detail: String, thread: MailThreadDetail) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDetail.isEmpty else { return }

        let senderEmail = thread.messages.last?.from?.email.lowercased()
        let senderDomain = senderEmail?.split(separator: "@").last.map(String.init)
        memories.insert(
            MailMemory(
                kind: .manualNote,
                title: trimmedTitle,
                detail: trimmedDetail,
                senderEmail: senderEmail,
                senderDomain: senderDomain
            ),
            at: 0
        )
        persistWorkspaceStateIfPossible()
    }

    func performAgentAction(
        _ action: MailAgentActionKind,
        thread: MailThreadDetail,
        mailService: MailService,
        settings: AppSettings,
        workspacePath: String?,
        aiService: AiService,
        calendarService: CalendarService,
        calendarToken: GoogleOAuthToken?
    ) async -> String? {
        guard let workspacePath else {
            error = MailIntelligenceError.missingWorkspace.localizedDescription
            return nil
        }

        isRunningAgentAction = true
        defer { isRunningAgentAction = false }

        var session = session(for: thread)
        session.entries.append(MailAgentSessionEntry(role: .user, content: action.displayName))
        agentSessions[thread.id] = session
        persistWorkspaceStateIfPossible()

        let run = try? agentWorkspaceStore.startRun(
            in: workspacePath,
            agent: "mail-agent",
            cwd: workspacePath
        )
        defer {
            if let run {
                _ = try? agentWorkspaceStore.finishRun(
                    in: workspacePath,
                    runId: run.id,
                    status: .succeeded,
                    summary: "Completed \(action.displayName.lowercased()) for \(thread.subject)"
                )
            }
        }

        do {
            let result: String
            switch action {
            case .draftReply:
                await ensureThreadArtifacts(
                    for: thread,
                    mailService: mailService,
                    settings: settings,
                    workspacePath: workspacePath,
                    aiService: aiService
                )
                acceptDraft(for: thread, connectedEmail: settings.googleConnectedEmail, mailService: mailService)
                result = "Inserted a suggested reply into the composer."
            case .createTask:
                let task = try agentWorkspaceStore.createTask(
                    in: workspacePath,
                    title: thread.subject,
                    detail: taskDetail(for: thread),
                    labels: ["mail"]
                )
                result = "Created task \(task.title)."
            case .createNote:
                let path = try createNote(from: thread, workspacePath: workspacePath, titlePrefix: "Mail Note")
                result = "Created note at \(path)."
            case .createCalendarEvent:
                guard let calendarToken else { throw MailIntelligenceError.missingCalendarToken }
                let draft = calendarDraft(for: thread)
                let event = try await calendarService.createGoogleEvent(
                    workspace: workspacePath,
                    token: calendarToken,
                    draft: draft
                )
                result = "Created calendar event \(event.title)."
            case .summarizeToNote:
                let path = try await createSummaryNote(from: thread, settings: settings, workspacePath: workspacePath, aiService: aiService)
                result = "Created thread summary note at \(path)."
            case .gatherContext:
                await ensureThreadArtifacts(
                    for: thread,
                    mailService: mailService,
                    settings: settings,
                    workspacePath: workspacePath,
                    aiService: aiService
                )
                result = "Updated sender context from local workspace notes."
            }

            var updatedSession = self.session(for: thread)
            updatedSession.entries.append(MailAgentSessionEntry(role: .action, content: result))
            updatedSession.updatedAt = Date()
            agentSessions[thread.id] = updatedSession
            persistWorkspaceStateIfPossible()
            if let run {
                _ = try? agentWorkspaceStore.logEvent(in: workspacePath, runId: run.id, level: .info, message: result)
            }
            return result
        } catch {
            self.error = error.localizedDescription
            var updatedSession = self.session(for: thread)
            updatedSession.entries.append(MailAgentSessionEntry(role: .assistant, content: error.localizedDescription))
            updatedSession.updatedAt = Date()
            agentSessions[thread.id] = updatedSession
            persistWorkspaceStateIfPossible()
            if let run {
                _ = try? agentWorkspaceStore.logEvent(in: workspacePath, runId: run.id, level: .error, message: error.localizedDescription)
                _ = try? agentWorkspaceStore.finishRun(
                    in: workspacePath,
                    runId: run.id,
                    status: .failed,
                    summary: error.localizedDescription
                )
            }
            return nil
        }
    }

    private func shouldRefresh(thread: MailThreadSummary) -> Bool {
        let record = records[thread.id]
        guard let sourceSignature = threadSignature(thread: thread) else {
            return record == nil
        }
        return record?.sourceSignature != sourceSignature
    }

    private func analyze(
        thread: MailThreadDetail,
        summary: MailThreadSummary,
        workspacePath: String?,
        settings: AppSettings,
        provider: MailModelProvider
    ) async throws -> MailThreadIntelligenceRecord {
        let systemPrompt = """
        You triage an email thread for a local-first desktop mail client inspired by Exo.
        Return only JSON with keys:
        priority, reason, suggested_action, flags, should_generate_draft, prefers_reply_all.
        priority must be one of: high, medium, low, skip.
        flags must only contain: needs_reply, waiting, archive_ready.
        Be concise, pragmatic, and prioritize actionable triage.
        """
        let prompt = """
        Connected account: \(settings.googleConnectedEmail)

        Thread:
        \(threadTranscript(for: thread))

        Local preferences:
        \(memoryPrompt(for: thread))
        """
        let response = try await provider.generate(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            workspacePath: workspacePath,
            settings: settings,
            maxTokens: 1200
        )
        let payload = try decodeJSON(response, as: AnalysisPayload.self)
        let priority = appliedPriorityOverride(for: thread) ?? payload.priority
        let analysis = MailThreadAnalysis(
            priority: priority,
            reason: payload.reason,
            suggestedAction: payload.suggestedAction,
            flags: payload.flags,
            shouldGenerateDraft: payload.shouldGenerateDraft,
            prefersReplyAll: payload.prefersReplyAll,
            analyzedAt: Date()
        )
        let annotation = MailThreadAnnotation(
            analysisStatus: .complete,
            analysisUpdatedAt: analysis.analyzedAt,
            suggestedPriority: priority,
            statusFlags: analysis.flags,
            draftStatus: records[thread.id]?.annotation.draftStatus ?? .none,
            hasSenderContext: records[thread.id]?.annotation.hasSenderContext ?? false
        )
        return MailThreadIntelligenceRecord(
            threadID: thread.id,
            sourceSignature: threadSignature(thread: summary),
            annotation: annotation,
            analysis: analysis,
            draftSuggestion: records[thread.id]?.draftSuggestion,
            senderContext: records[thread.id]?.senderContext,
            acceptedDraftBody: records[thread.id]?.acceptedDraftBody,
            editedDraftBody: records[thread.id]?.editedDraftBody,
            updatedAt: Date()
        )
    }

    private func generateDraftIfNeeded(
        for thread: MailThreadDetail,
        mailService: MailService,
        settings: AppSettings,
        workspacePath: String?,
        provider: MailModelProvider
    ) async throws {
        guard let analysis = records[thread.id]?.analysis, analysis.shouldGenerateDraft else { return }
        guard records[thread.id]?.draftSuggestion == nil else { return }

        isGeneratingDraft = true
        defer { isGeneratingDraft = false }

        let systemPrompt = """
        You draft a thoughtful email reply for a human user.
        Return only JSON with keys:
        subject, body, rationale.
        The draft must be ready for review, not for auto-send.
        """
        let prompt = """
        Connected account: \(settings.googleConnectedEmail)
        Thread subject: \(thread.subject)
        Suggested action: \(analysis.suggestedAction)

        Thread:
        \(threadTranscript(for: thread))

        Writing preferences and local memories:
        \(memoryPrompt(for: thread))
        """
        let response = try await provider.generate(
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            workspacePath: workspacePath,
            settings: settings,
            maxTokens: 1800
        )
        let payload = try decodeJSON(response, as: DraftPayload.self)
        var record = records[thread.id] ?? MailThreadIntelligenceRecord(threadID: thread.id)
        record.draftSuggestion = MailDraftSuggestion(
            threadID: thread.id,
            subject: payload.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MailService.replySubject(for: thread.subject) : payload.subject,
            body: payload.body,
            rationale: payload.rationale
        )
        record.annotation.draftStatus = .suggested
        record.updatedAt = Date()
        upsert(record, into: mailService)
    }

    private func buildSenderContext(
        for thread: MailThreadDetail,
        workspacePath: String?,
        settings: AppSettings,
        provider: MailModelProvider
    ) async throws -> MailSenderContext {
        isLoadingContext = true
        defer { isLoadingContext = false }

        let sender = thread.messages.last?.from ?? thread.messages.first?.from ?? MailMessageRecipient(name: nil, email: "unknown@example.com")
        let references = workspaceMatches(for: thread, workspacePath: workspacePath)

        var summary = references.isEmpty
            ? "No related workspace notes matched this sender yet."
            : references.prefix(3).map { "\(($0.path as NSString).lastPathComponent): \($0.excerpt)" }.joined(separator: "\n")

        if !references.isEmpty, await provider.executionPath(using: settings) != .unavailable {
            let systemPrompt = """
            You summarize sender context for a local desktop mail client.
            Return only JSON with key summary.
            Ground everything in the provided workspace references.
            """
            let prompt = """
            Sender: \(sender.displayName)
            Email: \(sender.email)
            Thread subject: \(thread.subject)

            Workspace references:
            \(references.map { "\($0.path): \($0.excerpt)" }.joined(separator: "\n\n"))
            """
            if let response = try? await provider.generate(
                systemPrompt: systemPrompt,
                userPrompt: prompt,
                workspacePath: workspacePath,
                settings: settings,
                maxTokens: 900
            ) {
                let payload = try decodeJSON(response, as: ContextPayload.self)
                summary = payload.summary
            }
        }

        return MailSenderContext(
            threadID: thread.id,
            senderName: sender.name ?? sender.email,
            senderEmail: sender.email,
            summary: summary,
            references: references,
            generatedAt: Date()
        )
    }

    private func upsert(_ record: MailThreadIntelligenceRecord, into mailService: MailService) {
        records[record.threadID] = record
        mailService.applyIntelligenceRecord(record)
        persistAccountStateIfPossible()
    }

    private func persistAccountStateIfPossible() {
        guard let activeAccountEmail, !activeAccountEmail.isEmpty else { return }
        let snapshot = MailIntelligenceAccountSnapshot(threadRecords: records, savedAt: Date())
        accountStore.save(snapshot, accountEmail: activeAccountEmail)
        lastSavedAt = snapshot.savedAt
    }

    private func persistWorkspaceStateIfPossible() {
        guard let activeWorkspacePath else { return }
        let snapshot = MailWorkspaceIntelligenceSnapshot(
            priorityOverrides: priorityOverrides,
            memories: memories,
            agentSessions: Array(agentSessions.values).sorted { $0.updatedAt > $1.updatedAt }
        )
        workspaceStore.save(snapshot, workspacePath: activeWorkspacePath)
    }

    private func appliedPriorityOverride(for thread: MailThreadDetail) -> MailPriority? {
        let senderEmail = thread.messages.last?.from?.email.lowercased()
        let senderDomain = senderEmail?.split(separator: "@").last.map(String.init)
        let subject = thread.subject.lowercased()

        for override in priorityOverrides {
            let emailMatches = override.senderEmail?.lowercased() == senderEmail
            let domainMatches = override.senderDomain?.lowercased() == senderDomain
            let subjectMatches: Bool
            if let subjectContains = override.subjectContains?.lowercased(), !subjectContains.isEmpty {
                subjectMatches = subject.contains(subjectContains)
            } else {
                subjectMatches = true
            }

            if (emailMatches || domainMatches) && subjectMatches {
                return override.priority
            }
        }

        return nil
    }

    private func memoryPrompt(for thread: MailThreadDetail) -> String {
        let senderEmail = thread.messages.last?.from?.email.lowercased()
        let senderDomain = senderEmail?.split(separator: "@").last.map(String.init)
        let relevantMemories = memories.filter { memory in
            memory.senderEmail?.lowercased() == senderEmail ||
                memory.senderDomain?.lowercased() == senderDomain ||
                memory.kind == .writingStyle
        }
        if relevantMemories.isEmpty {
            return "No stored mail memories."
        }
        return relevantMemories.prefix(6).map { "[\($0.kind.rawValue)] \($0.title): \($0.detail)" }.joined(separator: "\n")
    }

    private func defaultProposals(for thread: MailThreadDetail) -> [MailAgentActionProposal] {
        [
            MailAgentActionProposal(kind: .draftReply, title: "Draft a reply", detail: "Prepare a suggested reply for review."),
            MailAgentActionProposal(kind: .createTask, title: "Create a task", detail: "Turn this thread into a Bugbook task."),
            MailAgentActionProposal(kind: .createNote, title: "Create a note", detail: "Capture this thread as a workspace note."),
            MailAgentActionProposal(kind: .createCalendarEvent, title: "Create a calendar event", detail: "Schedule follow-up work in Google Calendar."),
            MailAgentActionProposal(kind: .summarizeToNote, title: "Summarize to note", detail: "Save a concise thread summary locally."),
            MailAgentActionProposal(kind: .gatherContext, title: "Gather context", detail: "Refresh sender and workspace context."),
        ]
    }

    private func createNote(from thread: MailThreadDetail, workspacePath: String, titlePrefix: String) throws -> String {
        let name = "\(titlePrefix) \(thread.subject)"
        let path = try fileSystem.createNewFile(in: workspacePath, name: sanitizedFileTitle(name))
        let content = """
        # \(thread.subject)

        ## Participants
        \(thread.participants.joined(separator: ", "))

        ## Summary
        \(thread.snippet)

        ## Thread
        \(threadTranscript(for: thread))
        """
        try fileSystem.saveFile(at: path, content: content)
        return path
    }

    private func createSummaryNote(from thread: MailThreadDetail, settings: AppSettings, workspacePath: String, aiService: AiService) async throws -> String {
        let provider = AiServiceMailModelProvider(aiService: aiService)
        var summary = thread.snippet
        if await provider.executionPath(using: settings) != .unavailable {
            let systemPrompt = """
            Summarize an email thread into markdown.
            Return only markdown with sections:
            ## Summary
            ## Action Items
            """
            let prompt = threadTranscript(for: thread)
            if let response = try? await provider.generate(
                systemPrompt: systemPrompt,
                userPrompt: prompt,
                workspacePath: workspacePath,
                settings: settings,
                maxTokens: 900
            ) {
                summary = response
            }
        }

        let path = try fileSystem.createNewFile(in: workspacePath, name: sanitizedFileTitle("Mail Summary \(thread.subject)"))
        let content = """
        # \(thread.subject)

        \(summary)
        """
        try fileSystem.saveFile(at: path, content: content)
        return path
    }

    private func calendarDraft(for thread: MailThreadDetail) -> CalendarEventDraft {
        let startDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let endDate = startDate.addingTimeInterval(3600)
        let summary = records[thread.id]?.analysis?.suggestedAction ?? thread.snippet
        return CalendarEventDraft(
            title: thread.subject,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            notes: summary,
            calendarId: "primary"
        )
    }

    private func taskDetail(for thread: MailThreadDetail) -> String {
        var lines = [
            "Thread: \(thread.subject)",
            "Participants: \(thread.participants.joined(separator: ", "))",
            "Snippet: \(thread.snippet)",
        ]
        if let action = records[thread.id]?.analysis?.suggestedAction {
            lines.append("Suggested action: \(action)")
        }
        return lines.joined(separator: "\n")
    }

    private func threadTranscript(for thread: MailThreadDetail) -> String {
        thread.messages.suffix(6).map { message in
            let sender = message.from?.displayName ?? "Unknown"
            let body = message.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            From: \(sender)
            Date: \(message.date?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
            Subject: \(message.subject)
            Body:
            \(body.isEmpty ? message.snippet : body)
            """
        }.joined(separator: "\n\n---\n\n")
    }

    private func threadSignature(thread: MailThreadSummary) -> String? {
        if let historyId = thread.historyId, !historyId.isEmpty {
            return historyId
        }
        guard let date = thread.date else { return nil }
        return "\(thread.messageCount)|\(date.timeIntervalSince1970)"
    }

    private func workspaceMatches(for thread: MailThreadDetail, workspacePath: String?) -> [MailSenderContextReference] {
        guard let workspacePath else { return [] }
        let senderTokens = candidateTokens(for: thread)
        guard !senderTokens.isEmpty else { return [] }

        var matches: [MailSenderContextReference] = []
        let enumerator = FileManager.default.enumerator(atPath: workspacePath)
        while let item = enumerator?.nextObject() as? String {
            guard item.hasSuffix(".md") else { continue }
            let fullPath = (workspacePath as NSString).appendingPathComponent(item)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
            let lowercased = content.lowercased()
            guard senderTokens.contains(where: { lowercased.contains($0) }) else { continue }
            let excerpt = content
                .components(separatedBy: .newlines)
                .first(where: { line in senderTokens.contains { line.lowercased().contains($0) } })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? String(content.prefix(140))
            matches.append(MailSenderContextReference(path: fullPath, excerpt: excerpt))
            if matches.count >= 5 { break }
        }
        return matches
    }

    private func candidateTokens(for thread: MailThreadDetail) -> [String] {
        guard let sender = thread.messages.last?.from ?? thread.messages.first?.from else { return [] }
        var tokens = [sender.email.lowercased()]
        if let name = sender.name?.lowercased() {
            tokens.append(name)
            tokens.append(contentsOf: name.split(separator: " ").map(String.init).filter { $0.count > 2 })
        }
        return Array(Set(tokens))
    }

    private func subjectHint(for subject: String) -> String? {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").prefix(3).joined(separator: " ")
    }

    private func sanitizedFileTitle(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "[/:]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Mail Note" : sanitized
    }

    private func decodeJSON<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            throw MailIntelligenceError.noModelProvider
        }
        let jsonString = String(cleaned[start...end])
        let data = Data(jsonString.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

private struct AnalysisPayload: Decodable {
    var priority: MailPriority
    var reason: String
    var suggestedAction: String
    var flags: [MailThreadFlag]
    var shouldGenerateDraft: Bool
    var prefersReplyAll: Bool
}

private struct DraftPayload: Decodable {
    var subject: String
    var body: String
    var rationale: String
}

private struct DraftRefinementPayload: Decodable {
    var body: String
    var rationale: String
}

private struct ContextPayload: Decodable {
    var summary: String
}
