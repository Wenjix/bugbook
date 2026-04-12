import XCTest
@testable import Dahso
@testable import DahsoCore

// MARK: - Baseline TSV Helper

/// Reads/writes performance baselines to a TSV file next to the test sources.
private enum PerfBaseline {
    static let tsvPath: String = {
        // Place the TSV next to the test file itself
        let thisFile = #filePath
        let dir = (thisFile as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent("perf_baseline.tsv")
    }()

    struct Entry {
        let testName: String
        let metric: String
        let value: Double
        let timestamp: String
    }

    static func load() -> [String: Entry] {
        guard let text = try? String(contentsOfFile: tsvPath, encoding: .utf8) else { return [:] }
        var entries: [String: Entry] = [:]
        for line in text.components(separatedBy: "\n").dropFirst() { // skip header
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 4, let val = Double(cols[2]) else { continue }
            entries[cols[0]] = Entry(testName: cols[0], metric: cols[1], value: val, timestamp: cols[3])
        }
        return entries
    }

    static func save(_ entries: [String: Entry]) {
        var lines = ["test_name\tmetric\tvalue\ttimestamp"]
        for key in entries.keys.sorted() {
            let e = entries[key]!
            lines.append("\(e.testName)\t\(e.metric)\t\(String(format: "%.3f", e.value))\t\(e.timestamp)")
        }
        try? lines.joined(separator: "\n").write(toFile: tsvPath, atomically: true, encoding: .utf8)
    }

    static func record(testName: String, metric: String, value: Double) {
        var entries = load()
        let ts = ISO8601DateFormatter().string(from: Date())
        let entry = Entry(testName: testName, metric: metric, value: value, timestamp: ts)

        // Compare to existing baseline if present
        if let baseline = entries[testName] {
            let pctChange = ((value - baseline.value) / baseline.value) * 100
            let direction = pctChange > 0 ? "slower" : "faster"
            let symbol = pctChange > 20 ? "REGRESSION" : "ok"
            print(String(format: "  %@: %.1fms -> %.1fms (%.0f%% %@) %@",
                         testName, baseline.value, value, abs(pctChange), direction, symbol))
        } else {
            print(String(format: "  %@: %.1fms (baseline)", testName, value))
        }

        entries[testName] = entry
        save(entries)
    }
}

// MARK: - Test Data Generators

private enum TestData {

    /// Build a schema with several property types for realistic serialization.
    static func makeSchema() -> DatabaseSchema {
        DatabaseSchema(
            id: "db_perf_test",
            name: "PerfTest",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(id: "prop_status", name: "Status", type: .select),
                PropertyDefinition(id: "prop_priority", name: "Priority", type: .number),
                PropertyDefinition(id: "prop_tags", name: "Tags", type: .multiSelect),
                PropertyDefinition(id: "prop_done", name: "Done", type: .checkbox),
                PropertyDefinition(id: "prop_due", name: "Due", type: .date),
                PropertyDefinition(id: "prop_url", name: "URL", type: .url),
            ],
            views: [ViewConfig(id: "view_table", name: "Table", type: .table)],
            defaultView: "view_table",
            createdAt: "2025-01-01T00:00:00Z"
        )
    }

    /// Create a row with all properties populated.
    static func makeRow(index: Int) -> DatabaseRow {
        DatabaseRow(
            id: "row_\(String(format: "%06d", index))",
            properties: [
                "prop_title": .text("Task number \(index) with a reasonably long title for realism"),
                "prop_status": .select("In Progress"),
                "prop_priority": .number(Double(index % 5)),
                "prop_tags": .multiSelect(["backend", "urgent", "sprint-\(index % 10)"]),
                "prop_done": .checkbox(index % 3 == 0),
                "prop_due": .date("2025-06-\(String(format: "%02d", (index % 28) + 1))"),
                "prop_url": .url("https://example.com/task/\(index)"),
            ],
            body: "This is the body of row \(index).\nIt has multiple lines.\n\nAnd a blank line too.",
            createdAt: Date(timeIntervalSinceReferenceDate: Double(index * 86400)),
            updatedAt: Date()
        )
    }

    /// Generate a 500-line markdown document with varied block types.
    static func makeMarkdown(lineCount: Int) -> String {
        var lines: [String] = []
        lines.append("# Performance Test Document")
        lines.append("")
        var i = 2
        while i < lineCount {
            let mod = i % 20
            switch mod {
            case 0:
                lines.append("## Section \(i / 20)")
            case 1, 2, 3:
                lines.append("This is paragraph \(i). It contains some **bold** and *italic* text, plus a [[wiki link]] and `inline code`.")
            case 4:
                lines.append("- Bullet item \(i)")
            case 5:
                lines.append("  - Nested bullet item \(i)")
            case 6:
                lines.append("- [ ] Task item \(i)")
            case 7:
                lines.append("- [x] Completed task \(i)")
            case 8:
                lines.append("1. Numbered item \(i)")
            case 9:
                lines.append("> Blockquote text at line \(i)")
            case 10:
                lines.append("```swift")
                lines.append("let x = \(i)")
                lines.append("print(x)")
                lines.append("```")
                i += 3
            case 11:
                lines.append("---")
            case 12:
                lines.append("### Heading Three \(i)")
            case 13:
                lines.append("[[Page Link \(i)]]")
            case 14, 15, 16, 17, 18, 19:
                lines.append("Regular paragraph line \(i) with some content to parse.")
            default:
                lines.append("")
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Generate markdown for N blocks (paragraphs, headings, lists).
    static func makeBlockMarkdown(blockCount: Int) -> String {
        var lines: [String] = []
        for j in 0..<blockCount {
            switch j % 5 {
            case 0: lines.append("# Heading \(j)")
            case 1: lines.append("Paragraph \(j) with some text content for the block document.")
            case 2: lines.append("- Bullet \(j)")
            case 3: lines.append("- [ ] Task \(j)")
            case 4: lines.append("> Quote \(j)")
            default: lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Performance Tests

@MainActor
final class PerformanceTests: XCTestCase {

    /// Run a block 10 times, return the median duration in milliseconds.
    /// Separate from XCTest's `measure` because its results aren't programmatically accessible.
    private func timed(_ block: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<10 {
            let start = CFAbsoluteTimeGetCurrent()
            block()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        samples.sort()
        return samples[samples.count / 2] // median
    }

    // MARK: 1. RowSerializer: serialize/deserialize 100 rows

    func testRowSerialize100() {
        let schema = TestData.makeSchema()
        let rows = (0..<100).map { TestData.makeRow(index: $0) }

        measure {
            for row in rows {
                _ = RowSerializer.serialize(row: row, schema: schema)
            }
        }

        let ms = timed {
            for row in rows { _ = RowSerializer.serialize(row: row, schema: schema) }
        }
        PerfBaseline.record(testName: "row_serialize_100", metric: "ms", value: ms)
    }

    func testRowDeserialize100() {
        let schema = TestData.makeSchema()
        let serialized = (0..<100).map { RowSerializer.serialize(row: TestData.makeRow(index: $0), schema: schema) }

        measure {
            for content in serialized {
                _ = RowSerializer.parse(content: content, schema: schema)
            }
        }

        let ms = timed {
            for content in serialized { _ = RowSerializer.parse(content: content, schema: schema) }
        }
        PerfBaseline.record(testName: "row_deserialize_100", metric: "ms", value: ms)
    }

    // MARK: 2. MarkdownBlockParser: parse 500-line document

    func testMarkdownParse500Lines() {
        let markdown = TestData.makeMarkdown(lineCount: 500)

        measure { _ = MarkdownBlockParser.parse(markdown) }

        let ms = timed { _ = MarkdownBlockParser.parse(markdown) }
        PerfBaseline.record(testName: "markdown_parse_500", metric: "ms", value: ms)
    }

    func testMarkdownSerialize500Lines() {
        let markdown = TestData.makeMarkdown(lineCount: 500)
        let blocks = MarkdownBlockParser.parse(markdown)

        measure { _ = MarkdownBlockParser.serialize(blocks) }

        let ms = timed { _ = MarkdownBlockParser.serialize(blocks) }
        PerfBaseline.record(testName: "markdown_serialize_500", metric: "ms", value: ms)
    }

    // MARK: 3. DatabaseStore: load schema + 100 rows from disk

    func testDatabaseStoreLoad100Rows() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DahsoPerfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dbPath = tmpDir.path
        let schema = TestData.makeSchema()

        // Write schema
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let schemaData = try encoder.encode(schema)
        try schemaData.write(to: tmpDir.appendingPathComponent("_schema.json"))

        // Write 100 row files
        let rowStore = RowStore()
        for i in 0..<100 {
            let row = TestData.makeRow(index: i)
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
        }

        let store = DatabaseStore()

        measure {
            let s = try! store.loadSchema(at: dbPath)
            _ = rowStore.loadAllRows(in: dbPath, schema: s)
        }

        let ms = timed {
            let s = try! store.loadSchema(at: dbPath)
            _ = rowStore.loadAllRows(in: dbPath, schema: s)
        }
        PerfBaseline.record(testName: "database_load_100", metric: "ms", value: ms)
    }

    // MARK: 4. BlockDocument: init with 50 blocks

    func testBlockDocumentInit50Blocks() {
        let markdown = TestData.makeBlockMarkdown(blockCount: 50)

        measure { _ = BlockDocument(markdown: markdown) }

        let ms = timed { _ = BlockDocument(markdown: markdown) }
        PerfBaseline.record(testName: "block_document_init_50", metric: "ms", value: ms)
    }

    // MARK: 5. QmdService: binary path detection

    func testQmdFindBinaryPath() {
        measure { _ = QmdService.findBinaryPath() }

        let ms = timed { _ = QmdService.findBinaryPath() }
        PerfBaseline.record(testName: "qmd_find_binary", metric: "ms", value: ms)
    }

    // MARK: 6. FileSystemService: build file tree for 100 files

    func testFileSystemBuildTree100Files() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DahsoPerfTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create 100 .md files
        for i in 0..<100 {
            let filename = "Page \(String(format: "%03d", i)).md"
            let filePath = tmpDir.appendingPathComponent(filename)
            try "# Page \(i)\n\nSome content here.\n".write(to: filePath, atomically: true, encoding: .utf8)
        }

        let service = FileSystemService()

        measure { _ = service.buildFileTree(at: tmpDir.path) }

        let ms = timed { _ = service.buildFileTree(at: tmpDir.path) }
        PerfBaseline.record(testName: "filesystem_tree_100", metric: "ms", value: ms)
    }
}
