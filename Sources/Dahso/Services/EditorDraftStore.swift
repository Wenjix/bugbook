import Foundation
import CryptoKit

struct EditorDraftStore {
    enum DraftKey {
        case page(path: String)
        case rowBody(dbPath: String, rowId: String)

        var rawValue: String {
            switch self {
            case .page(let path):
                return "page:\(path)"
            case .rowBody(let dbPath, let rowId):
                return "row:\(dbPath)#\(rowId)"
            }
        }
    }

    private struct DraftRecord: Codable {
        let key: String
        let sourcePath: String?
        let content: String
        let savedAt: Date
    }

    private let fileManager: FileManager
    private let draftsDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.draftsDirectory = directoryURL ?? Self.defaultDraftsDirectory(fileManager: fileManager)
    }

    func savePageDraft(content: String, path: String) {
        saveDraft(content: content, for: .page(path: path), sourcePath: path)
    }

    func restorePageDraftIfNewer(path: String) -> String? {
        restoreDraftIfNewer(for: .page(path: path), sourcePath: path)
    }

    func clearPageDraft(path: String) {
        clearDraft(for: .page(path: path))
    }

    func saveRowBodyDraft(content: String, dbPath: String, rowId: String, rowFilePath: String?) {
        saveDraft(content: content, for: .rowBody(dbPath: dbPath, rowId: rowId), sourcePath: rowFilePath)
    }

    func restoreRowBodyDraftIfNewer(dbPath: String, rowId: String, rowFilePath: String?) -> String? {
        restoreDraftIfNewer(for: .rowBody(dbPath: dbPath, rowId: rowId), sourcePath: rowFilePath)
    }

    func clearRowBodyDraft(dbPath: String, rowId: String) {
        clearDraft(for: .rowBody(dbPath: dbPath, rowId: rowId))
    }

    private func saveDraft(content: String, for key: DraftKey, sourcePath: String?) {
        let record = DraftRecord(
            key: key.rawValue,
            sourcePath: sourcePath,
            content: content,
            savedAt: Date()
        )

        do {
            try ensureDraftDirectoryExists()
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            return
        }
    }

    private func restoreDraftIfNewer(for key: DraftKey, sourcePath: String?) -> String? {
        guard let record = loadDraft(for: key) else { return nil }
        guard shouldRestore(record, sourcePath: sourcePath) else {
            clearDraft(for: key)
            return nil
        }
        return record.content
    }

    private func clearDraft(for key: DraftKey) {
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    private func loadDraft(for key: DraftKey) -> DraftRecord? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(DraftRecord.self, from: data)
    }

    private func shouldRestore(_ record: DraftRecord, sourcePath: String?) -> Bool {
        let resolvedSourcePath = sourcePath ?? record.sourcePath
        guard let resolvedSourcePath, fileManager.fileExists(atPath: resolvedSourcePath) else {
            return true
        }
        guard let modificationDate = modificationDate(at: resolvedSourcePath) else {
            return true
        }
        return record.savedAt > modificationDate
    }

    private func ensureDraftDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: draftsDirectory.path) else { return }
        try fileManager.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: DraftKey) -> URL {
        draftsDirectory.appendingPathComponent("\(Self.filenameHash(for: key.rawValue)).json")
    }

    private func modificationDate(at path: String) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    private static func defaultDraftsDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Dahso", isDirectory: true)
            .appendingPathComponent("EditorDrafts", isDirectory: true)
    }

    private static func filenameHash(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
