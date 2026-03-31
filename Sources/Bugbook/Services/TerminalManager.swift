import Foundation
import GhosttyKit
import AppKit
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "TerminalManager")

/// Manages all terminal sessions and the shared ghostty_app_t singleton.
/// The ghostty app must be initialized once and shared across all surfaces.
@MainActor
@Observable
final class TerminalManager {
    private(set) var sessions: [UUID: TerminalSession] = [:]

    /// The global ghostty app instance. Initialized on first use.
    private var ghosttyApp: ghostty_app_t?
    private var ghosttyConfig: ghostty_config_t?

    /// Initialize the ghostty runtime. Must be called before creating sessions.
    func ensureInitialized() {
        guard ghosttyApp == nil else { return }

        // Create config
        guard let cfg = ghostty_config_new() else {
            log.error("ghostty_config_new failed")
            return
        }
        ghostty_config_finalize(cfg)
        self.ghosttyConfig = cfg

        // Create runtime config with required callbacks.
        // We use Unmanaged to pass `self` as the userdata pointer.
        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { _ in
                // Wakeup: the terminal wants us to call ghostty_app_tick.
                // In a full integration we'd schedule this on the run loop.
                // For now this is a no-op since we tick on a display link.
            },
            action_cb: { _, _, _ in
                // Action callback: ghostty wants us to perform an app-level action
                // (new tab, new window, etc.). We don't support those yet.
                return false
            },
            read_clipboard_cb: { _, _, _ in
                // Read clipboard: ghostty wants to read the clipboard.
                // Return false to indicate we don't support this yet.
                return false
            },
            confirm_read_clipboard_cb: { _, _, _, _ in
                // Confirm clipboard read: no-op for now.
            },
            write_clipboard_cb: { userdata, loc, content, len, confirm in
                // Write to system clipboard
                guard let content = content else { return }
                let count = Int(len)
                guard count > 0 else { return }
                // The content array has `len` items; use the first one's data
                let firstContent = content.pointee
                guard let data = firstContent.data else { return }
                let str = String(cString: data)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(str, forType: .string)
            },
            close_surface_cb: { userdata, processAlive in
                // Surface wants to close. We'll handle this through our session management.
                // In a full integration, we'd find the session by surface userdata and close it.
            }
        )

        guard let app = ghostty_app_new(&runtime, cfg) else {
            log.error("ghostty_app_new failed")
            ghostty_config_free(cfg)
            self.ghosttyConfig = nil
            return
        }
        self.ghosttyApp = app
        log.info("Ghostty runtime initialized")

        // Start a display link / timer to tick the app periodically
        startTickTimer()
    }

    /// Create and start a new terminal session.
    @discardableResult
    func createSession(
        id: UUID = UUID(),
        workingDirectory: String? = nil
    ) -> TerminalSession {
        ensureInitialized()

        let dir = workingDirectory
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "/"
        let session = TerminalSession(id: id, workingDirectory: dir)

        if let app = ghosttyApp {
            session.start(app: app)
        } else {
            log.error("Cannot start session: ghostty app not initialized")
        }

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

    /// Shut down all sessions and free the ghostty app.
    func shutdown() {
        tickTimer?.invalidate()
        tickTimer = nil

        for session in sessions.values {
            session.terminate()
        }
        sessions.removeAll()

        if let app = ghosttyApp {
            ghostty_app_free(app)
            ghosttyApp = nil
        }
        // Config is freed separately since the app doesn't own it
        if let cfg = ghosttyConfig {
            ghostty_config_free(cfg)
            ghosttyConfig = nil
        }
    }

    // MARK: - Tick Timer

    private var tickTimer: Timer?

    /// ghostty_app_tick must be called periodically to drive rendering and I/O.
    private func startTickTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let app = self.ghosttyApp else { return }
                ghostty_app_tick(app)
            }
        }
    }
}
