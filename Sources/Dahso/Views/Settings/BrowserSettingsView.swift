import AppKit
import Foundation
import SwiftUI

struct BrowserSettingsView: View {
    @Bindable var appState: AppState
    @Bindable var browserManager: BrowserManager
    @State private var dataMessage: String?
    @State private var isClearingCookies = false
    @State private var extensionMessage: String?
    @State private var chromeWebStoreInput = ""
    @State private var isInstallingStoreExtension = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Search") {
                Picker("Search Engine", selection: $appState.settings.browserSearchEngine) {
                    ForEach(BrowserSearchEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable search suggestions", isOn: $appState.settings.browserSuggestionsEnabled)
                Toggle("Suggest Dahso pages", isOn: $appState.settings.browserSuggestsDahsoPages)
                    .disabled(!appState.settings.browserSuggestionsEnabled)

                HStack {
                    Text("Suggestion Count")
                        .font(.system(size: 13))
                    Spacer()
                    Stepper(value: $appState.settings.browserSuggestionLimit, in: 3...12) {
                        Text("\(appState.settings.browserSuggestionLimit)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .frame(width: 140)
                    .disabled(!appState.settings.browserSuggestionsEnabled)
                }

                HStack {
                    Text("Default Save Folder")
                        .font(.system(size: 13))
                    Spacer()
                    TextField("Web Clippings", text: $appState.settings.browserDefaultSaveFolder)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            SettingsSection("History & Privacy") {
                Toggle("Save browsing history", isOn: $appState.settings.browserHistoryEnabled)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("History")
                            .font(.system(size: 13, weight: .medium))
                        Text(historySummary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History") {
                        browserManager.clearHistory()
                        dataMessage = "Browsing history cleared."
                    }
                    .disabled(browserManager.browsingHistory.isEmpty)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cookies")
                            .font(.system(size: 13, weight: .medium))
                        Text("Clear stored site cookies for the embedded browser.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isClearingCookies ? "Clearing…" : "Clear Cookies") {
                        Task { await clearCookies() }
                    }
                    .disabled(isClearingCookies)
                }

                if let dataMessage, !dataMessage.isEmpty {
                    Text(dataMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if browserManager.browsingHistory.isEmpty {
                    Text("No browsing history yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(browserManager.browsingHistory.prefix(6))) { visit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text(visit.urlString)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }

            SettingsSection("Browser Chrome") {
                Toggle("Show back/forward buttons", isOn: $appState.settings.browserChrome.showsBackForwardButtons)
                Toggle("Show bookmarks bar", isOn: $appState.settings.browserChrome.showsBookmarksBar)
                Toggle("Auto-hide tab pills when only one tab exists", isOn: $appState.settings.browserChrome.autoHidesTabPills)
                Toggle("Show save button", isOn: $appState.settings.browserChrome.showsSaveButton)
                Toggle("Show status bar on link hover", isOn: $appState.settings.browserChrome.showsStatusBar)
            }

            SettingsSection("Browser Start Page") {
                Toggle("Show greeting", isOn: $appState.settings.browserChrome.showsNewTabGreeting)
                Toggle("Show quick launch", isOn: $appState.settings.browserChrome.showsNewTabQuickLaunch)
                Toggle("Show recent visits", isOn: $appState.settings.browserChrome.showsNewTabRecentVisits)
            }

            SettingsSection("Quick Launch") {
                ForEach($appState.settings.browserQuickLaunchItems) { $item in
                    HStack(spacing: 10) {
                        TextField("Title", text: $item.title)
                            .textFieldStyle(.roundedBorder)
                        TextField("URL", text: $item.url)
                            .textFieldStyle(.roundedBorder)
                        TextField("Icon", text: $item.icon)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Button {
                            removeQuickLaunch(item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Shortcut") {
                    appState.settings.browserQuickLaunchItems.append(
                        BrowserQuickLaunchItem(title: "New Shortcut", url: "https://", icon: "globe")
                    )
                }
            }

            SettingsSection("Extensions") {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unpacked Extensions")
                            .font(.system(size: 13, weight: .medium))
                        Text("Select an unpacked extension folder, or a Chrome extension folder that contains versioned subfolders. Changes apply the next time Dahso launches.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Extension…") {
                        addExtensions()
                    }
                }

                HStack(spacing: 10) {
                    TextField("Chrome Web Store URL or extension ID", text: $chromeWebStoreInput)
                        .textFieldStyle(.roundedBorder)

                    Button(isInstallingStoreExtension ? "Installing…" : "Install from Store") {
                        Task { await installChromeWebStoreExtension() }
                    }
                    .disabled(isInstallingStoreExtension || chromeWebStoreInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Store installs are imported into Dahso's local extension storage, then loaded on next launch.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let extensionMessage, !extensionMessage.isEmpty {
                    Text(extensionMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if appState.settings.browserExtensionPaths.isEmpty {
                    Text("No browser extensions configured.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.settings.browserExtensionPaths, id: \.self) { path in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(extensionDisplayName(for: path))
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text(path)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if !hasManifest(at: path) {
                                        Text("manifest.json not found. Remove or fix this path before restarting.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Spacer()

                                Button {
                                    removeExtension(path)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func removeQuickLaunch(_ id: UUID) {
        appState.settings.browserQuickLaunchItems.removeAll { $0.id == id }
    }

    private func installChromeWebStoreExtension() async {
        let rawInput = chromeWebStoreInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else { return }

        isInstallingStoreExtension = true
        defer { isInstallingStoreExtension = false }

        do {
            let installation = try await Task.detached(priority: .userInitiated) {
                try await BrowserExtensionStoreInstaller.install(from: rawInput)
            }.value

            appState.settings.browserExtensionPaths.removeAll { $0 == installation.path }
            appState.settings.browserExtensionPaths.append(installation.path)
            appState.settings.browserExtensionPaths.sort()
            chromeWebStoreInput = ""
            extensionMessage = "Installed \(installation.displayName). Restart Dahso to load it."
        } catch {
            extensionMessage = error.localizedDescription
        }
    }

    private func addExtensions() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.title = "Select Browser Extension Folders"
        panel.message = "Choose unpacked Chromium extension folders, or Chrome extension folders that contain versioned subfolders."

        guard panel.runModal() == .OK else { return }

        let resolvedPaths = panel.urls.compactMap { resolveExtensionDirectory(from: $0.path) }
        guard !resolvedPaths.isEmpty else {
            extensionMessage = "Choose an unpacked extension folder that contains a manifest.json file."
            return
        }

        let merged = Array(
            Set(appState.settings.browserExtensionPaths).union(resolvedPaths)
        ).sorted()

        appState.settings.browserExtensionPaths = merged
        extensionMessage = "Restart Dahso to load the selected extensions."
    }

    private func removeExtension(_ path: String) {
        appState.settings.browserExtensionPaths.removeAll { $0 == path }
        extensionMessage = "Restart Dahso to unload removed extensions."
    }

    private func extensionDisplayName(for path: String) -> String {
        guard let manifest = manifestDictionary(at: path),
              let name = manifest["name"] as? String,
              !name.isEmpty else {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        if let version = manifest["version"] as? String, !version.isEmpty {
            return "\(name) \(version)"
        }
        return name
    }

    private func resolveExtensionDirectory(from rawPath: String) -> String? {
        let standardizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        if hasManifest(at: standardizedPath) {
            return standardizedPath
        }

        guard let childNames = try? FileManager.default.contentsOfDirectory(atPath: standardizedPath) else {
            return nil
        }

        let candidates = childNames.compactMap { childName -> String? in
            let candidate = URL(fileURLWithPath: standardizedPath)
                .appendingPathComponent(childName, isDirectory: true)
                .standardizedFileURL.path
            return hasManifest(at: candidate) ? candidate : nil
        }

        guard !candidates.isEmpty else {
            return nil
        }

        return candidates.sorted { lhs, rhs in
            let lhsName = URL(fileURLWithPath: lhs).lastPathComponent
            let rhsName = URL(fileURLWithPath: rhs).lastPathComponent
            return lhsName.compare(rhsName, options: .numeric) == .orderedDescending
        }.first
    }

    private func hasManifest(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestPath(for: path))
    }

    private func manifestDictionary(at path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath(for: path))),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func manifestPath(for path: String) -> String {
        URL(fileURLWithPath: path)
            .appendingPathComponent("manifest.json", isDirectory: false)
            .path
    }

    private var historySummary: String {
        let count = browserManager.browsingHistory.count
        if count == 0 {
            return "Your browser history is empty."
        }
        return "\(count) saved visit\(count == 1 ? "" : "s")"
    }

    private func clearCookies() async {
        isClearingCookies = true
        defer { isClearingCookies = false }

        do {
            try await browserManager.clearCookies()
            dataMessage = "Cookies cleared."
        } catch {
            dataMessage = "Failed to clear cookies: \(error.localizedDescription)"
        }
    }
}

struct BrowserStoreInstalledExtension: Equatable, Sendable {
    let id: String
    let path: String
    let displayName: String
}

enum BrowserExtensionStoreInstaller {
    private static let storeIDPattern = #"[a-p]{32}"#

    static func extensionID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.range(of: "^\(storeIDPattern)$", options: .regularExpression) != nil {
            return trimmed
        }

        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return nil
        }

        guard host == "chrome.google.com" || host == "chromewebstore.google.com" else {
            return nil
        }

        let candidates = url.pathComponents.filter { component in
            component.range(of: "^\(storeIDPattern)$", options: .regularExpression) != nil
        }

        return candidates.last
    }

    static func install(from input: String) async throws -> BrowserStoreInstalledExtension {
        guard let extensionID = extensionID(from: input) else {
            throw BrowserExtensionStoreInstallerError.invalidStoreReference
        }

        let crxData = try await downloadCRX(for: extensionID)
        return try installCRX(crxData, extensionID: extensionID)
    }

    static func extractZIPPayload(from crxData: Data) throws -> Data {
        guard crxData.count >= 12 else {
            throw BrowserExtensionStoreInstallerError.invalidCRXPayload
        }

        let magic = String(decoding: crxData.prefix(4), as: UTF8.self)
        guard magic == "Cr24" else {
            throw BrowserExtensionStoreInstallerError.invalidCRXPayload
        }

        let version = readUInt32LE(from: crxData, offset: 4)
        let payloadOffset: Int

        switch version {
        case 2:
            guard crxData.count >= 16 else {
                throw BrowserExtensionStoreInstallerError.invalidCRXPayload
            }

            let publicKeyLength = Int(readUInt32LE(from: crxData, offset: 8))
            let signatureLength = Int(readUInt32LE(from: crxData, offset: 12))
            payloadOffset = 16 + publicKeyLength + signatureLength
        case 3:
            let headerLength = Int(readUInt32LE(from: crxData, offset: 8))
            payloadOffset = 12 + headerLength
        default:
            throw BrowserExtensionStoreInstallerError.unsupportedCRXVersion(Int(version))
        }

        guard payloadOffset < crxData.count else {
            throw BrowserExtensionStoreInstallerError.invalidCRXPayload
        }

        return crxData.subdata(in: payloadOffset..<crxData.count)
    }

    private static func downloadCRX(for extensionID: String) async throws -> Data {
        guard let url = chromeWebStoreDownloadURL(for: extensionID) else {
            throw BrowserExtensionStoreInstallerError.runtimeUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("application/x-chrome-extension,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrowserExtensionStoreInstallerError.invalidStoreResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BrowserExtensionStoreInstallerError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        guard data.starts(with: Data("Cr24".utf8)) else {
            throw BrowserExtensionStoreInstallerError.invalidCRXPayload
        }

        return data
    }

    private static func chromeWebStoreDownloadURL(for extensionID: String) -> URL? {
        guard let productVersion = ChromiumRuntimeMetadata.productVersion() else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "clients2.google.com"
        components.path = "/service/update2/crx"
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "os", value: "mac"),
            URLQueryItem(name: "arch", value: currentArchitecture),
            URLQueryItem(name: "nacl_arch", value: currentArchitecture),
            URLQueryItem(name: "prod", value: "chromiumcrx"),
            URLQueryItem(name: "prodchannel", value: ""),
            URLQueryItem(name: "prodversion", value: productVersion),
            URLQueryItem(name: "lang", value: Locale.preferredLanguages.first ?? "en-US"),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(extensionID)&installsource=ondemand&uc"),
        ]
        return components.url
    }

    private static func installCRX(_ crxData: Data, extensionID: String) throws -> BrowserStoreInstalledExtension {
        let zipPayload = try extractZIPPayload(from: crxData)
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archiveURL = tempRoot.appendingPathComponent("\(extensionID).zip", isDirectory: false)
        let extractionURL = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        let installURL = storeInstallRoot().appendingPathComponent(extensionID, isDirectory: true)

        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try zipPayload.write(to: archiveURL, options: .atomic)
        try unzipArchive(at: archiveURL, to: extractionURL)

        let extensionRoot = try resolveExtensionRoot(in: extractionURL)
        let manifest = try manifestDictionary(at: extensionRoot)
        let displayName = extensionDisplayName(from: manifest, fallback: extensionID)

        try fileManager.createDirectory(at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let replacementURL = tempRoot.appendingPathComponent("replacement", isDirectory: true)
        if fileManager.fileExists(atPath: replacementURL.path) {
            try fileManager.removeItem(at: replacementURL)
        }
        try fileManager.moveItem(at: extensionRoot, to: replacementURL)

        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }
        try fileManager.moveItem(at: replacementURL, to: installURL)

        return BrowserStoreInstalledExtension(id: extensionID, path: installURL.path, displayName: displayName)
    }

    private static func unzipArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BrowserExtensionStoreInstallerError.unzipFailed(errorOutput?.isEmpty == false ? errorOutput! : "Unable to unpack the extension archive.")
        }
    }

    private static func resolveExtensionRoot(in extractionURL: URL) throws -> URL {
        let manifestURL = extractionURL.appendingPathComponent("manifest.json", isDirectory: false)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            return extractionURL
        }

        let candidates = try FileManager.default.contentsOfDirectory(at: extractionURL, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json", isDirectory: false).path) }

        guard candidates.count == 1, let candidate = candidates.first else {
            throw BrowserExtensionStoreInstallerError.invalidExtensionBundle
        }

        return candidate
    }

    private static func manifestDictionary(at extensionRoot: URL) throws -> [String: Any] {
        let manifestURL = extensionRoot.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrowserExtensionStoreInstallerError.invalidExtensionBundle
        }
        return manifest
    }

    private static func extensionDisplayName(from manifest: [String: Any], fallback: String) -> String {
        let name = (manifest["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (manifest["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let name, !name.isEmpty, let version, !version.isEmpty {
            return "\(name) \(version)"
        }
        if let name, !name.isEmpty {
            return name
        }
        return fallback
    }

    private static func storeInstallRoot() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("Chromium", isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x64"
        #endif
    }

    private static func readUInt32LE(from data: Data, offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { rawBuffer in
            UInt32(littleEndian: rawBuffer.load(as: UInt32.self))
        }
    }
}

enum BrowserExtensionStoreInstallerError: LocalizedError, Sendable {
    case invalidStoreReference
    case runtimeUnavailable
    case invalidStoreResponse
    case downloadFailed(statusCode: Int)
    case invalidCRXPayload
    case unsupportedCRXVersion(Int)
    case unzipFailed(String)
    case invalidExtensionBundle

    var errorDescription: String? {
        switch self {
        case .invalidStoreReference:
            return "Enter a Chrome Web Store URL or a valid extension ID."
        case .runtimeUnavailable:
            return "Dahso could not determine the embedded Chromium version for this install."
        case .invalidStoreResponse:
            return "The Chrome Web Store response was invalid."
        case .downloadFailed(let statusCode):
            return "Chrome Web Store download failed with HTTP \(statusCode)."
        case .invalidCRXPayload:
            return "The downloaded extension package was not a valid CRX file."
        case .unsupportedCRXVersion(let version):
            return "The downloaded extension uses unsupported CRX version \(version)."
        case .unzipFailed(let message):
            return "Failed to unpack the extension: \(message)"
        case .invalidExtensionBundle:
            return "The downloaded extension did not contain a usable manifest.json."
        }
    }
}
