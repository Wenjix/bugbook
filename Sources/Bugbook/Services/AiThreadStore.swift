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
    /// Process-wide store: every window's AppState shares one in-memory thread
    /// list and one write queue. Created lazily on first chat use.
    static let shared = AiThreadStore()

    /// Live instances (weak) so app termination can flush pending writes of
    /// whatever stores actually exist without forcing any into existence.
    private static let liveStores = NSHashTable<AiThreadStore>.weakObjects()

    /// Flushes write-behind persistence of every live store. Owned by the app
    /// lifecycle (AppDelegate.applicationWillTerminate); a no-op when no store
    /// was ever created this session.
    static func flushAllPendingWrites() {
        for store in liveStores.allObjects {
            store.flushPendingWrites()
        }
    }

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
    /// Serial queue for write-behind persistence. Saves and deletes run here in
    /// order, off the main thread, so appending a chat message never blocks a
    /// frame on disk I/O.
    private let persistenceQueue = DispatchQueue(label: "com.bugbook.aithreadstore.persistence", qos: .utility)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Internal so tests can construct private instances with custom
    /// directories; the app uses `AiThreadStore.shared`.
    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.storeDirectory = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        loadAll()
        // Restore most recent thread
        if activeThreadId == nil, let mostRecent = sortedThreads.first {
            activeThreadId = mostRecent.id
        }
        Self.liveStores.add(self)
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

    /// Blocks until every queued save/delete has reached disk. Part of the
    /// interface contract: persistence is asynchronous; call this when the
    /// on-disk state must be observable (tests, shutdown).
    func flushPendingWrites() {
        persistenceQueue.sync {}
    }

    /// Pending coalesced save per thread — cancel-and-replace so a burst of
    /// appends collapses to one full-file write of the latest snapshot.
    private var pendingSaves: [UUID: DispatchWorkItem] = [:]

    private func save(_ thread: AiThread) {
        pendingSaves[thread.id]?.cancel()

        let url = fileURL(for: thread.id)
        let directory = storeDirectory
        let work = DispatchWorkItem {
            do {
                let fm = FileManager.default
                if !fm.fileExists(atPath: directory.path) {
                    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(thread)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.ai.error("Failed to save AI thread: \(error.localizedDescription)")
            }
        }
        pendingSaves[thread.id] = work
        persistenceQueue.async(execute: work)
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
        // A queued save for this thread is moot — the file is going away.
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil

        let url = fileURL(for: id)
        persistenceQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        storeDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Bugbook", isDirectory: true)
            .appendingPathComponent("AiThreads", isDirectory: true)
    }
}
