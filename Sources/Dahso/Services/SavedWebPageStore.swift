import Foundation

struct SavedWebPageStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    }

    func records(in workspacePath: String) -> [SavedWebPageRecord] {
        guard let data = try? Data(contentsOf: fileURL(for: workspacePath)),
              let records = try? decoder.decode([SavedWebPageRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.savedAt > $1.savedAt }
    }

    func record(forURL urlString: String, in workspacePath: String) -> SavedWebPageRecord? {
        records(in: workspacePath).first { $0.urlString == urlString }
    }

    func upsert(_ record: SavedWebPageRecord, in workspacePath: String) {
        var records = records(in: workspacePath)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else if let index = records.firstIndex(where: { $0.urlString == record.urlString }) {
            records[index] = record
        } else {
            records.append(record)
        }
        persist(records, workspacePath: workspacePath)
    }

    func remove(recordID: UUID, in workspacePath: String) {
        let filtered = records(in: workspacePath).filter { $0.id != recordID }
        persist(filtered, workspacePath: workspacePath)
    }

    func markStatus(_ status: SavedWebPageStatus, for recordID: UUID, in workspacePath: String) {
        var records = records(in: workspacePath)
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].status = status
        persist(records, workspacePath: workspacePath)
    }

    private func persist(_ records: [SavedWebPageRecord], workspacePath: String) {
        do {
            try ensureDirectoryExists()
            let data = try encoder.encode(records.sorted { $0.savedAt > $1.savedAt })
            try data.write(to: fileURL(for: workspacePath), options: .atomic)
        } catch {
            Log.app.error("Failed to persist saved web pages: \(error.localizedDescription)")
        }
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for workspacePath: String) -> URL {
        directoryURL.appendingPathComponent(Self.encodedWorkspacePath(workspacePath) + ".json")
    }

    private static func encodedWorkspacePath(_ workspacePath: String) -> String {
        Data(workspacePath.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("SavedWebPages", isDirectory: true)
    }
}
