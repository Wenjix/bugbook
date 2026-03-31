import Foundation
import SwiftTerm
import AppKit
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "Terminal")

/// Manages a single terminal instance: one shell process, one SwiftTerm view.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let workingDirectory: String
    let shellPath: String

    private(set) var title: String = "Terminal"
    private(set) var isAlive: Bool = false
    private(set) var terminalView: LocalProcessTerminalView?

    @ObservationIgnored private var delegateAdapter: TerminalDelegateAdapter?

    init(
        id: UUID = UUID(),
        workingDirectory: String,
        shellPath: String? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.shellPath = shellPath ?? (ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    }

    func start() {
        let view = LocalProcessTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 400))
        let sessionId = self.id
        let sessionDir = self.workingDirectory
        let adapter = TerminalDelegateAdapter { [weak self] title in
            Task { @MainActor in self?.title = title }
        } onProcessExit: { [weak self] exitCode in
            Task { @MainActor in
                self?.isAlive = false
                log.info("Terminal \(sessionId) exited with code \(exitCode ?? -1)")
            }
        }
        view.processDelegate = adapter
        self.delegateAdapter = adapter
        self.terminalView = view

        // Configure appearance
        let fontSize: CGFloat = 13
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.configureNativeColors()

        // Build environment
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env.append("HOME=\(home)")
        }

        view.startProcess(
            executable: shellPath,
            args: ["-l"],
            environment: env,
            execName: "-" + (shellPath as NSString).lastPathComponent,
            currentDirectory: workingDirectory
        )
        isAlive = true
        log.info("Started terminal \(sessionId) in \(sessionDir)")
    }

    func terminate() {
        terminalView?.terminate()
        terminalView = nil
        delegateAdapter = nil
        isAlive = false
    }
}

// MARK: - Delegate Adapter

/// Bridges SwiftTerm's delegate callbacks to closures for TerminalSession.
private class TerminalDelegateAdapter: LocalProcessTerminalViewDelegate {
    let onTitleChange: (String) -> Void
    let onProcessExit: (Int32?) -> Void

    init(onTitleChange: @escaping (String) -> Void, onProcessExit: @escaping (Int32?) -> Void) {
        self.onTitleChange = onTitleChange
        self.onProcessExit = onProcessExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessExit(exitCode)
    }
}
