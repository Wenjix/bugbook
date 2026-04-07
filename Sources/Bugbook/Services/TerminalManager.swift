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

    /// Pending color scheme to apply once ghostty is initialized.
    private var pendingColorScheme: ghostty_color_scheme_e?
    /// Pending theme to apply once ghostty is initialized.
    private var pendingTheme: (light: String, dark: String, scheme: TerminalColorSchemeMode)?

    /// Initialize the ghostty runtime. Must be called before creating sessions.
    func ensureInitialized() {
        guard ghosttyApp == nil else { return }

        // ghostty_init: pass empty args so libghostty doesn't touch the parent TTY
        let initResult = ghostty_init(0, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            log.error("ghostty_init failed with code \(initResult)")
            return
        }

        // Create config and load the user's Ghostty config (~/.config/ghostty/config)
        guard let cfg = ghostty_config_new() else {
            log.error("ghostty_config_new failed")
            return
        }
        ghostty_config_load_default_files(cfg)
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
            read_clipboard_cb: { userdata, clipboard, state in
                // Must access NSPasteboard on the main thread
                let work = {
                    guard let surface = _activeSurface else { return }
                    guard let text = NSPasteboard.general.string(forType: .string) else { return }
                    text.withCString { cStr in
                        ghostty_surface_complete_clipboard_request(surface, cStr, state, true)
                    }
                }
                if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
                return true
            },
            confirm_read_clipboard_cb: { userdata, content, state, requestType in
                let work = {
                    guard let surface = _activeSurface, let content else { return }
                    ghostty_surface_complete_clipboard_request(surface, content, state, true)
                }
                if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
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
                let work = {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(str, forType: .string)
                }
                if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
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

        // Apply any theme/color scheme that was set before initialization
        if let pending = pendingTheme {
            pendingTheme = nil
            pendingColorScheme = nil
            // applyTheme now has a valid ghosttyApp, so it will execute fully
            applyTheme(lightTheme: pending.light, darkTheme: pending.dark, colorScheme: pending.scheme)
        } else if let scheme = pendingColorScheme {
            ghostty_app_set_color_scheme(app, scheme)
            pendingColorScheme = nil
        }

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

    /// Set the color scheme on the ghostty app and all surfaces.
    /// If ghostty isn't initialized yet, stores the value for later.
    func applyColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let app = ghosttyApp else {
            // A plain color-scheme selection should override any deferred custom theme.
            pendingTheme = nil
            pendingColorScheme = scheme
            return
        }
        ghostty_app_set_color_scheme(app, scheme)
        // Also set directly on each surface for reliability
        for session in sessions.values {
            if let surface = session.surfaceView?.surface {
                ghostty_surface_set_color_scheme(surface, scheme)
            }
        }
    }

    /// Rebuild the ghostty config with a specific theme and apply it.
    /// Loads user defaults first, then overlays the chosen theme file.
    func applyTheme(lightTheme: String, darkTheme: String, colorScheme: TerminalColorSchemeMode) {
        guard let app = ghosttyApp else {
            pendingTheme = (lightTheme, darkTheme, colorScheme)
            return
        }

        let isDark: Bool
        switch colorScheme {
        case .light: isDark = false
        case .dark: isDark = true
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let themeName = isDark ? darkTheme : lightTheme

        guard let cfg = ghostty_config_new() else { return }

        // Load user config (preserves font, keybinds, etc.)
        ghostty_config_load_default_files(cfg)

        // Overlay the chosen theme file on top
        if !themeName.isEmpty {
            let themePath = Self.themePath(for: themeName)
            if FileManager.default.fileExists(atPath: themePath) {
                themePath.withCString { cStr in
                    ghostty_config_load_file(cfg, cStr)
                }
            }
        }

        ghostty_config_finalize(cfg)
        ghostty_app_update_config(app, cfg)

        // Push config update to each surface directly (our action_cb
        // doesn't handle CONFIG_CHANGE, so surfaces won't auto-update)
        let scheme: ghostty_color_scheme_e = isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        for session in sessions.values {
            if let surface = session.surfaceView?.surface {
                ghostty_surface_update_config(surface, cfg)
                ghostty_surface_set_color_scheme(surface, scheme)
            }
        }

        // Store new config, free old
        if let old = ghosttyConfig {
            ghostty_config_free(old)
        }
        ghosttyConfig = cfg
    }

    // MARK: - Theme Discovery

    static let ghosttyThemesDir = "/Applications/Ghostty.app/Contents/Resources/ghostty/themes"

    static func themePath(for name: String) -> String {
        "\(ghosttyThemesDir)/\(name)"
    }

    /// Returns sorted list of available Ghostty theme names.
    static func availableThemes() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: ghosttyThemesDir) else { return [] }
        return entries.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Parsed colors from a Ghostty theme file.
    struct ThemeColors {
        let background: String
        let foreground: String
        let cursorColor: String?
        /// ANSI palette: index 0-15. May be sparse.
        let palette: [Int: String]

        /// Palette color 1 (red), 2 (green), 3 (yellow), 4 (blue), 5 (magenta), 6 (cyan)
        func ansi(_ index: Int) -> String? { palette[index] }
    }

    /// Parse colors from a Ghostty theme file.
    static func themeColors(for name: String) -> ThemeColors? {
        let path = themePath(for: name)
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else { return nil }
        var bg: String?
        var fg: String?
        var cursor: String?
        var palette: [Int: String] = [:]
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("background") && !trimmed.hasPrefix("background-") {
                bg = trimmed.split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("foreground") && !trimmed.hasPrefix("foreground-") {
                fg = trimmed.split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("cursor-color") {
                cursor = trimmed.split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("palette") {
                // "palette = 2=#a9dc76"
                if let value = trimmed.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) {
                    let parts = value.split(separator: "=", maxSplits: 1)
                    if parts.count == 2, let idx = Int(parts[0]) {
                        palette[idx] = String(parts[1])
                    }
                }
            }
        }
        guard let bg, let fg else { return nil }
        return ThemeColors(background: bg, foreground: fg, cursorColor: cursor, palette: palette)
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
