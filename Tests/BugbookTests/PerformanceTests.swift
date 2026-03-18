import XCTest
@testable import Bugbook
@testable import BugbookCore

// MARK: - Baseline TSV Helpers

/// Reads/writes perf_baseline.tsv alongside the test source file.
/// Format: test_name\tmetric\tvalue\ttimestamp
private enum PerfBaseline {
    static let tsvPath: String = {
        // Place baseline TSV next to the compiled test bundle's resource dir,
        // but more practically, use a well-known path in the repo.
        let repoRoot = ProcessInfo.processInfo.environment["REPO_ROOT"]
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/BugbookTests/
                .path
        return (repoRoot as NSString).appendingPathComponent("perf_baseline.tsv")
    }()

    struct Entry {
        let testName: String
        let metric: String
        let value: Double
        let timestamp: String
    }

    static func loadBaseline() -> [String: Entry] {
        guard let content = try? String(contentsOfFile: tsvPath, encoding: .utf8) else { return [:] }
        var entries: [String: Entry] = [:]
        for line in content.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 4, cols[0] != "test_name" else { continue }
            if let val = Double(cols[2]) {
                entries[cols[0]] = Entry(testName: cols[0], metric: cols[1], value: val, timestamp: cols[3])
            }
        }
        return entries
    }

    static func appendResult(testName: String, metric: String, value: Double) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ts = iso.string(from: Date())

        let line = "\(testName)\t\(metric)\t\(String(format: "%.6f", value))\t\(ts)\n"

        if !FileManager.default.fileExists(atPath: tsvPath) {
            let header = "test_name\tmetric\tvalue\ttimestamp\n"
            try? (header + line).write(toFile: tsvPath, atomically: true, encoding: .utf8)
        } else {
            if let handle = FileHandle(forWritingAtPath: tsvPath) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            }
        }
    }

    /// Compare a new measurement against the baseline.
    /// Returns (passed, message). Regression threshold: 20% slower.
    static func compare(testName: String, metric: String, newValue: Double) -> (Bool, String) {
        let baseline = loadBaseline()
        guard let entry = baseline[testName] else {
            return (true, "\(testName): \(String(format: "%.4f", newValue))s (no baseline, recording)")
        }
        let change = (newValue - entry.value) / entry.value * 100
        let arrow = change > 0 ? "slower" : "faster"
        let passed = change < 20.0 // fail if >20% regression
        let status = passed ? "PASS" : "FAIL"
        let msg = "\(status) \(testName): \(String(format: "%.4f", entry.value))s -> \(String(format: "%.4f", newValue))s (\(String(format: "%+.1f", change))% \(arrow))"
        return (passed, msg)
    }
}

// MARK: - Test Data Generators

private enum TestData {
    static func makeSchema(propertyCount: Int = 5) -> DatabaseSchema {
        var props: [PropertyDefinition] = [
            PropertyDefinition(id: "prop_title", name: "Title", type: .title)
        ]
        let types: [PropertyType] = [.text, .number, .select, .checkbox, .date]
        for i in 1..<propertyCount {
            props.append(PropertyDefinition(
                id: "prop_\(i)",
                name: "Prop \(i)",
                type: types[i % types.count]
            ))
        }
        return DatabaseSchema(
            id: "db_perf_test",
            name: "Perf Test DB",
            properties: props,
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2025-01-01T00:00:00Z"
        )
    }

    static func makeRow(index: Int, schema: DatabaseSchema) -> DatabaseRow {
        var props: [String: PropertyValue] = [:]
        for prop in schema.properties {
            switch prop.type {
            case .title: props[prop.id] = .text("Row \(index)")
            case .text: props[prop.id] = .text("Some text content for row \(index) property \(prop.id)")
            case .number: props[prop.id] = .number(Double(index) * 1.5)
            case .select: props[prop.id] = .select("option_\(index % 5)")
            case .checkbox: props[prop.id] = .checkbox(index % 2 == 0)
            case .date: props[prop.id] = .date("2025-01-\(String(format: "%02d", (index % 28) + 1))")
            default: break
            }
        }
        return DatabaseRow(
            id: "row_\(String(format: "%06d", index))",
            properties: props,
            body: "Body content for row \(index).\nSecond line of body.",
            createdAt: Date(timeIntervalSince1970: 1700000000 + Double(index)),
            updatedAt: Date(timeIntervalSince1970: 1700000000 + Double(index) + 100)
        )
    }

    static func makeMarkdownDocument(lineCount: Int) -> String {
        var lines: [String] = ["# Performance Test Document"]
        var currentLine = 1
        while currentLine < lineCount {
            let blockType = currentLine % 10
            switch blockType {
            case 0:
                lines.append("## Section \(currentLine)")
            case 1, 2:
                lines.append("This is paragraph text on line \(currentLine). It contains some **bold** and *italic* formatting.")
            case 3:
                lines.append("- Bullet item \(currentLine)")
            case 4:
                lines.append("- [ ] Task item \(currentLine)")
            case 5:
                lines.append("> Blockquote on line \(currentLine)")
            case 6:
                lines.append("\(currentLine). Numbered item")
            case 7:
                lines.append("```swift")
                lines.append("let x = \(currentLine)")
                lines.append("```")
                currentLine += 2
            case 8:
                lines.append("")
            case 9:
                lines.append("[[Page Link \(currentLine)]]")
            default:
                lines.append("Paragraph \(currentLine)")
            }
            currentLine += 1
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Performance Tests

final class PerformanceTests: XCTestCase {

    // MARK: 1. RowSerializer — serialize/deserialize 100 rows

    func testRowSerializerPerformance() {
        let schema = TestData.makeSchema()
        let rows = (0..<100).map { TestData.makeRow(index: $0, schema: schema) }

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            for row in rows {
                let serialized = RowSerializer.serialize(row: row, schema: schema)
                _ = RowSerializer.parse(content: serialized, schema: schema)
            }
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "RowSerializer_100rows", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "RowSerializer_100rows", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 2. MarkdownBlockParser — parse a 500-line document

    func testMarkdownBlockParserPerformance() {
        let markdown = TestData.makeMarkdownDocument(lineCount: 500)

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            _ = MarkdownBlockParser.parse(markdown)
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "MarkdownBlockParser_500lines", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "MarkdownBlockParser_500lines", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 3. DatabaseStore — load schema + 100 rows from disk

    func testDatabaseStoreLoadPerformance() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookPerfTest-\(UUID().uuidString)", isDirectory: true)
        let dbPath = tmpDir.appendingPathComponent("perf_db").path
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Set up a database on disk
        let schema = TestData.makeSchema()
        let store = DatabaseStore()
        try FileManager.default.createDirectory(atPath: dbPath, withIntermediateDirectories: true)
        try store.saveSchema(schema, at: dbPath)

        let rowStore = RowStore()
        for i in 0..<100 {
            let row = TestData.makeRow(index: i, schema: schema)
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
        }

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            let loadedSchema = try! store.loadSchema(at: dbPath)
            _ = rowStore.loadAllRows(in: dbPath, schema: loadedSchema)
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "DatabaseStore_load_100rows", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "DatabaseStore_load_100rows", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 4. BlockDocument — init with 50 blocks

    @MainActor
    func testBlockDocumentInitPerformance() {
        // Build markdown with ~50 blocks
        let markdown = TestData.makeMarkdownDocument(lineCount: 50)

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            _ = BlockDocument(markdown: markdown)
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "BlockDocument_init_50blocks", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "BlockDocument_init_50blocks", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 5. QmdService — binary path lookup (index rebuild requires live workspace)

    func testQmdServiceDetectPerformance() {
        // Skip if qmd is not installed
        guard QmdService.findBinaryPath() != nil else {
            print("SKIP QmdService_detect: qmd not installed")
            return
        }

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            _ = QmdService.findBinaryPath()
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "QmdService_detect", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "QmdService_detect", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 6. FileSystemService — build file tree for 100 files

    @MainActor
    func testFileSystemBuildTreePerformance() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookPerfTree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Create 100 .md files
        for i in 0..<100 {
            let filePath = tmpDir.appendingPathComponent("Note \(String(format: "%03d", i)).md")
            try "# Note \(i)\n\nContent here.\n".write(to: filePath, atomically: true, encoding: .utf8)
        }

        let service = FileSystemService()

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            _ = service.buildFileTree(at: tmpDir.path)
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "FileSystemService_buildTree_100files", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "FileSystemService_buildTree_100files", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: 7. IndexManager — rebuild index for 100 rows

    func testIndexManagerRebuildPerformance() {
        let schema = TestData.makeSchema()
        let rows = (0..<100).map { TestData.makeRow(index: $0, schema: schema) }
        let indexManager = IndexManager()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugbookPerfIndex-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        var elapsed: Double = 0
        measure {
            let start = CFAbsoluteTimeGetCurrent()
            _ = indexManager.rebuild(dbPath: tmpDir.path, schema: schema, rows: rows)
            elapsed = CFAbsoluteTimeGetCurrent() - start
        }

        PerfBaseline.appendResult(testName: "IndexManager_rebuild_100rows", metric: "wall_time_s", value: elapsed)
        let (passed, msg) = PerfBaseline.compare(testName: "IndexManager_rebuild_100rows", metric: "wall_time_s", newValue: elapsed)
        print(msg)
        XCTAssertTrue(passed, msg)
    }

    // MARK: - Summary / Compare All

    func testPerfSummary() {
        let baseline = PerfBaseline.loadBaseline()
        if baseline.isEmpty {
            print("\n=== PERF BASELINE ===")
            print("No baseline found at \(PerfBaseline.tsvPath)")
            print("First run — results are being recorded as the new baseline.")
            print("=====================\n")
        } else {
            print("\n=== PERF COMPARISON ===")
            print("Baseline: \(PerfBaseline.tsvPath)")
            print("Entries: \(baseline.count)")
            for (name, entry) in baseline.sorted(by: { $0.key < $1.key }) {
                print("  \(name): \(String(format: "%.4f", entry.value))s (recorded \(entry.timestamp))")
            }
            print("========================\n")
        }
    }
}
