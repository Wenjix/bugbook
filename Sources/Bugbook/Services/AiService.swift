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

    private static let systemInstruction = """
You are a writing assistant inside a note-taking app called Bugbook. The user will give you content and a request. Return ONLY the modified content as markdown. Do NOT duplicate sections. Do NOT add explanations or code fences.

Formatting rules:
- Headings: # H1, ## H2, ### H3
- Bullet lists: - item
- Numbered lists: 1. item
- To-do items: - [ ] task
- Block quotes: > text
- Code blocks: ```lang ... ```
- Dividers: ---
- Toggles (collapsible sections): Use this EXACT syntax:
  <!-- toggle -->
  Toggle Title
  Child content here (any markdown)
  <!-- /toggle -->
- For collapsed toggles: <!-- toggle collapsed --> instead of <!-- toggle -->

NEVER use HTML tags like <details>, <summary>, <strong>, etc. This app does NOT render HTML.
"""

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
                return try await callAPI(apiKey: apiKey, userPrompt: question)
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

    private func callAPI(apiKey: String, systemPrompt: String? = nil, userPrompt: String, maxTokens: Int = 1024) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": userPrompt]]
        ]
        if let systemPrompt {
            body["system"] = systemPrompt
        }
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

    // MARK: - Transcript Summarization

    struct TranscriptSummary {
        let summary: String
        let actionItems: String
    }

    func summarizeTranscript(_ transcript: String, apiKey: String) async throws -> TranscriptSummary {
        guard !apiKey.isEmpty else { throw AiError.noEngineAvailable }

        let systemPrompt = """
        You are summarizing a meeting transcript. Return ONLY markdown with two sections, no extra commentary:

        ## Summary
        <2-5 bullet points covering key discussion points, decisions made, and outcomes>

        ## Action Items
        <checklist of action items extracted from the conversation. Format each as: - [ ] Item (assigned to Person). If no person is obvious, omit the parenthetical.>

        If the transcript is too short or unclear to extract meaningful content, write a brief summary of what was discussed and leave action items empty.
        """

        let result = try await callAPI(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userPrompt: "Summarize this meeting transcript:\n\n\(transcript)",
            maxTokens: 2048
        )

        // Split the AI response into summary and action items sections
        let parts = result.components(separatedBy: "## Action Items")
        let summaryPart = parts[0]
            .replacingOccurrences(of: "## Summary", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let actionItemsPart = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : "- [ ] "

        return TranscriptSummary(
            summary: summaryPart.isEmpty ? "Meeting recorded." : summaryPart,
            actionItems: actionItemsPart.isEmpty ? "- [ ] " : actionItemsPart
        )
    }

    // MARK: - Content Generation

    func generateContent(engine: PreferredAIEngine, workspacePath: String, prompt: String, pageContext: String = "", apiKey: String = "") async throws -> String {
        var fullPrompt = Self.systemInstruction + "\n\n"
        if !pageContext.isEmpty {
            fullPrompt += "Current page context:\n\(pageContext)\n\n"
        }
        fullPrompt += "User request: \(prompt)"

        if engine == .claudeAPI {
            guard !apiKey.isEmpty else { throw AiError.noEngineAvailable }
            isRunning = true
            error = nil
            defer { isRunning = false }
            do {
                return try await callAPI(apiKey: apiKey, systemPrompt: Self.systemInstruction, userPrompt: pageContext.isEmpty ? prompt : "Current page context:\n\(pageContext)\n\nUser request: \(prompt)", maxTokens: 2048)
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
            command = "claude -p \(shellSingleQuoted(fullPrompt))"
        case .codex:
            command = "codex \(shellSingleQuoted(fullPrompt))"
        case .auto, .claudeAPI:
            throw AiError.noEngineAvailable
        }

        do {
            return try await runCommand(command, cwd: workspacePath)
        } catch let err as AiError {
            error = err.errorDescription
            throw err
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - CLI Execution

    /// Execute a bugbook CLI command and return the output.
    func executeBugbookCommand(_ command: String) async throws -> String {
        try await runCommand("bugbook \(command)")
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
