import Foundation
import Darwin

struct MeetingSummaryResult: Equatable {
    var title: String?
    var summary: [String]
    var actionItems: [String]
}

enum MeetingSummaryGenerationError: LocalizedError {
    case commandFailed(String)
    case emptyOutput
    case missingSummary
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "Summary generation failed." : message
        case .emptyOutput:
            return "Summary generation returned no text."
        case .missingSummary:
            return "Summary generation did not return a usable summary."
        case .timedOut(let timeout):
            return "Summary generation timed out after \(Int(timeout)) seconds."
        }
    }
}

final class MeetingSummaryService: @unchecked Sendable {
    private let commandTimeout: TimeInterval

    init(commandTimeout: TimeInterval = 120) {
        self.commandTimeout = max(1, commandTimeout)
    }

    func generateSummary(transcript: String, command: String) async throws -> MeetingSummaryResult {
        let prompt = """
        Summarize this meeting transcript. Output in this exact format with no preamble:

        TITLE: <a short, descriptive meeting title (max 8 words)>

        SUMMARY:
        - <key bullet 1>
        - <key bullet 2>
        - <key bullet 3>

        ACTION ITEMS:
        - <action item 1>
        - <action item 2>

        Rules:
        - Title is one line, no quotes, no trailing punctuation.
        - Summary bullets are short (one sentence each), capturing the main points discussed.
        - Action items are concrete tasks or follow-ups. Omit the section if there are none.
        - Do not include any text outside these three sections.

        Transcript:
        \(transcript)
        """

        let output = try await runSummaryCommand(command: command, prompt: prompt, timeout: commandTimeout)
        let parsed = parseSummaryOutput(output)
        guard parsed.sawSummarySection, !parsed.summary.isEmpty else {
            throw MeetingSummaryGenerationError.missingSummary
        }
        return MeetingSummaryResult(
            title: parsed.title,
            summary: parsed.summary,
            actionItems: parsed.actionItems
        )
    }

    private func runSummaryCommand(command: String, prompt: String, timeout: TimeInterval) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]

            let promptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("bugbook-summary-prompt-\(UUID().uuidString).txt")
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            let inputHandle = try FileHandle(forReadingFrom: promptURL)
            defer {
                try? inputHandle.close()
                try? FileManager.default.removeItem(at: promptURL)
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputHandle
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            let outputTask = Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .utility) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }

            guard !process.isRunning else {
                Self.terminateProcessTree(rootPID: process.processIdentifier, signal: SIGTERM)
                let exitedAfterTerminate = try await Self.waitForProcessExit(process, timeout: 2)
                if !exitedAfterTerminate {
                    Self.terminateProcessTree(rootPID: process.processIdentifier, signal: SIGKILL)
                    _ = try await Self.waitForProcessExit(process, timeout: 2)
                }
                _ = await outputTask.value
                _ = await errorTask.value
                throw MeetingSummaryGenerationError.timedOut(timeout)
            }

            let data = await outputTask.value
            let errorData = await errorTask.value
            if process.terminationStatus != 0 {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw MeetingSummaryGenerationError.commandFailed(message)
            }

            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                throw MeetingSummaryGenerationError.emptyOutput
            }
            return output
        }.value
    }

    private static func waitForProcessExit(_ process: Process, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning else { return false }
        return true
    }

    private static func terminateProcessTree(rootPID: Int32, signal: Int32) {
        for childPID in childProcessIDs(of: rootPID) {
            terminateProcessTree(rootPID: childPID, signal: signal)
        }
        Darwin.kill(rootPID, signal)
    }

    private static func childProcessIDs(of pid: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func parseSummaryOutput(
        _ output: String
    ) -> (title: String?, summary: [String], actionItems: [String], sawSummarySection: Bool) {
        var title: String?
        var summary: [String] = []
        var actionItems: [String] = []
        var inSummary = false
        var inActions = false
        var sawSummarySection = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TITLE:") {
                let value = String(trimmed.dropFirst(6))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !value.isEmpty { title = value }
                inSummary = false
                inActions = false
                continue
            }
            if trimmed.hasPrefix("SUMMARY:") {
                inSummary = true
                inActions = false
                sawSummarySection = true
                continue
            }
            if trimmed.hasPrefix("ACTION ITEMS:") {
                inSummary = false
                inActions = true
                continue
            }
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                if inSummary {
                    summary.append(item)
                } else if inActions {
                    actionItems.append(item)
                }
            }
        }

        return (title, summary, actionItems, sawSummarySection)
    }
}
