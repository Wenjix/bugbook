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
@Observable
class AiService {
    var engineStatus = AiEngineStatus()
    var isRunning = false
    var error: String?
    @ObservationIgnored private var hasDetectedEngines = false

    // MARK: - Engine Detection

    func detectEngines() async {
        let claudePath = try? await runCommand("which claude")
        let claudeFound = claudePath?.isEmpty == false

        var claudeVer: String?
        if claudeFound {
            claudeVer = try? await runCommand("claude --version")
        }

        let codexPath = try? await runCommand("which codex")
        let codexFound = codexPath?.isEmpty == false

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

    func chatWithNotes(engine: PreferredAIEngine, workspacePath: String, question: String, apiKey: String = "") async throws -> String {
        if engine == .claudeAPI {
            guard !apiKey.isEmpty else { throw AiError.noEngineAvailable }
            isRunning = true
            error = nil
            defer { isRunning = false }
            do {
                return try await chatViaAPI(apiKey: apiKey, question: question)
            } catch {
                self.error = error.localizedDescription
                throw error
            }
        }

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
        case .auto, .claudeAPI:
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

    private func chatViaAPI(apiKey: String, question: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": question]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AiError.commandFailed("No response") }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AiError.commandFailed("API error \(http.statusCode): \(msg)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else {
            throw AiError.commandFailed("Unexpected API response format")
        }
        return text
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
        case .claudeAPI:
            return nil // handled separately in chatWithNotes
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
