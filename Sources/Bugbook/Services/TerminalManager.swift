import Foundation
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "TerminalManager")

/// Manages all terminal sessions across all workspaces.
@MainActor
@Observable
final class TerminalManager {
    private(set) var sessions: [UUID: TerminalSession] = [:]

    /// Create and start a new terminal session.
    @discardableResult
    func createSession(
        id: UUID = UUID(),
        workingDirectory: String? = nil
    ) -> TerminalSession {
        let dir = workingDirectory
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "/"
        let session = TerminalSession(id: id, workingDirectory: dir)
        session.start()
        sessions[session.id] = session
        log.info("Created terminal session \(session.id) in \(dir)")
        return session
    }

    /// Close and destroy a session.
    func closeSession(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.terminate()
        log.info("Closed terminal session \(id)")
    }

    /// Get a session by ID, or nil.
    func session(for id: UUID) -> TerminalSession? {
        sessions[id]
    }

    /// Shut down all sessions. Call on app quit.
    func shutdown() {
        for session in sessions.values {
            session.terminate()
        }
        sessions.removeAll()
    }
}
