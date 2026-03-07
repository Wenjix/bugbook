import Foundation
import CoreServices

/// Watches a workspace directory recursively for file system changes
/// (agent edits, CLI operations, Finder moves, etc.) and fires a callback
/// so the UI can refresh the file tree.
///
/// Uses FSEvents for efficient recursive monitoring. Changes are debounced
/// to avoid excessive refreshes during bulk operations.
final class WorkspaceWatcher {
    private var stream: FSEventStreamRef?
    private var debounceItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.8
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func watch(path: String) {
        stop()

        let paths = [path] as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<WorkspaceWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleCallback()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency — FSEvents batches changes within this window
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    private func scheduleCallback() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }
        debounceItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: item
        )
    }
}
