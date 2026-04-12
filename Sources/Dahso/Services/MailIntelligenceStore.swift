import Foundation

struct MailIntelligenceAccountSnapshot: Codable, Equatable {
    var threadRecords: [String: MailThreadIntelligenceRecord]
    var savedAt: Date
}

struct MailWorkspaceIntelligenceSnapshot: Codable, Equatable {
    var priorityOverrides: [MailPriorityOverride]
    var memories: [MailMemory]
    var agentSessions: [MailAgentSession]
}

struct MailIntelligenceStore {
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

    func load(accountEmail: String) -> MailIntelligenceAccountSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: accountEmail)) else { return nil }
        return try? decoder.decode(MailIntelligenceAccountSnapshot.self, from: data)
    }

    func save(_ snapshot: MailIntelligenceAccountSnapshot, accountEmail: String) {
        do {
            try ensureBaseDirectoryExists()
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL(for: accountEmail), options: .atomic)
        } catch {
            Log.mail.error("Failed to save mail intelligence cache: \(error.localizedDescription)")
        }
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for accountEmail: String) -> URL {
        let sanitized = accountEmail
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let filename = sanitized.isEmpty ? "mail-intelligence" : sanitized
        return baseDirectory.appendingPathComponent("\(filename).json")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("MailIntelligence", isDirectory: true)
    }
}

struct MailAgentSessionStore {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(workspacePath: String) -> MailWorkspaceIntelligenceSnapshot {
        let fileURL = workspaceFileURL(workspacePath: workspacePath)
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(MailWorkspaceIntelligenceSnapshot.self, from: data) else {
            return MailWorkspaceIntelligenceSnapshot(priorityOverrides: [], memories: [], agentSessions: [])
        }
        return snapshot
    }

    func save(_ snapshot: MailWorkspaceIntelligenceSnapshot, workspacePath: String) {
        do {
            let directory = workspaceDirectory(workspacePath: workspacePath)
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(snapshot)
            try data.write(to: workspaceFileURL(workspacePath: workspacePath), options: .atomic)
        } catch {
            Log.mail.error("Failed to save workspace mail intelligence: \(error.localizedDescription)")
        }
    }

    func workspaceDirectory(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath, isDirectory: true)
            .appendingPathComponent(".dahso", isDirectory: true)
            .appendingPathComponent("mail", isDirectory: true)
    }

    private func workspaceFileURL(workspacePath: String) -> URL {
        workspaceDirectory(workspacePath: workspacePath)
            .appendingPathComponent("mail-intelligence.json")
    }
}
