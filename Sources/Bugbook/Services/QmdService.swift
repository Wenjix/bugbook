import Foundation

enum QmdStatus: Equatable {
    case unknown
    case notInstalled
    case installing
    case installed(version: String, path: String)
    case error(String)

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

enum QmdSearchMode: String, Codable, CaseIterable {
    case bm25 = "bm25"
    case semantic = "semantic"
    case hybrid = "hybrid"

    var label: String {
        switch self {
        case .bm25: return "BM25"
        case .semantic: return "Semantic"
        case .hybrid: return "Hybrid"
        }
    }

    var detail: String {
        switch self {
        case .bm25: return "Fast keyword search (no models needed)."
        case .semantic: return "Vector similarity search. Downloads ~300 MB model on first use."
        case .hybrid: return "BM25 + semantic + reranking via qmd query. Best quality, runs locally."
        }
    }

    /// The qmd CLI subcommand for this search mode.
    var cliCommand: String {
        switch self {
        case .bm25: return "search"
        case .semantic: return "vsearch"
        case .hybrid: return "query"
        }
    }
}

enum QmdError: Error, LocalizedError {
    case commandFailed(String)
    var errorDescription: String? {
        if case .commandFailed(let msg) = self { return msg.isEmpty ? "Command failed" : msg }
        return nil
    }
}

/// Parsed output from `qmd status`.
struct QmdIndexStatus: Equatable {
    var totalFiles: Int = 0
    var totalVectors: Int = 0
    var collections: Int = 0
    var indexSize: String = ""
}

@MainActor
@Observable
final class QmdService {
    var status: QmdStatus = .unknown
    var collectionReady: Bool = false
    var indexStatus: QmdIndexStatus?

    // MARK: - Public

    func detect() async {
        status = .unknown
        if let path = try? await runShell("which qmd"), !path.isEmpty {
            let raw = try? await runShell("\"\(path)\" --version")
            let version = raw?.components(separatedBy: "\n").first ?? "unknown"
            status = .installed(version: version, path: path)
        } else {
            status = .notInstalled
        }
    }

    func install() async {
        guard case .notInstalled = status else { return }
        status = .installing
        do {
            let hasBun = (try? await runShell("which bun")) != nil
            let cmd = hasBun
                ? "bun install -g @tobilu/qmd"
                : "npm install -g @tobilu/qmd"
            try await runShell(cmd)
            await detect()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func ensureCollection(workspace: String) async {
        guard case .installed(_, let path) = status else { return }
        // v2: collection name is derived from the directory's last path component
        _ = try? await runBinary(path, args: ["collection", "add", workspace])
        _ = try? await runBinary(path, args: ["update"])
        collectionReady = true
    }

    /// Fetch index health from `qmd status` for display in settings.
    func fetchIndexStatus() async {
        guard case .installed(_, let path) = status else { return }
        guard let output = try? await runShellOutput(path, args: ["status"]) else { return }
        var parsed = QmdIndexStatus()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Size:") {
                parsed.indexSize = trimmed.replacingOccurrences(of: "Size:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Total:") {
                // "Total:    123 files indexed"
                let digits = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .first(where: { !$0.isEmpty })
                parsed.totalFiles = digits.flatMap { Int($0) } ?? 0
            } else if trimmed.hasPrefix("Vectors:") {
                let digits = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .first(where: { !$0.isEmpty })
                parsed.totalVectors = digits.flatMap { Int($0) } ?? 0
            } else if trimmed.hasPrefix("Collections (") {
                let digits = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .first(where: { !$0.isEmpty })
                parsed.collections = digits.flatMap { Int($0) } ?? 0
            }
        }
        indexStatus = parsed
    }

    /// Fire-and-forget: registers the workspace as a qmd collection if qmd is on PATH.
    /// Safe to call at startup -- returns immediately if qmd is not found.
    nonisolated static func registerCollectionInBackground(workspace: String) {
        Task.detached(priority: .background) {
            guard let path = Self.findBinaryPath() else { return }
            func run(_ args: [String]) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }
            // v2: no --name flag, collection name derived from directory
            run(["collection", "add", workspace])
            run(["update"])
        }
    }

    // MARK: - Path resolution (nonisolated so Task.detached can call them)

    nonisolated static func findBinaryPath() -> String? {
        // Login shell PATH lookup -- respects nvm, bun, npm global configs
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which qmd"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        if (try? task.run()) != nil {
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let p = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !p.isEmpty { return p }
            }
        }
        // Fallback: check common install dirs without a login shell
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        for p in [
            "\(home)/.bun/bin/qmd",
            "\(home)/.npm-global/bin/qmd",
            "\(home)/.local/bin/qmd",
            "/usr/local/bin/qmd",
            "/opt/homebrew/bin/qmd",
        ] where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return nil
    }

    // MARK: - Private

    @discardableResult
    private func runShell(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                task.arguments = ["-l", "-c", command]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if task.terminationStatus == 0 {
                        continuation.resume(returning: out)
                    } else {
                        continuation.resume(throwing: QmdError.commandFailed(out))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBinary(_ path: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .background).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Run the qmd binary and capture stdout.
    private func runShellOutput(_ path: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice
                do {
                    try task.run()
                    task.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
