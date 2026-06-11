import XCTest
@testable import Bugbook

/// Icon hydration for the sidebar tree (and everything derived from it —
/// favorites, palette entries): `buildFileTree` reads each page's icon from
/// the file head through an mtime-keyed cache, so unchanged files never pay
/// a re-read on rebuild.
@MainActor
final class PageIconHydrationTests: XCTestCase {

    private var workspace: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageIconHydrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspace)
        super.tearDown()
    }

    @discardableResult
    private func writePage(
        named name: String,
        icon: String?,
        mtime: Date? = nil
    ) throws -> String {
        let path = workspace.appendingPathComponent(name).path
        let head = icon.map { "<!-- icon:\($0) -->\n" } ?? ""
        try "\(head)# \(name)\n\nBody content long enough to pass the size filter.\n"
            .write(toFile: path, atomically: true, encoding: .utf8)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: path)
        }
        return path
    }

    private func treeEntry(named name: String, in service: FileSystemService) -> FileEntry? {
        service.buildFileTree(at: workspace.path).first { $0.name == name }
    }

    func testBuildFileTreeHydratesIconsFromFileHead() throws {
        let service = FileSystemService()
        try writePage(named: "Gateway.md", icon: "sf:globe")
        try writePage(named: "Rocket.md", icon: "🚀")
        try writePage(named: "Plain.md", icon: nil)

        let tree = service.buildFileTree(at: workspace.path)
        let icons = Dictionary(uniqueKeysWithValues: tree.map { ($0.name, $0.icon) })

        XCTAssertEqual(icons["Gateway.md"], "sf:globe")
        XCTAssertEqual(icons["Rocket.md"], "🚀")
        XCTAssertEqual(icons["Plain.md"] ?? nil, nil)
    }

    func testIconRehydratesWhenFileChanges() throws {
        let service = FileSystemService()
        let path = try writePage(named: "Note.md", icon: "sf:bolt.fill", mtime: Date(timeIntervalSinceNow: -100))
        XCTAssertEqual(treeEntry(named: "Note.md", in: service)?.icon, "sf:bolt.fill")

        // Rewrite with a different icon and a distinct mtime — the cache must
        // invalidate and re-read.
        try "<!-- icon:sf:flame -->\n# Note\n\nBody content long enough to pass the size filter.\n"
            .write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)

        XCTAssertEqual(treeEntry(named: "Note.md", in: service)?.icon, "sf:flame")
    }

    func testUnchangedFilesAreServedFromCacheWithoutReparsing() {
        let cache = PageIconHydrationCache()
        let mtime = Date(timeIntervalSinceNow: -50)
        var parseCount = 0

        let first = cache.icon(at: "/ws/A.md", modifiedAt: mtime) { _ in
            parseCount += 1
            return "sf:globe"
        }
        let second = cache.icon(at: "/ws/A.md", modifiedAt: mtime) { _ in
            parseCount += 1
            return "sf:globe"
        }

        XCTAssertEqual(first, "sf:globe")
        XCTAssertEqual(second, "sf:globe")
        XCTAssertEqual(parseCount, 1, "an unchanged mtime must be served from the cache")

        // A changed mtime invalidates the entry.
        let third = cache.icon(at: "/ws/A.md", modifiedAt: Date()) { _ in
            parseCount += 1
            return "sf:flame"
        }
        XCTAssertEqual(third, "sf:flame")
        XCTAssertEqual(parseCount, 2)
    }

    func testNilIconResultsAreCachedToo() {
        let cache = PageIconHydrationCache()
        let mtime = Date()
        var parseCount = 0

        XCTAssertNil(cache.icon(at: "/ws/B.md", modifiedAt: mtime) { _ in
            parseCount += 1
            return nil
        })
        XCTAssertNil(cache.icon(at: "/ws/B.md", modifiedAt: mtime) { _ in
            parseCount += 1
            return nil
        })
        XCTAssertEqual(parseCount, 1, "icon-less pages must not be re-read either")
    }
}
