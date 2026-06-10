import XCTest
@testable import Bugbook

/// Tests AiThreadStore through its interface. Persistence is write-behind;
/// `flushPendingWrites()` is the interface's durability barrier.
@MainActor
final class AiThreadStoreTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiThreadStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testAppendMessagePersistsAcrossReload() {
        let store = AiThreadStore(directoryURL: directory)
        let thread = store.createThread()
        store.appendMessage(
            ChatMessage(role: .user, content: "Hello world", timestamp: Date()),
            to: thread.id
        )
        store.flushPendingWrites()

        let reloaded = AiThreadStore(directoryURL: directory)
        XCTAssertEqual(reloaded.threads.count, 1)
        XCTAssertEqual(reloaded.threads.first?.messages.map(\.content), ["Hello world"])
        XCTAssertEqual(reloaded.threads.first?.title, "Hello world", "auto-title from first user message")
    }

    func testWritesAreOrderedAcrossAppends() {
        let store = AiThreadStore(directoryURL: directory)
        let thread = store.createThread()
        for index in 0..<5 {
            store.appendMessage(
                ChatMessage(role: .user, content: "msg \(index)", timestamp: Date()),
                to: thread.id
            )
        }
        store.flushPendingWrites()

        let reloaded = AiThreadStore(directoryURL: directory)
        XCTAssertEqual(
            reloaded.threads.first?.messages.map(\.content),
            ["msg 0", "msg 1", "msg 2", "msg 3", "msg 4"]
        )
    }

    func testDeleteThreadRemovesFile() {
        let store = AiThreadStore(directoryURL: directory)
        let thread = store.createThread()
        store.appendMessage(
            ChatMessage(role: .user, content: "bye", timestamp: Date()),
            to: thread.id
        )
        store.deleteThread(thread.id)
        store.flushPendingWrites()

        let reloaded = AiThreadStore(directoryURL: directory)
        XCTAssertTrue(reloaded.threads.isEmpty)
    }

    func testFlushAllPendingWritesFlushesLiveStores() {
        let store = AiThreadStore(directoryURL: directory)
        let thread = store.createThread()
        store.appendMessage(
            ChatMessage(role: .user, content: "terminate-flush", timestamp: Date()),
            to: thread.id
        )

        // App-lifecycle flush path (AppDelegate.applicationWillTerminate).
        AiThreadStore.flushAllPendingWrites()

        let reloaded = AiThreadStore(directoryURL: directory)
        XCTAssertEqual(reloaded.threads.first?.messages.map(\.content), ["terminate-flush"])
    }

    func testCoalescedBurstPersistsLatestSnapshot() {
        let store = AiThreadStore(directoryURL: directory)
        let thread = store.createThread()
        // A burst of appends coalesces (cancel-and-replace), but the surviving
        // write must carry the full final snapshot.
        for index in 0..<20 {
            store.appendMessage(
                ChatMessage(
                    role: index.isMultiple(of: 2) ? .user : .assistant,
                    content: "burst \(index)",
                    timestamp: Date()
                ),
                to: thread.id
            )
        }
        store.flushPendingWrites()

        let reloaded = AiThreadStore(directoryURL: directory)
        XCTAssertEqual(reloaded.threads.first?.messages.count, 20)
        XCTAssertEqual(reloaded.threads.first?.messages.last?.content, "burst 19")
    }
}
