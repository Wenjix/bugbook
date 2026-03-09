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
        case .bm25: return "Fast keyword search. No models needed."
        case .semantic: return "Vector search. Finds meaning, not just exact words. Requires ~300 MB model on first use."
        case .hybrid: return "BM25 + semantic + re-ranking. Best quality. Keeps models loaded in background."
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

@MainActor
@Observable
final class QmdService {
    var status: QmdStatus = .unknown
    var collectionReady: Bool = false

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
        let name = collectionName(for: workspace)
        _ = try? await runBinary(path, args: ["collection", "add", workspace, "--name", name])
        _ = try? await runBinary(path, args: ["update"])
        collectionReady = true
    }

    /// Start the qmd HTTP daemon in the background if hybrid mode is selected and it isn't already running.
    /// Returns immediately — model loading takes ~30s and happens asynchronously.
    nonisolated static func prewarmDaemonIfNeeded(mode: QmdSearchMode) {
        guard mode == .hybrid else { return }
        Task.detached(priority: .background) {
            guard let path = Self.findBinaryPath() else { return }
            guard await !Self.isDaemonHealthy() else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["mcp", "--http", "--daemon"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            // Intentionally don't waitUntilExit — daemon runs in background
        }
    }

    nonisolated private static func isDaemonHealthy() async -> Bool {
        guard let url = URL(string: "http://localhost:8181/health") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 2)
        req.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: req))
            .flatMap { $0.1 as? HTTPURLResponse }
            .map { $0.statusCode == 200 } ?? false
    }

    /// Fire-and-forget: registers the workspace as a qmd collection if qmd is on PATH.
    /// Safe to call at startup — returns immediately if qmd is not found.
    nonisolated static func registerCollectionInBackground(workspace: String) {
        Task.detached(priority: .background) {
            guard let path = Self.findBinaryPath() else { return }
            let name = Self.collectionNameFor(workspace)
            func run(_ args: [String]) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: path)
                task.arguments = args
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }
            run(["collection", "add", workspace, "--name", name])
            run(["update"])
        }
    }

    // MARK: - Path resolution (nonisolated so Task.detached can call them)

    nonisolated static func findBinaryPath() -> String? {
        // Login shell PATH lookup — respects nvm, bun, npm global configs
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

    private func collectionName(for workspace: String) -> String {
        Self.collectionNameFor(workspace)
    }

    nonisolated private static func collectionNameFor(_ workspace: String) -> String {
        let name = URL(fileURLWithPath: workspace).lastPathComponent
        return name.isEmpty ? "bugbook" : name
    }

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
}
