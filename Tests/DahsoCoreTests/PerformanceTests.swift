import XCTest
@testable import DahsoCore

final class PerformanceTests: XCTestCase {

    // MARK: - Test Data Helpers

    private func makeSampleSchema(propertyCount: Int = 5) -> DatabaseSchema {
        var props: [PropertyDefinition] = [
            PropertyDefinition(id: "prop_title", name: "Title", type: .title),
        ]
        for i in 1..<propertyCount {
            let type: PropertyType
            switch i % 4 {
            case 0: type = .text
            case 1: type = .select
            case 2: type = .number
            case 3: type = .checkbox
            default: type = .text
            }
            props.append(PropertyDefinition(id: "prop_\(i)", name: "Prop \(i)", type: type))
        }
        return DatabaseSchema(
            id: "db_perf",
            name: "PerfTest",
            properties: props,
            views: [ViewConfig(id: "view_table", name: "All", type: .table)],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
    }

    private func makeSampleRow(index: Int, schema: DatabaseSchema) -> DatabaseRow {
        var properties: [String: PropertyValue] = [:]
        for prop in schema.properties {
            switch prop.type {
            case .title:
                properties[prop.id] = .text("Row Title \(index)")
            case .text:
                properties[prop.id] = .text("Some text content for row \(index) that is moderately long")
            case .select:
                properties[prop.id] = .select("option_\(index % 5)")
            case .number:
                properties[prop.id] = .number(Double(index) * 1.5)
            case .checkbox:
                properties[prop.id] = .checkbox(index % 2 == 0)
            default:
                break
            }
        }
        let baseDate = Date(timeIntervalSince1970: 1700000000 + Double(index) * 3600)
        return DatabaseRow(
            id: "row_\(String(format: "%06d", index))",
            properties: properties,
            body: "This is the body content for row \(index).\nIt has multiple lines.\nLine 3 here.",
            createdAt: baseDate,
            updatedAt: baseDate.addingTimeInterval(86400)
        )
    }

    private func makeSampleContent(index: Int, schema: DatabaseSchema) -> String {
        let row = makeSampleRow(index: index, schema: schema)
        return RowSerializer.serialize(row: row, schema: schema)
    }

    // MARK: - Row Serialization Performance

    func testSerializePerformance_100rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<100).map { makeSampleRow(index: $0, schema: schema) }

        measure {
            for row in rows {
                _ = RowSerializer.serialize(row: row, schema: schema)
            }
        }
    }

    func testSerializePerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }

        measure {
            for row in rows {
                _ = RowSerializer.serialize(row: row, schema: schema)
            }
        }
    }

    // MARK: - Row Parse Performance

    func testParsePerformance_100rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let contents = (0..<100).map { makeSampleContent(index: $0, schema: schema) }

        measure {
            for content in contents {
                _ = RowSerializer.parse(content: content, schema: schema)
            }
        }
    }

    func testParsePerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let contents = (0..<1000).map { makeSampleContent(index: $0, schema: schema) }

        measure {
            for content in contents {
                _ = RowSerializer.parse(content: content, schema: schema)
            }
        }
    }

    func testParsePerformance_skipBody_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let contents = (0..<1000).map { makeSampleContent(index: $0, schema: schema) }

        measure {
            for content in contents {
                _ = RowSerializer.parse(content: content, schema: schema, skipBody: true)
            }
        }
    }

    // MARK: - Round Trip Performance

    func testRoundTripPerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }

        measure {
            for row in rows {
                let content = RowSerializer.serialize(row: row, schema: schema)
                _ = RowSerializer.parse(content: content, schema: schema)
            }
        }
    }

    // MARK: - Query Engine Performance

    func testQueryFilterPerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }
        let query = Query(
            databaseId: "db_perf",
            filters: [
                .equals(property: "prop_1", value: .select("option_2")),
                .isNotEmpty(property: "prop_title"),
            ]
        )

        measure {
            _ = QueryEngine.execute(query: query, schema: schema, rows: rows)
        }
    }

    func testQuerySortPerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }
        let query = Query(
            databaseId: "db_perf",
            sorts: [Sort(property: "prop_2", ascending: false)]
        )

        measure {
            _ = QueryEngine.execute(query: query, schema: schema, rows: rows)
        }
    }

    func testQueryFilterAndSortPerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }
        let query = Query(
            databaseId: "db_perf",
            filters: [
                .equals(property: "prop_1", value: .select("option_2")),
            ],
            sorts: [Sort(property: "prop_2", ascending: true)],
            limit: 50
        )

        measure {
            _ = QueryEngine.execute(query: query, schema: schema, rows: rows)
        }
    }

    // MARK: - Index Rebuild Performance

    func testIndexRebuildPerformance_100rows() throws {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<100).map { makeSampleRow(index: $0, schema: schema) }

        let tmpDir = NSTemporaryDirectory() + "dahso_perf_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let indexManager = IndexManager()

        measure {
            _ = indexManager.rebuild(dbPath: tmpDir, schema: schema, rows: rows)
        }
    }

    func testIndexRebuildPerformance_500rows() throws {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<500).map { makeSampleRow(index: $0, schema: schema) }

        let tmpDir = NSTemporaryDirectory() + "dahso_perf_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let indexManager = IndexManager()

        measure {
            _ = indexManager.rebuild(dbPath: tmpDir, schema: schema, rows: rows)
        }
    }

    // MARK: - Schema Validation Performance

    func testSchemaValidationPerformance_1000rows() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<1000).map { makeSampleRow(index: $0, schema: schema) }

        measure {
            for row in rows {
                _ = SchemaValidator.validate(properties: row.properties, schema: schema, requireTitle: true)
            }
        }
    }

    // MARK: - Correctness Sanity Checks

    func testSerializeParseRoundTrip() {
        let schema = makeSampleSchema(propertyCount: 8)
        let row = makeSampleRow(index: 42, schema: schema)

        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.id, row.id)
        XCTAssertEqual(parsed?.properties.count, row.properties.count)
        XCTAssertEqual(parsed?.body, row.body)
    }

    func testQueryFilterCorrectness() {
        let schema = makeSampleSchema(propertyCount: 8)
        let rows = (0..<100).map { makeSampleRow(index: $0, schema: schema) }
        let query = Query(
            databaseId: "db_perf",
            filters: [.equals(property: "prop_1", value: .select("option_2"))]
        )

        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        // Every 5th row has option_2 (index % 5 == 2)
        XCTAssertEqual(result.totalCount, 20)
        for row in result.rows {
            XCTAssertEqual(row.properties["prop_1"], .select("option_2"))
        }
    }
}
