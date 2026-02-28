import Foundation

enum AiError: LocalizedError {
    case noEngineAvailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noEngineAvailable:
            return "No AI engine found. Install Claude CLI or Codex CLI."
        case .commandFailed(let output):
            return output.isEmpty ? "Command failed with no output." : output
        }
    }
}

struct AiEngineStatus {
    var claudeAvailable: Bool = false
    var claudeVersion: String?
    var codexAvailable: Bool = false
    var codexVersion: String?
}

@MainActor
class AiService: ObservableObject {
    @Published var engineStatus = AiEngineStatus()
    @Published var isRunning = false
    @Published var error: String?
    private var hasDetectedEngines = false

    // MARK: - Engine Detection

    func detectEngines() async {
        let claudePath = try? await runCommand("which claude")
        let claudeFound = claudePath != nil && !claudePath!.isEmpty

        var claudeVer: String?
        if claudeFound {
            claudeVer = try? await runCommand("claude --version")
        }

        let codexPath = try? await runCommand("which codex")
        let codexFound = codexPath != nil && !codexPath!.isEmpty

        var codexVer: String?
        if codexFound {
            codexVer = try? await runCommand("codex --version")
        }

        engineStatus = AiEngineStatus(
            claudeAvailable: claudeFound,
            claudeVersion: claudeVer,
            codexAvailable: codexFound,
            codexVersion: codexVer
        )
        hasDetectedEngines = true
    }

    // MARK: - Chat

    func chatWithNotes(engine: PreferredAIEngine, workspacePath: String, question: String) async throws -> String {
        if !hasDetectedEngines {
            await detectEngines()
        }

        let resolvedEngine = resolveEngine(engine)

        guard let cli = resolvedEngine else {
            throw AiError.noEngineAvailable
        }

        isRunning = true
        error = nil
        defer { isRunning = false }

        let command: String
        switch cli {
        case .claude:
            command = "claude -p \(shellSingleQuoted("Given the notes in this workspace, answer:\n\(question)"))"
        case .codex:
            command = "codex \(shellSingleQuoted("Given the notes in this workspace, answer:\n\(question)"))"
        case .auto:
            // Should not reach here after resolveEngine
            throw AiError.noEngineAvailable
        }

        do {
            let result = try await runCommand(command, cwd: workspacePath)
            return result
        } catch let err as AiError {
            error = err.errorDescription
            throw err
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Pre-warming

    func prewarmSession() async {
        // Lightweight check to ensure the CLI is responsive
        if engineStatus.claudeAvailable {
            _ = try? await runCommand("claude --version")
        } else if engineStatus.codexAvailable {
            _ = try? await runCommand("codex --version")
        }
    }

    // MARK: - Helpers

    private func resolveEngine(_ preferred: PreferredAIEngine) -> PreferredAIEngine? {
        switch preferred {
        case .claude:
            return engineStatus.claudeAvailable ? .claude : nil
        case .codex:
            return engineStatus.codexAvailable ? .codex : nil
        case .auto:
            if engineStatus.claudeAvailable { return .claude }
            if engineStatus.codexAvailable { return .codex }
            return nil
        }
    }

    private func shellSingleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func runCommand(_ command: String, cwd: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]
                if let cwd = cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        continuation.resume(throwing: AiError.commandFailed(output))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
