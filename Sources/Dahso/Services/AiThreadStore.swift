import Foundation

struct AiThread: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "New Thread", messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Auto-generate title from the first user message, truncated.
    static func titleFromFirstMessage(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        if firstLine.count <= 50 { return firstLine }
        return String(firstLine.prefix(47)) + "..."
    }
}

@MainActor
@Observable class AiThreadStore {
    private(set) var threads: [AiThread] = []
    var activeThreadId: UUID?

    var activeThread: AiThread? {
        threads.first { $0.id == activeThreadId }
    }

    /// Threads sorted by most recent first.
    var sortedThreads: [AiThread] {
        threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    private let fileManager: FileManager
    private let storeDirectory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.storeDirectory = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        loadAll()
        // Restore most recent thread
        if activeThreadId == nil, let mostRecent = sortedThreads.first {
            activeThreadId = mostRecent.id
        }
    }

    // MARK: - Public API

    @discardableResult
    func createThread() -> AiThread {
        let thread = AiThread()
        threads.append(thread)
        activeThreadId = thread.id
        save(thread)
        return thread
    }

    func switchTo(_ threadId: UUID) {
        guard threads.contains(where: { $0.id == threadId }) else { return }
        activeThreadId = threadId
    }

    func appendMessage(_ message: ChatMessage, to threadId: UUID) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[idx].messages.append(message)
        threads[idx].updatedAt = Date()

        // Auto-title from first user message
        if threads[idx].title == "New Thread",
           message.role == .user {
            threads[idx].title = AiThread.titleFromFirstMessage(message.content)
        }

        save(threads[idx])
    }

    func toggleMessageReverted(_ messageId: UUID, in threadId: UUID) {
        guard let threadIdx = threads.firstIndex(where: { $0.id == threadId }),
              let msgIdx = threads[threadIdx].messages.firstIndex(where: { $0.id == messageId }) else { return }
        threads[threadIdx].messages[msgIdx].isReverted.toggle()
        save(threads[threadIdx])
    }

    func deleteThread(_ threadId: UUID) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let thread = threads.remove(at: idx)
        removeFile(for: thread.id)

        // If we deleted the active thread, switch to most recent or nil
        if activeThreadId == threadId {
            activeThreadId = sortedThreads.first?.id
        }
    }

    // MARK: - Persistence

    private func save(_ thread: AiThread) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(thread)
            try data.write(to: fileURL(for: thread.id), options: .atomic)
        } catch {
            Log.ai.error("Failed to save AI thread: \(error.localizedDescription)")
        }
    }

    private func loadAll() {
        guard fileManager.fileExists(atPath: storeDirectory.path) else { return }
        do {
            let files = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            threads = files.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(AiThread.self, from: data)
            }
        } catch {
            Log.ai.error("Failed to load AI threads: \(error.localizedDescription)")
        }
    }

    private func removeFile(for id: UUID) {
        try? fileManager.removeItem(at: fileURL(for: id))
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: storeDirectory.path) else { return }
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("AiThreads", isDirectory: true)
    }
}
