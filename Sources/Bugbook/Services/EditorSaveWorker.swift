import Foundation

enum EditorSaveResult: Equatable {
    case saved
    case missing
    case cancelled
    case failed(String)
}

struct EditorLoadedPage: Equatable {
    let content: String
    let isRestoredDraft: Bool
}

enum EditorLoadResult: Equatable {
    case loaded(EditorLoadedPage)
    case missing
    case cancelled
    case failed(String)
}

actor EditorSaveWorker {
    private let fileManager: FileManager
    private let draftStore: EditorDraftStore

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

    func saveMarkdownFile(at path: String, content: String) -> EditorSaveResult {
        guard !Task.isCancelled else { return .cancelled }
        guard fileManager.fileExists(atPath: path) else { return .missing }

        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func appendMarkdownToFile(at path: String, markdown: String) -> EditorLoadResult {
        guard !Task.isCancelled else { return .cancelled }
        guard fileManager.fileExists(atPath: path) else { return .missing }

        do {
            var content = try String(contentsOfFile: path, encoding: .utf8)
            if !content.hasSuffix("\n") { content += "\n" }
            content += markdown
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return .loaded(EditorLoadedPage(content: content, isRestoredDraft: false))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func loadPageContent(at path: String) -> EditorLoadResult {
        guard !Task.isCancelled else { return .cancelled }
        guard fileManager.fileExists(atPath: path) else { return .missing }

        do {
            let diskContent = try String(contentsOfFile: path, encoding: .utf8)
            guard !Task.isCancelled else { return .cancelled }
            let restoredDraft = draftStore.restorePageDraftIfNewer(path: path)
            return .loaded(EditorLoadedPage(
                content: restoredDraft ?? diskContent,
                isRestoredDraft: restoredDraft != nil
            ))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
