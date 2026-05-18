import Foundation

enum EditorSaveResult: Equatable, Sendable {
    case saved
    case missing
    case cancelled
    case failed(String)
}

struct EditorLoadedPage: Sendable {
    let content: String
    let isRestoredDraft: Bool
    let parsedDocument: BlockDocument.ParsedDocument?

    init(
        content: String,
        isRestoredDraft: Bool,
        parsedDocument: BlockDocument.ParsedDocument? = nil
    ) {
        self.content = content
        self.isRestoredDraft = isRestoredDraft
        self.parsedDocument = parsedDocument
    }
}

extension EditorLoadedPage: Equatable {
    static func == (lhs: EditorLoadedPage, rhs: EditorLoadedPage) -> Bool {
        lhs.content == rhs.content &&
            lhs.isRestoredDraft == rhs.isRestoredDraft
    }
}

enum EditorLoadResult: Equatable, Sendable {
    case loaded(EditorLoadedPage)
    case missing
    case cancelled
    case failed(String)
}

actor EditorSaveWorker {
    private struct PageFileMetadata: Equatable, Sendable {
        let fileSize: UInt64
        let modificationDate: Date
    }

    private struct CachedPageContent: Sendable {
        let metadata: PageFileMetadata
        let content: String
        let parsedDocument: BlockDocument.ParsedDocument?
    }

    private struct DiskReadResult: Sendable {
        let metadata: PageFileMetadata
        let content: String
    }

    private static let maxCachedPages = 128

    private let fileManager: FileManager
    private let draftStore: EditorDraftStore
    private var contentCache: [String: CachedPageContent] = [:]
    private var contentCacheOrder: [String] = []

    init(fileManager: FileManager = .default, draftStore: EditorDraftStore = EditorDraftStore()) {
        self.fileManager = fileManager
        self.draftStore = draftStore
    }

    func savePageDraft(content: String, path: String) {
        guard !Task.isCancelled else { return }
        draftStore.savePageDraft(content: content, path: path)
    }

    func clearPageDraft(path: String) {
        guard !Task.isCancelled else { return }
        draftStore.clearPageDraft(path: path)
    }

    func saveMarkdownFile(at path: String, content: String) async -> EditorSaveResult {
        guard !Task.isCancelled else { return .cancelled }
        let result = await Task.detached(priority: .utility) { () -> EditorSaveResult in
            guard !Task.isCancelled else { return .cancelled }
            guard FileManager.default.fileExists(atPath: path) else { return .missing }
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return .saved
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value

        if result == .saved {
            updateCache(path: path, content: content)
        }
        return result
    }

    func appendMarkdownToFile(at path: String, markdown: String) async -> EditorLoadResult {
        guard !Task.isCancelled else { return .cancelled }

        let result = await Task.detached(priority: .userInitiated) { () -> EditorLoadResult in
            guard !Task.isCancelled else { return .cancelled }
            guard FileManager.default.fileExists(atPath: path) else { return .missing }

            do {
                var content = try String(contentsOfFile: path, encoding: .utf8)
                if !content.hasSuffix("\n") { content += "\n" }
                content += markdown
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                let parsed = BlockDocument.parseMarkdown(content)
                return .loaded(EditorLoadedPage(
                    content: content,
                    isRestoredDraft: false,
                    parsedDocument: parsed
                ))
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value

        if case .loaded(let loadedPage) = result {
            updateCache(
                path: path,
                content: loadedPage.content,
                parsedDocument: loadedPage.parsedDocument
            )
        }
        return result
    }

    func loadPageContent(at path: String, priority: TaskPriority = .userInitiated) async -> EditorLoadResult {
        guard !Task.isCancelled else { return .cancelled }
        guard let metadata = Self.fileMetadata(at: path) else { return .missing }

        let diskContent: String
        let cachedParsedDocument: BlockDocument.ParsedDocument?
        if let cached = contentCache[path], cached.metadata == metadata {
            diskContent = cached.content
            cachedParsedDocument = cached.parsedDocument
            touchCacheEntry(path)
        } else {
            let result = await Self.readDiskContent(at: path, priority: priority)
            guard !Task.isCancelled else { return .cancelled }

            switch result {
            case .success(let diskResult):
                diskContent = diskResult.content
                cachedParsedDocument = nil
                cache(
                    content: diskResult.content,
                    metadata: diskResult.metadata,
                    path: path,
                    parsedDocument: nil
                )
            case .failure(let error):
                return .failed(error.localizedDescription)
            }
        }

        let restoredDraft = draftStore.restorePageDraftIfNewer(path: path)
        let content = restoredDraft ?? diskContent
        let parsed: BlockDocument.ParsedDocument
        if restoredDraft == nil, let cachedParsedDocument {
            parsed = cachedParsedDocument
        } else {
            parsed = await Self.parsePageContent(content, priority: priority)
        }
        if restoredDraft == nil, cachedParsedDocument == nil {
            updateCache(path: path, content: content, parsedDocument: parsed)
        }
        return .loaded(EditorLoadedPage(
            content: content,
            isRestoredDraft: restoredDraft != nil,
            parsedDocument: parsed
        ))
    }

    func preloadPageContent(at path: String) async {
        _ = await loadPageContent(at: path, priority: .utility)
    }

    private static func readDiskContent(
        at path: String,
        priority: TaskPriority
    ) async -> Result<DiskReadResult, Error> {
        await Task.detached(priority: priority) {
            do {
                guard let metadata = fileMetadata(at: path) else {
                    return .failure(CocoaError(.fileReadNoSuchFile))
                }
                let content = try String(contentsOfFile: path, encoding: .utf8)
                return .success(DiskReadResult(metadata: metadata, content: content))
            } catch {
                return .failure(error)
            }
        }.value
    }

    private static func parsePageContent(
        _ content: String,
        priority: TaskPriority
    ) async -> BlockDocument.ParsedDocument {
        await Task.detached(priority: priority) {
            BlockDocument.parseMarkdown(content)
        }.value
    }

    private static func fileMetadata(at path: String) -> PageFileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return PageFileMetadata(fileSize: fileSize.uint64Value, modificationDate: modificationDate)
    }

    private func updateCache(
        path: String,
        content: String,
        parsedDocument: BlockDocument.ParsedDocument? = nil
    ) {
        guard let metadata = Self.fileMetadata(at: path) else {
            contentCache.removeValue(forKey: path)
            contentCacheOrder.removeAll { $0 == path }
            return
        }
        cache(content: content, metadata: metadata, path: path, parsedDocument: parsedDocument)
    }

    private func cache(
        content: String,
        metadata: PageFileMetadata,
        path: String,
        parsedDocument: BlockDocument.ParsedDocument?
    ) {
        contentCache[path] = CachedPageContent(
            metadata: metadata,
            content: content,
            parsedDocument: parsedDocument
        )
        touchCacheEntry(path)
        while contentCacheOrder.count > Self.maxCachedPages {
            let evicted = contentCacheOrder.removeFirst()
            contentCache.removeValue(forKey: evicted)
        }
    }

    private func touchCacheEntry(_ path: String) {
        contentCacheOrder.removeAll { $0 == path }
        contentCacheOrder.append(path)
    }
}
