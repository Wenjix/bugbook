import ArgumentParser
import Darwin
import Foundation

enum BugbookBinaryInstallMethod: String {
    case symlink
    case copy
}

func installBugbookBinary(
    sourcePath: String,
    destinationDirectory: String,
    installedName: String,
    method: BugbookBinaryInstallMethod,
    force: Bool
) throws -> [String: Any] {
    let fm = FileManager.default
    let source = absolutePath(for: (sourcePath as NSString).expandingTildeInPath)
    guard fm.fileExists(atPath: source) else {
        throw CLIError.fileNotFound(source)
    }

    let directory = normalizePath((destinationDirectory as NSString).expandingTildeInPath)
    try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let destination = normalizePath((directory as NSString).appendingPathComponent(installedName))
    let alreadyExists = pathExistsIncludingBrokenSymlink(destination)
    var updated = false

    if alreadyExists {
        if method == .symlink,
           let existingTarget = try? fm.destinationOfSymbolicLink(atPath: destination),
           normalizePath(existingTarget) == source {
            return installResult(
                source: source,
                destination: destination,
                method: method,
                updated: false
            )
        }

        guard force else {
            throw CLIError.invalidInput("Destination already exists: \(destination). Re-run with --force to replace it.")
        }
        try fm.removeItem(atPath: destination)
        updated = true
    }

    switch method {
    case .symlink:
        try fm.createSymbolicLink(atPath: destination, withDestinationPath: source)
    case .copy:
        try fm.copyItem(atPath: source, toPath: destination)
    }

    return installResult(
        source: source,
        destination: destination,
        method: method,
        updated: updated || !alreadyExists
    )
}

private func absolutePath(for path: String) -> String {
    if path.hasPrefix("/") {
        return normalizePath(path)
    }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return normalizePath(URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL.path)
}

private func pathExistsIncludingBrokenSymlink(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
}

private func installResult(
    source: String,
    destination: String,
    method: BugbookBinaryInstallMethod,
    updated: Bool
) -> [String: Any] {
    let destinationDirectory = (destination as NSString).deletingLastPathComponent
    let pathEntries = Set((ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init))

    var json: [String: Any] = [
        "installed": true,
        "updated": updated,
        "source": source,
        "destination": destination,
        "method": method.rawValue,
        "command_name": (destination as NSString).lastPathComponent,
    ]

    if !pathEntries.contains(destinationDirectory) {
        json["path_hint"] = "Add \(destinationDirectory) to PATH"
        json["shell_snippet"] = "export PATH=\"\(destinationDirectory):$PATH\""
    }

    return json
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the current BugbookCLI binary as `bugbook`"
    )

    @Option(name: .long, help: "Directory to place the installed command")
    var directory: String = "~/.local/bin"

    @Option(name: .long, help: "Installed command name")
    var name: String = "bugbook"

    @Flag(name: .long, help: "Copy the executable instead of creating a symlink")
    var copy: Bool = false

    @Flag(name: .long, help: "Replace an existing destination if needed")
    var force: Bool = false

    func run() throws {
        let executablePath = absolutePath(for: (CommandLine.arguments[0] as NSString).expandingTildeInPath)
        let output = try installBugbookBinary(
            sourcePath: executablePath,
            destinationDirectory: directory,
            installedName: name,
            method: copy ? .copy : .symlink,
            force: force
        )
        try outputJSON(output)
    }
}
