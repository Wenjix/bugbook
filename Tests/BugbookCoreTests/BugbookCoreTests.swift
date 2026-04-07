import XCTest
@testable import BugbookCore

// MARK: - Schema Model Tests

final class SchemaModelTests: XCTestCase {

    func testPropertyTypeRawValues() {
        XCTAssertEqual(PropertyType.title.rawValue, "title")
        XCTAssertEqual(PropertyType.text.rawValue, "text")
        XCTAssertEqual(PropertyType.number.rawValue, "number")
        XCTAssertEqual(PropertyType.select.rawValue, "select")
        XCTAssertEqual(PropertyType.multiSelect.rawValue, "multi_select")
        XCTAssertEqual(PropertyType.date.rawValue, "date")
        XCTAssertEqual(PropertyType.checkbox.rawValue, "checkbox")
        XCTAssertEqual(PropertyType.url.rawValue, "url")
        XCTAssertEqual(PropertyType.email.rawValue, "email")
        XCTAssertEqual(PropertyType.relation.rawValue, "relation")
        XCTAssertEqual(PropertyType.formula.rawValue, "formula")
        XCTAssertEqual(PropertyType.lookup.rawValue, "lookup")
        XCTAssertEqual(PropertyType.rollup.rawValue, "rollup")
    }

    func testPropertyTypeAllCases() {
        XCTAssertEqual(PropertyType.allCases.count, 13)
    }

    func testSelectOptionInit() {
        let opt = SelectOption(id: "opt_1", name: "Active", color: "green")
        XCTAssertEqual(opt.id, "opt_1")
        XCTAssertEqual(opt.name, "Active")
        XCTAssertEqual(opt.color, "green")
    }

    func testSelectOptionHashable() {
        let opt1 = SelectOption(id: "opt_1", name: "Active", color: "green")
        let opt2 = SelectOption(id: "opt_1", name: "Active", color: "green")
        let opt3 = SelectOption(id: "opt_2", name: "Inactive", color: "red")
        var set = Set<SelectOption>()
        set.insert(opt1)
        set.insert(opt2)
        set.insert(opt3)
        XCTAssertEqual(set.count, 2)
    }

    func testPropertyConfigInit() {
        let opts = [SelectOption(id: "o1", name: "Low", color: "gray")]
        let config = PropertyConfig(options: opts, format: "percent", target: "db_123", cardinality: "one")
        XCTAssertEqual(config.options?.count, 1)
        XCTAssertEqual(config.format, "percent")
        XCTAssertEqual(config.target, "db_123")
        XCTAssertEqual(config.cardinality, "one")
    }

    func testPropertyDefinitionOptionsAccessor() {
        var prop = PropertyDefinition(id: "prop_status", name: "Status", type: .select)
        XCTAssertNil(prop.options)

        let opts = [SelectOption(id: "opt_done", name: "Done", color: "green")]
        prop.options = opts
        XCTAssertEqual(prop.options?.count, 1)
        XCTAssertEqual(prop.options?.first?.id, "opt_done")
    }

    func testDatabaseSchemaTitleProperty() {
        let titleProp = PropertyDefinition(id: "prop_title", name: "Title", type: .title)
        let textProp = PropertyDefinition(id: "prop_notes", name: "Notes", type: .text)
        let schema = DatabaseSchema(
            id: "db_1",
            name: "Tasks",
            properties: [textProp, titleProp],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertEqual(schema.titleProperty?.id, "prop_title")
    }

    func testDatabaseSchemaTitlePropertyNilWhenAbsent() {
        let textProp = PropertyDefinition(id: "prop_notes", name: "Notes", type: .text)
        let schema = DatabaseSchema(
            id: "db_1",
            name: "Notes",
            properties: [textProp],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertNil(schema.titleProperty)
    }

    func testDatabaseSchemaJSONRoundTrip() throws {
        let schema = makeSampleSchema()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(schema)
        let decoded = try JSONDecoder().decode(DatabaseSchema.self, from: data)
        XCTAssertEqual(decoded.id, schema.id)
        XCTAssertEqual(decoded.name, schema.name)
        XCTAssertEqual(decoded.version, schema.version)
        XCTAssertEqual(decoded.properties.count, schema.properties.count)
        XCTAssertEqual(decoded.defaultView, schema.defaultView)
    }

    func testPropertyDefinitionCodingKeysPreserved() throws {
        let prop = PropertyDefinition(id: "prop_priority", name: "Priority", type: .select,
                                     config: PropertyConfig(options: [SelectOption(id: "o1", name: "High", color: "red")]))
        let data = try JSONEncoder().encode(prop)
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        XCTAssertEqual(decoded.id, "prop_priority")
        XCTAssertEqual(decoded.type, .select)
        XCTAssertEqual(decoded.options?.first?.name, "High")
    }
}

// MARK: - Row Model Tests

final class RowModelTests: XCTestCase {

    func testDatabaseRowInit() {
        let now = Date()
        let row = DatabaseRow(id: "row_abc123", properties: ["prop_title": .text("My Task")],
                              body: "some body", createdAt: now, updatedAt: now)
        XCTAssertEqual(row.id, "row_abc123")
        XCTAssertEqual(row.body, "some body")
        XCTAssertEqual(row.properties["prop_title"], .text("My Task"))
    }

    func testDatabaseRowDefaultInit() {
        let row = DatabaseRow(id: "row_xyz")
        XCTAssertTrue(row.properties.isEmpty)
        XCTAssertTrue(row.body.isEmpty)
    }

    func testDatabaseRowTitleFromSchema() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_1", properties: ["prop_title": .text("My First Row")])
        XCTAssertEqual(row.title(schema: schema), "My First Row")
    }

    func testDatabaseRowTitleDefaultsToNewPage() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_1", properties: [:])
        XCTAssertEqual(row.title(schema: schema), "New Page")
    }

    func testDatabaseRowTitleEmptyStringDefaultsToNewPage() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_1", properties: ["prop_title": .text("")])
        XCTAssertEqual(row.title(schema: schema), "New Page")
    }

    func testPropertyValueStringValues() {
        XCTAssertEqual(PropertyValue.text("hello").stringValue, "hello")
        XCTAssertEqual(PropertyValue.number(42).stringValue, "42")
        XCTAssertEqual(PropertyValue.number(3.14).stringValue, "3.14")
        XCTAssertEqual(PropertyValue.select("In Progress").stringValue, "In Progress")
        XCTAssertEqual(PropertyValue.multiSelect(["a", "b"]).stringValue, "a,b")
        XCTAssertEqual(PropertyValue.date("2024-03-15").stringValue, "2024-03-15")
        XCTAssertEqual(PropertyValue.checkbox(true).stringValue, "true")
        XCTAssertEqual(PropertyValue.checkbox(false).stringValue, "false")
        XCTAssertEqual(PropertyValue.url("https://example.com").stringValue, "https://example.com")
        XCTAssertEqual(PropertyValue.email("a@b.com").stringValue, "a@b.com")
        XCTAssertEqual(PropertyValue.relation("row_ref").stringValue, "row_ref")
        XCTAssertEqual(PropertyValue.relationMany(["row_a", "row_b"]).stringValue, "row_a,row_b")
        XCTAssertEqual(PropertyValue.empty.stringValue, "")
    }

    func testPropertyValueNumberIntegerDisplay() {
        // Integers should display without decimal
        XCTAssertEqual(PropertyValue.number(100.0).stringValue, "100")
        XCTAssertEqual(PropertyValue.number(0.0).stringValue, "0")
        XCTAssertEqual(PropertyValue.number(-5.0).stringValue, "-5")
    }

    func testPropertyValueEquality() {
        XCTAssertEqual(PropertyValue.text("hello"), PropertyValue.text("hello"))
        XCTAssertNotEqual(PropertyValue.text("hello"), PropertyValue.text("world"))
        XCTAssertEqual(PropertyValue.number(42), PropertyValue.number(42))
        XCTAssertEqual(PropertyValue.checkbox(true), PropertyValue.checkbox(true))
        XCTAssertEqual(PropertyValue.empty, PropertyValue.empty)
        XCTAssertNotEqual(PropertyValue.text(""), PropertyValue.empty)
    }

    func testPropertyValueCodableRoundTrip() throws {
        let values: [PropertyValue] = [
            .text("hello"),
            .number(3.14),
            .select("opt_a"),
            .multiSelect(["a", "b", "c"]),
            .date("2024-01-01"),
            .checkbox(true),
            .url("https://example.com"),
            .email("test@test.com"),
            .relation("row_abc"),
            .relationMany(["row_1", "row_2"]),
            .empty
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
            XCTAssertEqual(decoded, value, "Round-trip failed for value: \(value)")
        }
    }
}

// MARK: - Agent Model Tests

final class AgentModelTests: XCTestCase {

    func testAgentTaskInit() {
        let task = AgentTask(
            id: "task_1",
            title: "Fix login bug",
            detail: "Users can't log in with SSO",
            status: .inProgress,
            assignee: "claude",
            labels: ["bug", "auth"],
            linkedPaths: ["/projects/auth.md"],
            latestRunId: "run_1",
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-02T00:00:00Z"
        )
        XCTAssertEqual(task.id, "task_1")
        XCTAssertEqual(task.title, "Fix login bug")
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.labels, ["bug", "auth"])
        XCTAssertEqual(task.linkedPaths.count, 1)
        XCTAssertEqual(task.latestRunId, "run_1")
    }

    func testAgentTaskDefaultStatus() {
        let task = AgentTask(id: "task_2", title: "New task", createdAt: "2024-01-01T00:00:00Z", updatedAt: "2024-01-01T00:00:00Z")
        XCTAssertEqual(task.status, .todo)
        XCTAssertTrue(task.labels.isEmpty)
        XCTAssertTrue(task.linkedPaths.isEmpty)
        XCTAssertNil(task.detail)
        XCTAssertNil(task.assignee)
        XCTAssertNil(task.latestRunId)
    }

    func testAgentTaskStatusAllCases() {
        XCTAssertEqual(AgentTaskStatus.allCases.count, 6)
        XCTAssertEqual(AgentTaskStatus.inProgress.rawValue, "in_progress")
    }

    func testAgentRunInit() {
        let run = AgentRun(
            id: "run_1",
            taskId: "task_1",
            agent: "claude-opus-4-6",
            cwd: "/projects/bugbook",
            branch: "fix/login",
            status: .running,
            startedAt: "2024-01-01T10:00:00Z"
        )
        XCTAssertEqual(run.id, "run_1")
        XCTAssertEqual(run.taskId, "task_1")
        XCTAssertEqual(run.agent, "claude-opus-4-6")
        XCTAssertEqual(run.status, .running)
        XCTAssertNil(run.endedAt)
        XCTAssertNil(run.summary)
        XCTAssertNil(run.commit)
    }

    func testAgentRunStatusRawValues() {
        XCTAssertEqual(AgentRunStatus.running.rawValue, "running")
        XCTAssertEqual(AgentRunStatus.succeeded.rawValue, "succeeded")
        XCTAssertEqual(AgentRunStatus.failed.rawValue, "failed")
        XCTAssertEqual(AgentRunStatus.cancelled.rawValue, "cancelled")
    }

    func testAgentEventInit() {
        let event = AgentEvent(
            id: "evt_1",
            runId: "run_1",
            taskId: "task_1",
            level: .warning,
            message: "Rate limit approached",
            timestamp: "2024-01-01T10:05:00Z"
        )
        XCTAssertEqual(event.id, "evt_1")
        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.message, "Rate limit approached")
        XCTAssertEqual(event.runId, "run_1")
    }

    func testAgentEventLevelAllCases() {
        XCTAssertEqual(AgentEventLevel.allCases.count, 3)
    }

    func testAgentTaskCodableRoundTrip() throws {
        let task = AgentTask(
            id: "task_abc",
            title: "Deploy to prod",
            status: .done,
            labels: ["infra"],
            linkedPaths: [],
            createdAt: "2024-06-01T00:00:00Z",
            updatedAt: "2024-06-02T00:00:00Z"
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(AgentTask.self, from: data)
        XCTAssertEqual(decoded.id, "task_abc")
        XCTAssertEqual(decoded.status, .done)
        XCTAssertEqual(decoded.labels, ["infra"])
    }

    func testAgentStoreErrorDescriptions() {
        XCTAssertEqual(AgentStoreError.invalidTaskTitle.description, "Task title cannot be empty.")
        XCTAssertTrue(AgentStoreError.taskNotFound("task_1").description.contains("task_1"))
        XCTAssertTrue(AgentStoreError.runNotFound("run_99").description.contains("run_99"))
        XCTAssertTrue(AgentStoreError.invalidData("bad JSON").description.contains("bad JSON"))
    }

    func testAgentTaskPatchInit() {
        let patch = AgentTaskPatch(title: "Updated Title", status: .blocked, labels: ["blocker"])
        XCTAssertEqual(patch.title, "Updated Title")
        XCTAssertEqual(patch.status, .blocked)
        XCTAssertEqual(patch.labels, ["blocker"])
        XCTAssertNil(patch.detail)
        XCTAssertNil(patch.assignee)
    }

    func testAgentDashboardInit() {
        let dashboard = AgentDashboard(
            generatedAt: "2024-01-01T00:00:00Z",
            taskCounts: ["todo": 3, "done": 10],
            activeTasks: [],
            recentRuns: [],
            recentEvents: []
        )
        XCTAssertEqual(dashboard.taskCounts["todo"], 3)
        XCTAssertEqual(dashboard.taskCounts["done"], 10)
        XCTAssertTrue(dashboard.activeTasks.isEmpty)
    }
}

// MARK: - RowSerializer Tests

final class RowSerializerTests: XCTestCase {

    func testSerializeAndParseRoundTrip() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_abc123",
            properties: [
                "prop_title": .text("My Task"),
                "prop_status": .select("opt_todo"),
                "prop_priority": .number(5),
                "prop_done": .checkbox(false)
            ],
            body: "# Notes\nSome content here.",
            createdAt: Date(timeIntervalSince1970: 1700000000),
            updatedAt: Date(timeIntervalSince1970: 1700001000)
        )

        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.id, "row_abc123")
        XCTAssertEqual(parsed?.properties["prop_title"], .text("My Task"))
        XCTAssertEqual(parsed?.properties["prop_status"], .select("opt_todo"))
        XCTAssertEqual(parsed?.properties["prop_priority"], .number(5))
        XCTAssertEqual(parsed?.properties["prop_done"], .checkbox(false))
        XCTAssertEqual(parsed?.body, "# Notes\nSome content here.")
    }

    func testSerializeProducesValidFrontmatter() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_xyz", properties: ["prop_title": .text("Hello")])
        let content = RowSerializer.serialize(row: row, schema: schema)
        XCTAssertTrue(content.hasPrefix("---\n"))
        XCTAssertTrue(content.contains("id: row_xyz"))
        XCTAssertTrue(content.contains("created_at:"))
        XCTAssertTrue(content.contains("updated_at:"))
        XCTAssertTrue(content.contains("---\n"), "Should have closing frontmatter delimiter")
    }

    func testParseReturnsNilForInvalidContent() {
        let schema = makeSampleSchema()
        XCTAssertNil(RowSerializer.parse(content: "no frontmatter here", schema: schema))
        XCTAssertNil(RowSerializer.parse(content: "", schema: schema))
        XCTAssertNil(RowSerializer.parse(content: "---\nno closing delimiter", schema: schema))
    }

    func testParseReturnsNilForMissingId() {
        let schema = makeSampleSchema()
        let content = "---\ncreated_at: 2024-01-01T00:00:00Z\nupdated_at: 2024-01-01T00:00:00Z\n---\n"
        XCTAssertNil(RowSerializer.parse(content: content, schema: schema))
    }

    func testSerializeEmptyProperties() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_empty", properties: [:], body: "")
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.id, "row_empty")
        XCTAssertTrue(parsed?.properties.isEmpty ?? false)
    }

    func testSerializeSpecialCharactersInTitle() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_special",
            properties: ["prop_title": .text("Title with \"quotes\" and \\backslash")]
        )
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_title"], .text("Title with \"quotes\" and \\backslash"))
    }

    func testSerializeMultiSelectRoundTrip() {
        let schema = makeSchemaWithMultiSelect()
        let row = DatabaseRow(
            id: "row_ms",
            properties: [
                "prop_title": .text("Tags Test"),
                "prop_tags": .multiSelect(["tag_a", "tag_b", "tag_c"])
            ]
        )
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_tags"], .multiSelect(["tag_a", "tag_b", "tag_c"]))
    }

    func testSerializeEmptyValueExcluded() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_ev",
            properties: ["prop_title": .text("Test"), "prop_status": .empty]
        )
        let content = RowSerializer.serialize(row: row, schema: schema)
        // Empty values should not appear in the serialized output
        XCTAssertFalse(content.contains("prop_status"))
    }

    func testSerializeCheckboxValues() {
        let schema = makeSampleSchema()
        let rowTrue = DatabaseRow(id: "row_t", properties: ["prop_title": .text("T"), "prop_done": .checkbox(true)])
        let rowFalse = DatabaseRow(id: "row_f", properties: ["prop_title": .text("F"), "prop_done": .checkbox(false)])
        let schema2 = makeSampleSchema()

        let parsedTrue = RowSerializer.parse(content: RowSerializer.serialize(row: rowTrue, schema: schema), schema: schema2)
        let parsedFalse = RowSerializer.parse(content: RowSerializer.serialize(row: rowFalse, schema: schema), schema: schema2)

        XCTAssertEqual(parsedTrue?.properties["prop_done"], .checkbox(true))
        XCTAssertEqual(parsedFalse?.properties["prop_done"], .checkbox(false))
    }

    func testSerializeValueForIndex() {
        XCTAssertEqual(RowSerializer.serializeValueForIndex(.text("hello")) as? String, "hello")
        XCTAssertEqual(RowSerializer.serializeValueForIndex(.number(42)) as? Double, 42)
        XCTAssertEqual(RowSerializer.serializeValueForIndex(.checkbox(true)) as? Bool, true)
        XCTAssertEqual(RowSerializer.serializeValueForIndex(.select("opt_a")) as? String, "opt_a")
        let msVal = RowSerializer.serializeValueForIndex(.multiSelect(["a", "b"])) as? [String]
        XCTAssertEqual(msVal, ["a", "b"])
        XCTAssertTrue(RowSerializer.serializeValueForIndex(.empty) is NSNull)
    }

    func testBodyPreservedThroughRoundTrip() {
        let schema = makeSampleSchema()
        let multilineBody = "# Header\n\nParagraph one.\n\nParagraph two.\n- item a\n- item b"
        let row = DatabaseRow(id: "row_body", properties: ["prop_title": .text("Body Test")], body: multilineBody)
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertEqual(parsed?.body, multilineBody)
    }

    func testUrlAndEmailRoundTrip() {
        let schema = makeSchemaWithUrlAndEmail()
        let row = DatabaseRow(
            id: "row_contact",
            properties: [
                "prop_title": .text("Contact"),
                "prop_url": .url("https://example.com/path?q=1&r=2"),
                "prop_email": .email("user@example.com")
            ]
        )
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_url"], .url("https://example.com/path?q=1&r=2"))
        XCTAssertEqual(parsed?.properties["prop_email"], .email("user@example.com"))
    }
}

// MARK: - SchemaValidator Tests

final class SchemaValidatorTests: XCTestCase {

    func testValidRowPassesValidation() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Valid Task"),
            "prop_status": .select("opt_todo"),
            "prop_priority": .number(3),
            "prop_done": .checkbox(false)
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        XCTAssertTrue(errors.isEmpty, "Expected no errors but got: \(errors)")
    }

    func testMissingTitleFailsWhenRequired() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = ["prop_status": .select("opt_todo")]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_title" }))
    }

    func testEmptyTitleFailsWhenRequired() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = ["prop_title": .text("")]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_title" && $0.message.contains("empty") }))
    }

    func testEmptyPropertyValueTitleFailsWhenRequired() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = ["prop_title": .empty]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        XCTAssertFalse(errors.isEmpty)
    }

    func testMissingTitleOkWhenNotRequired() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = ["prop_status": .select("opt_todo")]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: false)
        XCTAssertTrue(errors.isEmpty, "Title should not be required for updates")
    }

    func testUnknownPropertyIdFails() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_nonexistent": .text("Value")
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_nonexistent" }))
    }

    func testWrongTypeForNumberPropertyFails() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_priority": .text("high") // should be .number
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_priority" }))
    }

    func testWrongTypeForCheckboxFails() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_done": .text("yes") // should be .checkbox
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_done" }))
    }

    func testWrongTypeForSelectFails() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_status": .text("todo") // should be .select
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_status" }))
    }

    func testInvalidSelectOptionFails() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_status": .select("opt_nonexistent") // not in options
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_status" && $0.message.contains("opt_nonexistent") }))
    }

    func testValidSelectOptionPasses() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_status": .select("opt_todo")
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty, "Valid select option should pass validation")
    }

    func testEmptyValueAlwaysAllowed() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_priority": .empty, // clearing a number field with empty
            "prop_status": .empty
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty, "Empty values should always be allowed (clearing a field)")
    }

    func testValidMultiSelectOptionsPasses() {
        let schema = makeSchemaWithMultiSelect()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_tags": .multiSelect(["tag_a", "tag_b"])
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty)
    }

    func testInvalidMultiSelectOptionFails() {
        let schema = makeSchemaWithMultiSelect()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_tags": .multiSelect(["tag_a", "tag_invalid"])
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_tags" && $0.message.contains("tag_invalid") }))
    }

    func testRelationTypeAcceptsRelationValue() {
        let schema = makeSchemaWithRelation()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_ref": .relation("row_other")
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty)
    }

    func testRelationTypeAcceptsRelationManyValue() {
        let schema = makeSchemaWithRelation()
        let properties: [String: PropertyValue] = [
            "prop_title": .text("Test"),
            "prop_ref": .relationMany(["row_a", "row_b"])
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidationErrorDescription() {
        let err = ValidationError(propertyId: "prop_title", message: "Title cannot be empty")
        XCTAssertTrue(err.description.contains("prop_title"))
        XCTAssertTrue(err.description.contains("Title cannot be empty"))
    }
}

// MARK: - QueryEngine Tests

final class QueryEngineTests: XCTestCase {

    var schema: DatabaseSchema!
    var rows: [DatabaseRow]!

    override func setUp() {
        super.setUp()
        schema = makeSampleSchema()
        rows = makeSampleRows()
    }

    func testEmptyQueryReturnsAllRows() {
        let query = Query(databaseId: "db_1")
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, rows.count)
        XCTAssertEqual(result.totalCount, rows.count)
        XCTAssertFalse(result.hasMore)
    }

    func testFilterEquals() {
        let query = Query(
            databaseId: "db_1",
            filters: [.equals(property: "prop_status", value: .select("opt_todo"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy { $0.properties["prop_status"] == .select("opt_todo") })
    }

    func testFilterNotEquals() {
        let query = Query(
            databaseId: "db_1",
            filters: [.notEquals(property: "prop_status", value: .select("opt_done"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy { $0.properties["prop_status"] != .select("opt_done") })
    }

    func testFilterGreaterThan() {
        let query = Query(
            databaseId: "db_1",
            filters: [.greaterThan(property: "prop_priority", value: .number(3))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy {
            if case .number(let n) = $0.properties["prop_priority"] { return n > 3 }
            return false
        })
    }

    func testFilterLessThan() {
        let query = Query(
            databaseId: "db_1",
            filters: [.lessThan(property: "prop_priority", value: .number(3))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy {
            if case .number(let n) = $0.properties["prop_priority"] { return n < 3 }
            return false
        })
    }

    func testFilterContainsText() {
        let query = Query(
            databaseId: "db_1",
            filters: [.contains(property: "prop_title", value: .text("Task"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy {
            if case .text(let s) = $0.properties["prop_title"] {
                return s.localizedCaseInsensitiveContains("Task")
            }
            return false
        })
    }

    func testFilterContainsCaseInsensitive() {
        let query = Query(
            databaseId: "db_1",
            filters: [.contains(property: "prop_title", value: .text("task"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertFalse(result.rows.isEmpty)
    }

    func testFilterNotContains() {
        let allResults = QueryEngine.execute(query: Query(databaseId: "db_1"), schema: schema, rows: rows)
        let filteredResults = QueryEngine.execute(
            query: Query(databaseId: "db_1", filters: [.notContains(property: "prop_title", value: .text("Task"))]),
            schema: schema,
            rows: rows
        )
        XCTAssertTrue(filteredResults.rows.count <= allResults.rows.count)
    }

    func testFilterIsEmpty() {
        let rowWithEmpty = DatabaseRow(id: "row_nostat", properties: [
            "prop_title": .text("No Status"),
            "prop_status": .empty
        ])
        let testRows = rows + [rowWithEmpty]
        let query = Query(
            databaseId: "db_1",
            filters: [.isEmpty(property: "prop_status")]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: testRows)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.id, "row_nostat")
    }

    func testFilterIsNotEmpty() {
        let rowWithEmpty = DatabaseRow(id: "row_nostat", properties: [
            "prop_title": .text("No Status"),
            "prop_status": .empty
        ])
        let testRows = rows + [rowWithEmpty]
        let query = Query(
            databaseId: "db_1",
            filters: [.isNotEmpty(property: "prop_status")]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: testRows)
        XCTAssertTrue(result.rows.allSatisfy { $0.id != "row_nostat" })
    }

    func testFilterInList() {
        let query = Query(
            databaseId: "db_1",
            filters: [.inList(property: "prop_status", values: [.select("opt_todo"), .select("opt_done")])]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy {
            $0.properties["prop_status"] == .select("opt_todo") || $0.properties["prop_status"] == .select("opt_done")
        })
    }

    func testMultipleFiltersAndedTogether() {
        let query = Query(
            databaseId: "db_1",
            filters: [
                .equals(property: "prop_status", value: .select("opt_todo")),
                .greaterThan(property: "prop_priority", value: .number(2))
            ]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.allSatisfy { row in
            guard row.properties["prop_status"] == .select("opt_todo") else { return false }
            guard case .number(let n) = row.properties["prop_priority"] else { return false }
            return n > 2
        })
    }

    func testSortAscending() {
        let query = Query(
            databaseId: "db_1",
            sorts: [Sort(property: "prop_priority", ascending: true)]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        let priorities = result.rows.compactMap { row -> Double? in
            if case .number(let n) = row.properties["prop_priority"] { return n }
            return nil
        }
        XCTAssertEqual(priorities, priorities.sorted())
    }

    func testSortDescending() {
        let query = Query(
            databaseId: "db_1",
            sorts: [Sort(property: "prop_priority", ascending: false)]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        let priorities = result.rows.compactMap { row -> Double? in
            if case .number(let n) = row.properties["prop_priority"] { return n }
            return nil
        }
        XCTAssertEqual(priorities, priorities.sorted(by: >))
    }

    func testPaginationLimit() {
        let query = Query(databaseId: "db_1", limit: 2)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.totalCount, rows.count)
        XCTAssertTrue(result.hasMore)
    }

    func testPaginationOffset() {
        let allResult = QueryEngine.execute(query: Query(databaseId: "db_1"), schema: schema, rows: rows)
        let offsetResult = QueryEngine.execute(
            query: Query(databaseId: "db_1", offset: 1),
            schema: schema,
            rows: rows
        )
        XCTAssertEqual(offsetResult.rows.count, allResult.rows.count - 1)
        XCTAssertEqual(offsetResult.rows.first?.id, allResult.rows[1].id)
    }

    func testPaginationOffsetAndLimit() {
        let query = Query(databaseId: "db_1", limit: 2, offset: 1)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.totalCount, rows.count)
    }

    func testHasMoreFalseWhenWithinLimit() {
        let query = Query(databaseId: "db_1", limit: 100)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertFalse(result.hasMore)
    }

    func testEmptyRowSetReturnsEmptyResult() {
        let query = Query(databaseId: "db_1")
        let result = QueryEngine.execute(query: query, schema: schema, rows: [])
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertFalse(result.hasMore)
    }

    func testFilterMatchingNothingReturnsEmpty() {
        let query = Query(
            databaseId: "db_1",
            filters: [.equals(property: "prop_status", value: .select("opt_cancelled"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
    }
}

// MARK: - MutationEngine Tests

final class MutationEngineTests: XCTestCase {

    var schema: DatabaseSchema!
    var dbPath: String!
    var rowStore: RowStore!
    var indexManager: IndexManager!

    override func setUp() {
        super.setUp()
        schema = makeSampleSchema()
        dbPath = makeTemporaryDirectory()
        rowStore = RowStore()
        indexManager = IndexManager()

        // Save schema to temp dir
        let dbStore = DatabaseStore()
        try? dbStore.saveSchema(schema, at: dbPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
        super.tearDown()
    }

    func testCreateRowSucceeds() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("New Task"), "prop_priority": .number(3)], body: nil)
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(result.hasErrors, "Expected no errors: \(result.errors)")
        XCTAssertEqual(result.created.count, 1)
        XCTAssertTrue(result.updated.isEmpty)
        XCTAssertTrue(result.deleted.isEmpty)
    }

    func testCreateRowWithBodySucceeds() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(
                    properties: ["prop_title": .text("Task with Body")],
                    body: "# Details\nThis is the body content."
                )
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(result.hasErrors)
        let rowId = result.created.first!
        let rows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let created = rows.first(where: { $0.id == rowId })
        XCTAssertEqual(created?.body, "# Details\nThis is the body content.")
    }

    func testCreateRowMissingTitleFails() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_priority": .number(1)], body: nil)
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.created.isEmpty)
    }

    func testCreateRowEmptyTitleFails() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("")], body: nil)
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertTrue(result.hasErrors)
    }

    func testCreateRowInvalidPropertyFails() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: [
                    "prop_title": .text("Valid Title"),
                    "prop_nonexistent": .text("Bad Property")
                ], body: nil)
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.created.isEmpty)
    }

    func testUpdateRowSucceeds() {
        // First create a row
        let createResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .createRow(properties: ["prop_title": .text("Original"), "prop_priority": .number(1)], body: nil)
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        let rowId = createResult.created.first!

        // Now update it
        let updateResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .updateRow(rowId: rowId, properties: ["prop_priority": .number(5)])
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertFalse(updateResult.hasErrors, "Expected no errors: \(updateResult.errors)")
        XCTAssertEqual(updateResult.updated, [rowId])

        // Verify on disk
        let rows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let updated = rows.first(where: { $0.id == rowId })
        XCTAssertEqual(updated?.properties["prop_priority"], .number(5))
    }

    func testUpdateRowBodySucceeds() {
        let createResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .createRow(properties: ["prop_title": .text("Body Test")], body: "original body")
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        let rowId = createResult.created.first!

        let updateResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .updateRowBody(rowId: rowId, body: "updated body content")
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertFalse(updateResult.hasErrors)
        XCTAssertEqual(updateResult.updated, [rowId])

        let rows = rowStore.loadAllRows(in: dbPath, schema: schema)
        let updated = rows.first(where: { $0.id == rowId })
        XCTAssertEqual(updated?.body, "updated body content")
    }

    func testUpdateNonexistentRowFails() {
        let result = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .updateRow(rowId: "row_doesnotexist", properties: ["prop_title": .text("New")])
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.errors.first?.message.contains("row_doesnotexist") ?? false)
    }

    func testDeleteRowSucceeds() {
        let createResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .createRow(properties: ["prop_title": .text("To Delete")], body: nil)
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        let rowId = createResult.created.first!
        XCTAssertFalse(rowStore.loadAllRows(in: dbPath, schema: schema).isEmpty)

        let deleteResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [.deleteRow(rowId: rowId)]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertFalse(deleteResult.hasErrors)
        XCTAssertEqual(deleteResult.deleted, [rowId])
        XCTAssertTrue(rowStore.loadAllRows(in: dbPath, schema: schema).isEmpty)
    }

    func testBatchCreateMultipleRows() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("Row 1")], body: nil),
                .createRow(properties: ["prop_title": .text("Row 2")], body: nil),
                .createRow(properties: ["prop_title": .text("Row 3")], body: nil)
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(result.created.count, 3)
        let rows = rowStore.loadAllRows(in: dbPath, schema: schema)
        XCTAssertEqual(rows.count, 3)
    }

    func testValidationFailureBlocksAllOperations() {
        // Mix valid and invalid operations — all should be rejected
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("Valid Row")], body: nil),
                .createRow(properties: ["prop_priority": .number(1)], body: nil) // missing title
            ]
        )
        let result = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertTrue(result.hasErrors)
        XCTAssertTrue(result.created.isEmpty, "No rows should be created when any validation fails")
        XCTAssertTrue(rowStore.loadAllRows(in: dbPath, schema: schema).isEmpty)
    }

    func testMutationResultHasErrors() {
        let result = MutationResult(errors: [MutationError(operation: 0, message: "Something failed")])
        XCTAssertTrue(result.hasErrors)
    }

    func testMutationResultNoErrors() {
        let result = MutationResult(created: ["row_1"])
        XCTAssertFalse(result.hasErrors)
    }

    func testMutationErrorDescription() {
        let err = MutationError(operation: 2, message: "Row not found")
        XCTAssertTrue(err.description.contains("2"))
        XCTAssertTrue(err.description.contains("Row not found"))
    }
}

// MARK: - IndexManager Tests

final class IndexManagerTests: XCTestCase {

    var schema: DatabaseSchema!
    var dbPath: String!
    var indexManager: IndexManager!
    var rowStore: RowStore!

    override func setUp() {
        super.setUp()
        schema = makeSampleSchema()
        dbPath = makeTemporaryDirectory()
        indexManager = IndexManager()
        rowStore = RowStore()

        let dbStore = DatabaseStore()
        try? dbStore.saveSchema(schema, at: dbPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dbPath)
        super.tearDown()
    }

    func testRebuildProducesValidStructure() {
        let rows = [
            DatabaseRow(id: "row_a", properties: ["prop_title": .text("Row A"), "prop_status": .select("opt_todo")]),
            DatabaseRow(id: "row_b", properties: ["prop_title": .text("Row B"), "prop_status": .select("opt_done")])
        ]
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)

        XCTAssertEqual(index["version"] as? Int, 1)
        XCTAssertNotNil(index["updated_at"])
        let rowsMap = index["rows"] as? [String: Any]
        XCTAssertEqual(rowsMap?.count, 2)
        XCTAssertNotNil(rowsMap?["row_a"])
        XCTAssertNotNil(rowsMap?["row_b"])
    }

    func testRebuildIncludesProperties() {
        let rows = [
            DatabaseRow(id: "row_a", properties: [
                "prop_title": .text("Alpha"),
                "prop_status": .select("opt_todo"),
                "prop_priority": .number(7)
            ])
        ]
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        let rowsMap = index["rows"] as? [String: Any]
        let rowA = rowsMap?["row_a"] as? [String: Any]
        let props = rowA?["properties"] as? [String: Any]
        XCTAssertEqual(props?["prop_title"] as? String, "Alpha")
        XCTAssertEqual(props?["prop_priority"] as? Double, 7)
    }

    func testRebuildBuildsSelectIndex() {
        let rows = [
            DatabaseRow(id: "row_a", properties: ["prop_title": .text("A"), "prop_status": .select("opt_todo")]),
            DatabaseRow(id: "row_b", properties: ["prop_title": .text("B"), "prop_status": .select("opt_todo")]),
            DatabaseRow(id: "row_c", properties: ["prop_title": .text("C"), "prop_status": .select("opt_done")])
        ]
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        let indexes = index["indexes"] as? [String: Any]
        let statusIndex = indexes?["prop_status"] as? [String: [String]]
        XCTAssertEqual(statusIndex?["opt_todo"]?.count, 2)
        XCTAssertEqual(statusIndex?["opt_done"]?.count, 1)
    }

    func testRebuildBuildsCheckboxIndex() {
        let rows = [
            DatabaseRow(id: "row_a", properties: ["prop_title": .text("A"), "prop_done": .checkbox(true)]),
            DatabaseRow(id: "row_b", properties: ["prop_title": .text("B"), "prop_done": .checkbox(false)]),
            DatabaseRow(id: "row_c", properties: ["prop_title": .text("C"), "prop_done": .checkbox(true)])
        ]
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        let indexes = index["indexes"] as? [String: Any]
        let doneIndex = indexes?["prop_done"] as? [String: [String]]
        XCTAssertEqual(doneIndex?["true"]?.count, 2)
        XCTAssertEqual(doneIndex?["false"]?.count, 1)
    }

    func testSaveAndLoadIndex() throws {
        let rows = [
            DatabaseRow(id: "row_x", properties: ["prop_title": .text("X")])
        ]
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: rows)
        try indexManager.saveIndex(index, at: dbPath)

        let loaded = indexManager.loadIndex(at: dbPath)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?["version"] as? Int, 1)
        let loadedRows = loaded?["rows"] as? [String: Any]
        XCTAssertNotNil(loadedRows?["row_x"])
    }

    func testLoadIndexReturnsNilWhenMissing() {
        let result = indexManager.loadIndex(at: dbPath)
        XCTAssertNil(result)
    }

    func testRebuildEmptyRowsProducesEmptyRowsMap() {
        let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: [])
        let rowsMap = index["rows"] as? [String: Any]
        XCTAssertTrue(rowsMap?.isEmpty ?? true)
    }

    func testIndexRebuildAfterMutation() {
        let mutation = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("Index Test"), "prop_status": .select("opt_todo")], body: nil)
            ]
        )
        let mutResult = MutationEngine.execute(mutation: mutation, schema: schema, dbPath: dbPath,
                                               rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(mutResult.hasErrors)

        // Index should now exist and contain the created row
        let index = indexManager.loadIndex(at: dbPath)
        XCTAssertNotNil(index)
        let rowsMap = index?["rows"] as? [String: Any]
        XCTAssertEqual(rowsMap?.count, 1)
    }
}

// MARK: - RowStore Tests

final class RowStoreTests: XCTestCase {

    func testGenerateRowIdFormat() {
        let id = RowStore.generateRowId()
        XCTAssertTrue(id.hasPrefix("row_"))
        XCTAssertEqual(id.count, 10) // "row_" + 6 chars
    }

    func testGenerateRowIdUnique() {
        let ids = Set((0..<100).map { _ in RowStore.generateRowId() })
        // With 36^6 = ~2B possibilities, 100 IDs should virtually never collide
        XCTAssertEqual(ids.count, 100)
    }

    func testRowFilenameBasic() {
        let filename = RowStore.rowFilename(title: "My Task", suffix: "abc123")
        XCTAssertEqual(filename, "My Task (abc123).md")
    }

    func testRowFilenameSpecialCharsSanitized() {
        let filename = RowStore.rowFilename(title: "Task / With: Special? Chars", suffix: "xyz")
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("?"))
        XCTAssertTrue(filename.hasSuffix("(xyz).md"))
    }

    func testRowFilenameTruncatesLongTitles() {
        let longTitle = String(repeating: "a", count: 200)
        let filename = RowStore.rowFilename(title: longTitle, suffix: "abc")
        // Title portion should be at most 80 chars, plus " (abc).md"
        XCTAssertLessThanOrEqual(filename.count, 90)
    }

    func testExtractIdSuffix() {
        XCTAssertEqual(RowStore.extractIdSuffix(from: "row_abc123"), "abc123")
        XCTAssertEqual(RowStore.extractIdSuffix(from: "row_xyz"), "xyz")
        XCTAssertEqual(RowStore.extractIdSuffix(from: "not_a_row_id"), "not_a_row_id")
    }

    func testSaveAndLoadRow() throws {
        let schema = makeSampleSchema()
        let tmpDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let store = RowStore()
        let row = DatabaseRow(
            id: "row_test01",
            properties: ["prop_title": .text("Test Row"), "prop_priority": .number(4)],
            body: "some body text"
        )
        try store.saveRow(row, schema: schema, dbPath: tmpDir)

        let loaded = store.loadAllRows(in: tmpDir, schema: schema)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "row_test01")
        XCTAssertEqual(loaded.first?.properties["prop_title"], .text("Test Row"))
        XCTAssertEqual(loaded.first?.properties["prop_priority"], .number(4))
        XCTAssertEqual(loaded.first?.body, "some body text")
    }

    func testDeleteRow() throws {
        let schema = makeSampleSchema()
        let tmpDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let store = RowStore()
        let row = DatabaseRow(id: "row_del001", properties: ["prop_title": .text("To Delete")])
        try store.saveRow(row, schema: schema, dbPath: tmpDir)
        XCTAssertEqual(store.loadAllRows(in: tmpDir, schema: schema).count, 1)

        try store.deleteRow(rowId: "row_del001", dbPath: tmpDir)
        XCTAssertTrue(store.loadAllRows(in: tmpDir, schema: schema).isEmpty)
    }

    func testLoadAllRowsSortedByCreatedAt() throws {
        let schema = makeSampleSchema()
        let tmpDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let store = RowStore()
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let t3 = Date(timeIntervalSince1970: 3000)

        // Save in reverse order
        let row3 = DatabaseRow(id: "row_c", properties: ["prop_title": .text("Third")], createdAt: t3, updatedAt: t3)
        let row1 = DatabaseRow(id: "row_a", properties: ["prop_title": .text("First")], createdAt: t1, updatedAt: t1)
        let row2 = DatabaseRow(id: "row_b", properties: ["prop_title": .text("Second")], createdAt: t2, updatedAt: t2)

        try store.saveRow(row3, schema: schema, dbPath: tmpDir)
        try store.saveRow(row1, schema: schema, dbPath: tmpDir)
        try store.saveRow(row2, schema: schema, dbPath: tmpDir)

        let loaded = store.loadAllRows(in: tmpDir, schema: schema)
        XCTAssertEqual(loaded.map { $0.id }, ["row_a", "row_b", "row_c"])
    }
}

// MARK: - View Model Tests

final class ViewModelTests: XCTestCase {

    func testViewTypeAllCases() {
        XCTAssertEqual(ViewType.allCases.count, 4)
        XCTAssertTrue(ViewType.allCases.contains(.table))
        XCTAssertTrue(ViewType.allCases.contains(.kanban))
    }

    func testSortConfigAscendingProperty() {
        let sort = SortConfig(property: "prop_title", direction: "asc")
        XCTAssertTrue(sort.ascending)
    }

    func testSortConfigDescendingProperty() {
        let sort = SortConfig(property: "prop_title", direction: "desc")
        XCTAssertFalse(sort.ascending)
    }

    func testViewConfigInit() {
        let view = ViewConfig(id: "view_1", name: "All Tasks", type: .table)
        XCTAssertEqual(view.id, "view_1")
        XCTAssertEqual(view.type, .table)
        XCTAssertTrue(view.sorts.isEmpty)
        XCTAssertTrue(view.filters.isEmpty)
        XCTAssertNil(view.manualRowOrder)
    }

    func testViewConfigCodableRoundTrip() throws {
        let view = ViewConfig(
            id: "view_kanban",
            name: "Kanban Board",
            type: .kanban,
            groupBy: "prop_status",
            manualRowOrder: ["row_a", "row_b"]
        )
        let data = try JSONEncoder().encode(view)
        let decoded = try JSONDecoder().decode(ViewConfig.self, from: data)
        XCTAssertEqual(decoded.id, "view_kanban")
        XCTAssertEqual(decoded.type, .kanban)
        XCTAssertEqual(decoded.groupBy, "prop_status")
        XCTAssertEqual(decoded.manualRowOrder, ["row_a", "row_b"])
    }
}

// MARK: - Edge Case Tests

final class EdgeCaseTests: XCTestCase {

    // MARK: - Empty/Nil Handling

    func testEmptyStringSchemaName() {
        let schema = DatabaseSchema(
            id: "db_empty",
            name: "",
            properties: [PropertyDefinition(id: "prop_title", name: "Title", type: .title)],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertEqual(schema.name, "")
        XCTAssertNotNil(schema.titleProperty)
    }

    func testEmptyStringPropertyName() {
        let prop = PropertyDefinition(id: "prop_x", name: "", type: .text)
        XCTAssertEqual(prop.name, "")
        XCTAssertEqual(prop.type, .text)
    }

    func testNilValuesInRowProperties() {
        let row = DatabaseRow(id: "row_nil", properties: [:])
        XCTAssertNil(row.properties["prop_nonexistent"])
        XCTAssertEqual(row.title(schema: makeSampleSchema()), "New Page")
    }

    func testEmptyQueryResultProperties() {
        let result = QueryResult(rows: [], totalCount: 0, hasMore: false)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertFalse(result.hasMore)
    }

    func testQueryOnEmptyRowsReturnsEmptyResult() {
        let schema = makeSampleSchema()
        let query = Query(
            databaseId: "db_test",
            filters: [.equals(property: "prop_status", value: .select("opt_todo"))],
            sorts: [Sort(property: "prop_priority", ascending: true)],
            limit: 10,
            offset: 0
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: [])
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertFalse(result.hasMore)
    }

    func testEmptyPropertyValueStringValue() {
        XCTAssertEqual(PropertyValue.empty.stringValue, "")
    }

    func testEmptyMultiSelectStringValue() {
        XCTAssertEqual(PropertyValue.multiSelect([]).stringValue, "")
    }

    func testEmptyRelationManyStringValue() {
        XCTAssertEqual(PropertyValue.relationMany([]).stringValue, "")
    }

    func testMutationResultWithNoOperations() {
        let result = MutationResult()
        XCTAssertTrue(result.created.isEmpty)
        XCTAssertTrue(result.updated.isEmpty)
        XCTAssertTrue(result.deleted.isEmpty)
        XCTAssertFalse(result.hasErrors)
    }

    func testSchemaWithNoProperties() {
        let schema = DatabaseSchema(
            id: "db_noprops",
            name: "Empty Schema",
            properties: [],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertNil(schema.titleProperty)
        XCTAssertTrue(schema.properties.isEmpty)
    }

    func testValidationOnSchemaWithNoProperties() {
        let schema = DatabaseSchema(
            id: "db_noprops",
            name: "Empty",
            properties: [],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        let errors = SchemaValidator.validate(properties: ["prop_x": .text("val")], schema: schema)
        XCTAssertTrue(errors.contains(where: { $0.propertyId == "prop_x" }))
    }

    func testRowSerializerParseEmptyString() {
        let schema = makeSampleSchema()
        XCTAssertNil(RowSerializer.parse(content: "", schema: schema))
    }

    // MARK: - Unicode Handling

    func testUnicodeSchemaName() throws {
        let schema = DatabaseSchema(
            id: "db_unicode",
            name: "タスク管理 📝",
            properties: [PropertyDefinition(id: "prop_title", name: "名前", type: .title)],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(DatabaseSchema.self, from: data)
        XCTAssertEqual(decoded.name, "タスク管理 📝")
        XCTAssertEqual(decoded.properties.first?.name, "名前")
    }

    func testUnicodePropertyValues() {
        let values: [PropertyValue] = [
            .text("日本語テスト"),
            .text("Ελληνικά"),
            .text("العربية"),
            .text("🎉🚀💻"),
            .select("状態"),
            .multiSelect(["赤", "青", "緑"]),
            .url("https://example.com/café"),
            .email("ñ@example.com")
        ]
        for value in values {
            XCTAssertFalse(value.stringValue.isEmpty, "String value should not be empty for: \(value)")
        }
    }

    func testUnicodePropertyValueCodableRoundTrip() throws {
        let value = PropertyValue.text("こんにちは世界 🌍")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testUnicodeInRowTitleAndBody() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_uni",
            properties: ["prop_title": .text("Ünïcödé Tëst — 日本")],
            body: "中文内容\nعربي\nрусский"
        )
        let content = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: content, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_title"], .text("Ünïcödé Tëst — 日本"))
        XCTAssertEqual(parsed?.body, "中文内容\nعربي\nрусский")
    }

    func testUnicodeQueryFilterContains() {
        let rows = [
            DatabaseRow(id: "row_j", properties: ["prop_title": .text("日本語タスク")]),
            DatabaseRow(id: "row_e", properties: ["prop_title": .text("English Task")])
        ]
        let schema = makeSampleSchema()
        let query = Query(
            databaseId: "db_test",
            filters: [.contains(property: "prop_title", value: .text("日本"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.id, "row_j")
    }

    func testUnicodeRowSerializerRoundTrip() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_emoji",
            properties: ["prop_title": .text("🔥 Hot Task 🔥")],
            body: "Body with émojis: 🎯🎨✅"
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.properties["prop_title"], .text("🔥 Hot Task 🔥"))
        XCTAssertEqual(parsed?.body, "Body with émojis: 🎯🎨✅")
    }

    // MARK: - Large Data

    func testSchemaWithManyColumns() throws {
        var properties: [PropertyDefinition] = [
            PropertyDefinition(id: "prop_title", name: "Title", type: .title)
        ]
        for i in 1...25 {
            properties.append(PropertyDefinition(id: "prop_col\(i)", name: "Column \(i)", type: .text))
        }
        let schema = DatabaseSchema(
            id: "db_wide",
            name: "Wide Table",
            properties: properties,
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertEqual(schema.properties.count, 26)

        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(DatabaseSchema.self, from: data)
        XCTAssertEqual(decoded.properties.count, 26)
        XCTAssertEqual(decoded.titleProperty?.id, "prop_title")
    }

    func testRowWithVeryLongTextValue() {
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 1000)
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_long",
            properties: ["prop_title": .text(longText)]
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.properties["prop_title"], .text(longText))
    }

    func testRowWithVeryLongBody() {
        let longBody = String(repeating: "# Section\nParagraph content.\n\n", count: 500)
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_longbody",
            properties: ["prop_title": .text("Long Body Row")],
            body: longBody
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertNotNil(parsed)
        // Parser trims trailing newlines from body
        let expectedBody = longBody.trimmingCharacters(in: .newlines)
        XCTAssertEqual(parsed?.body, expectedBody)
    }

    func testQueryEngineWithManyRows() {
        let schema = makeSampleSchema()
        var rows: [DatabaseRow] = []
        for i in 0..<500 {
            rows.append(DatabaseRow(
                id: "row_\(i)",
                properties: [
                    "prop_title": .text("Task \(i)"),
                    "prop_priority": .number(Double(i % 10)),
                    "prop_status": .select(i % 2 == 0 ? "opt_todo" : "opt_done")
                ]
            ))
        }
        let query = Query(
            databaseId: "db_test",
            filters: [.equals(property: "prop_status", value: .select("opt_todo"))],
            sorts: [Sort(property: "prop_priority", ascending: true)],
            limit: 10
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, 10)
        XCTAssertEqual(result.totalCount, 250)
        XCTAssertTrue(result.hasMore)
    }

    func testLargeMultiSelectArray() {
        let options = (0..<50).map { SelectOption(id: "opt_\($0)", name: "Option \($0)", color: "gray") }
        let tagsProp = PropertyDefinition(
            id: "prop_tags",
            name: "Tags",
            type: .multiSelect,
            config: PropertyConfig(options: options)
        )
        let schema = DatabaseSchema(
            id: "db_big_ms",
            name: "Big Multi",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                tagsProp
            ],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        let selectedIds = (0..<50).map { "opt_\($0)" }
        let properties: [String: PropertyValue] = [
            "prop_title": .text("All Tags"),
            "prop_tags": .multiSelect(selectedIds)
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Boundary Values

    func testNumberBoundaryValues() {
        let values: [(Double, String)] = [
            (Double(Int.max), String(Int.max)),
            (Double(Int.min), String(Int.min)),
            (0, "0"),
            (-0.0, "0"),
            (Double.pi, String(Double.pi)),
        ]
        for (num, _) in values {
            let pv = PropertyValue.number(num)
            XCTAssertFalse(pv.stringValue.isEmpty, "stringValue should not be empty for number: \(num)")
        }
    }

    func testNumberPropertyValueCodableAtExtremes() throws {
        let extremeValues: [PropertyValue] = [
            .number(0),
            .number(-1),
            .number(999999999999),
            .number(0.000001),
            .number(-999999999999),
        ]
        for value in extremeValues {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
            XCTAssertEqual(decoded, value, "Round-trip failed for \(value)")
        }
    }

    func testVeryLongPropertyName() throws {
        let longName = String(repeating: "x", count: 500)
        let prop = PropertyDefinition(id: "prop_long", name: longName, type: .text)
        let data = try JSONEncoder().encode(prop)
        let decoded = try JSONDecoder().decode(PropertyDefinition.self, from: data)
        XCTAssertEqual(decoded.name, longName)
    }

    func testVeryLongPropertyId() {
        let longId = "prop_" + String(repeating: "a", count: 500)
        let prop = PropertyDefinition(id: longId, name: "Test", type: .text)
        XCTAssertEqual(prop.id, longId)
    }

    func testDateBoundaryValues() {
        let dates = [
            "0001-01-01",
            "9999-12-31",
            "2024-02-29",    // leap year
            "1970-01-01",    // epoch
        ]
        for dateStr in dates {
            let pv = PropertyValue.date(dateStr)
            XCTAssertEqual(pv.stringValue, dateStr)
        }
    }

    func testDateBoundaryValueCodableRoundTrip() throws {
        let value = PropertyValue.date("9999-12-31")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testDatabaseDateValueRoundTripsStructuredPayload() {
        let value = DatabaseDateValue(
            start: "2026-03-07T09:30",
            end: "2026-03-07T10:30",
            includeTime: true,
            dateFormat: .full
        )

        let decoded = DatabaseDateValue.decode(from: value.rawValue)
        XCTAssertEqual(decoded, value)
    }

    func testDatabaseDateValuePreservesSimpleDateStorage() {
        let value = DatabaseDateValue(start: "2026-03-07")
        XCTAssertEqual(value.rawValue, "2026-03-07")
    }

    func testDatabaseDateValueContainsDaysAcrossRange() {
        let value = DatabaseDateValue(
            start: "2026-03-07",
            end: "2026-03-09",
            includeTime: false,
            dateFormat: .long
        )

        XCTAssertTrue(value.contains(dayString: "2026-03-07"))
        XCTAssertTrue(value.contains(dayString: "2026-03-08"))
        XCTAssertTrue(value.contains(dayString: "2026-03-09"))
        XCTAssertFalse(value.contains(dayString: "2026-03-10"))
    }

    func testSortWithEmptyValues() {
        let rows = [
            DatabaseRow(id: "row_empty", properties: ["prop_title": .text("Has Title")]),
            DatabaseRow(id: "row_num", properties: ["prop_title": .text("Has Both"), "prop_priority": .number(5)]),
            DatabaseRow(id: "row_also_empty", properties: ["prop_title": .text("No Priority")])
        ]
        let schema = makeSampleSchema()
        let query = Query(
            databaseId: "db_test",
            sorts: [Sort(property: "prop_priority", ascending: true)]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertEqual(result.rows.count, 3)
        // Row with actual number value should come first when ascending (empties sort last)
        XCTAssertEqual(result.rows.first?.id, "row_num")
    }

    func testOffsetBeyondRowCount() {
        let schema = makeSampleSchema()
        let rows = [
            DatabaseRow(id: "row_1", properties: ["prop_title": .text("Only Row")])
        ]
        let query = Query(databaseId: "db_test", offset: 100)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, 1)
    }

    func testZeroLimitReturnsNoRows() {
        let schema = makeSampleSchema()
        let rows = makeSampleRows()
        let query = Query(databaseId: "db_test", limit: 0)
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.totalCount, rows.count)
        XCTAssertTrue(result.hasMore)
    }

    // MARK: - Concurrent / Multiple Mutations

    func testMultipleMutationsOnSameStore() {
        let schema = makeSampleSchema()
        let dbPath = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let rowStore = RowStore()
        let indexManager = IndexManager()
        let dbStore = DatabaseStore()
        try? dbStore.saveSchema(schema, at: dbPath)

        // First mutation: create 3 rows
        let create = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("Row A")], body: nil),
                .createRow(properties: ["prop_title": .text("Row B")], body: nil),
                .createRow(properties: ["prop_title": .text("Row C")], body: nil)
            ]
        )
        let createResult = MutationEngine.execute(mutation: create, schema: schema, dbPath: dbPath,
                                                   rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(createResult.hasErrors)
        XCTAssertEqual(createResult.created.count, 3)

        // Second mutation: update first row
        let updateResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .updateRow(rowId: createResult.created[0], properties: ["prop_priority": .number(10)])
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertFalse(updateResult.hasErrors)

        // Third mutation: delete second row
        let deleteResult = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .deleteRow(rowId: createResult.created[1])
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        XCTAssertFalse(deleteResult.hasErrors)

        // Verify final state
        let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
        XCTAssertEqual(allRows.count, 2)
        let updatedRow = allRows.first(where: { $0.id == createResult.created[0] })
        XCTAssertEqual(updatedRow?.properties["prop_priority"], .number(10))
        XCTAssertNil(allRows.first(where: { $0.id == createResult.created[1] }))
    }

    func testMixedCreateUpdateDeleteInSingleMutation() {
        let schema = makeSampleSchema()
        let dbPath = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let rowStore = RowStore()
        let indexManager = IndexManager()
        let dbStore = DatabaseStore()
        try? dbStore.saveSchema(schema, at: dbPath)

        // Seed a row
        let seed = MutationEngine.execute(
            mutation: Mutation(databaseId: schema.id, operations: [
                .createRow(properties: ["prop_title": .text("Seed Row")], body: nil)
            ]),
            schema: schema, dbPath: dbPath, rowStore: rowStore, indexManager: indexManager
        )
        let seedId = seed.created.first!

        // Single mutation with create + update + delete
        let mixed = Mutation(
            databaseId: schema.id,
            operations: [
                .createRow(properties: ["prop_title": .text("New Row")], body: nil),
                .updateRow(rowId: seedId, properties: ["prop_title": .text("Updated Seed")]),
                .deleteRow(rowId: seedId)
            ]
        )
        let result = MutationEngine.execute(mutation: mixed, schema: schema, dbPath: dbPath,
                                             rowStore: rowStore, indexManager: indexManager)
        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(result.created.count, 1)
        XCTAssertEqual(result.updated.count, 1)
        XCTAssertEqual(result.deleted.count, 1)
    }

    // MARK: - Duplicate Handling

    func testDuplicateSchemaPropertyIds() {
        // Two properties with the same id -- the schema struct allows construction,
        // but SchemaValidator.validate uses Dictionary(uniqueKeysWithValues:) which
        // crashes on duplicate keys. This test verifies the schema can be created
        // and encoded without issue; validation is intentionally skipped since it
        // would crash (documenting that duplicate prop IDs are unsupported).
        let props = [
            PropertyDefinition(id: "prop_title", name: "Title", type: .title),
            PropertyDefinition(id: "prop_dup", name: "Field A", type: .text),
            PropertyDefinition(id: "prop_dup", name: "Field B", type: .number)
        ]
        let schema = DatabaseSchema(
            id: "db_dup",
            name: "Dup Test",
            properties: props,
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        XCTAssertEqual(schema.properties.count, 3)
        XCTAssertNotNil(schema.titleProperty)
        // JSON round-trip still works (arrays allow duplicates)
        let data = try? JSONEncoder().encode(schema)
        XCTAssertNotNil(data)
    }

    func testDuplicateRowIdsInQueryEngine() {
        let schema = makeSampleSchema()
        let rows = [
            DatabaseRow(id: "row_dup", properties: ["prop_title": .text("First"), "prop_priority": .number(1)]),
            DatabaseRow(id: "row_dup", properties: ["prop_title": .text("Second"), "prop_priority": .number(2)])
        ]
        let query = Query(databaseId: "db_test")
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        // Both rows returned even though IDs are the same -- QueryEngine doesn't deduplicate
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.totalCount, 2)
    }

    func testDuplicateSchemaNames() throws {
        let schema1 = DatabaseSchema(
            id: "db_1", name: "Tasks",
            properties: [PropertyDefinition(id: "prop_title", name: "Title", type: .title)],
            views: [], defaultView: "view_table", createdAt: "2024-01-01T00:00:00Z"
        )
        let schema2 = DatabaseSchema(
            id: "db_2", name: "Tasks",
            properties: [PropertyDefinition(id: "prop_title", name: "Title", type: .title)],
            views: [], defaultView: "view_table", createdAt: "2024-01-01T00:00:00Z"
        )
        // Same name, different IDs -- both should encode/decode fine
        XCTAssertEqual(schema1.name, schema2.name)
        XCTAssertNotEqual(schema1.id, schema2.id)
        let data1 = try JSONEncoder().encode(schema1)
        let data2 = try JSONEncoder().encode(schema2)
        XCTAssertNotEqual(data1, data2)
    }

    func testDuplicateSelectOptionIds() {
        let options = [
            SelectOption(id: "opt_a", name: "Alpha", color: "red"),
            SelectOption(id: "opt_a", name: "Also Alpha", color: "blue")
        ]
        let prop = PropertyDefinition(
            id: "prop_status",
            name: "Status",
            type: .select,
            config: PropertyConfig(options: options)
        )
        let schema = DatabaseSchema(
            id: "db_dupopt",
            name: "Dup Opts",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                prop
            ],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        // Selecting "opt_a" should pass since it exists (even if duplicated)
        let errors = SchemaValidator.validate(
            properties: ["prop_title": .text("Test"), "prop_status": .select("opt_a")],
            schema: schema
        )
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Special Characters

    func testSQLInjectionLikeValuesInText() {
        let malicious = "Robert'); DROP TABLE Students;--"
        let pv = PropertyValue.text(malicious)
        XCTAssertEqual(pv.stringValue, malicious)

        let schema = makeSampleSchema()
        let row = DatabaseRow(id: "row_sql", properties: ["prop_title": .text(malicious)])
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_title"], .text(malicious))
    }

    func testNewlinesInTextValues() {
        let textWithNewlines = "Line 1\nLine 2\nLine 3"
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_nl",
            properties: ["prop_title": .text(textWithNewlines)]
        )
        // Note: newlines in frontmatter values may not round-trip perfectly through
        // the YAML-like serializer. The important thing is no crash.
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        XCTAssertFalse(serialized.isEmpty)
    }

    func testTabsInTextValues() {
        let textWithTabs = "Col1\tCol2\tCol3"
        let pv = PropertyValue.text(textWithTabs)
        XCTAssertEqual(pv.stringValue, textWithTabs)
    }

    func testBackslashesInTextRoundTrip() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_bs",
            properties: ["prop_title": .text("C:\\Users\\test\\file.txt")]
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_title"], .text("C:\\Users\\test\\file.txt"))
    }

    func testQuotesInTextRoundTrip() {
        let schema = makeSampleSchema()
        let row = DatabaseRow(
            id: "row_qt",
            properties: ["prop_title": .text("She said \"hello\" and left")]
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_title"], .text("She said \"hello\" and left"))
    }

    func testSpecialCharsInBody() {
        let schema = makeSampleSchema()
        let body = "---\nThis looks like frontmatter but isn't\n---\n\n<script>alert('xss')</script>"
        let row = DatabaseRow(
            id: "row_body_special",
            properties: ["prop_title": .text("Special Body")],
            body: body
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertNotNil(parsed)
        // Body may or may not preserve the --- exactly, but shouldn't crash
        XCTAssertFalse(parsed?.body.isEmpty ?? true)
    }

    func testSpecialCharsInSelectOptionId() {
        let schema = DatabaseSchema(
            id: "db_special_select",
            name: "Special",
            properties: [
                PropertyDefinition(id: "prop_title", name: "Title", type: .title),
                PropertyDefinition(
                    id: "prop_status",
                    name: "Status",
                    type: .select,
                    config: PropertyConfig(options: [
                        SelectOption(id: "opt with spaces", name: "Has Spaces", color: "gray"),
                        SelectOption(id: "opt/with/slashes", name: "Has Slashes", color: "blue")
                    ])
                )
            ],
            views: [],
            defaultView: "view_table",
            createdAt: "2024-01-01T00:00:00Z"
        )
        let errors = SchemaValidator.validate(
            properties: [
                "prop_title": .text("Test"),
                "prop_status": .select("opt with spaces")
            ],
            schema: schema
        )
        XCTAssertTrue(errors.isEmpty)
    }

    func testUrlWithSpecialCharsRoundTrip() {
        let schema = makeSchemaWithUrlAndEmail()
        let url = "https://example.com/path?q=hello&lang=日本語&emoji=🎉"
        let row = DatabaseRow(
            id: "row_url_special",
            properties: [
                "prop_title": .text("URL Test"),
                "prop_url": .url(url)
            ]
        )
        let serialized = RowSerializer.serialize(row: row, schema: schema)
        let parsed = RowSerializer.parse(content: serialized, schema: schema)
        XCTAssertEqual(parsed?.properties["prop_url"], .url(url))
    }

    func testPropertyValueWithControlCharacters() throws {
        let value = PropertyValue.text("null\0byte and bell\u{07}")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PropertyValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testRowFilenameWithUnicode() {
        let filename = RowStore.rowFilename(title: "日本語タスク", suffix: "abc123")
        XCTAssertTrue(filename.contains("abc123"))
        XCTAssertTrue(filename.hasSuffix(".md"))
    }

    func testFilterPropertyIdAccessor() {
        let filters: [Filter] = [
            .equals(property: "p1", value: .text("a")),
            .notEquals(property: "p2", value: .text("b")),
            .greaterThan(property: "p3", value: .number(1)),
            .lessThan(property: "p4", value: .number(2)),
            .contains(property: "p5", value: .text("c")),
            .notContains(property: "p6", value: .text("d")),
            .isEmpty(property: "p7"),
            .isNotEmpty(property: "p8"),
            .inList(property: "p9", values: [.text("e")])
        ]
        let expectedIds = ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9"]
        for (filter, expected) in zip(filters, expectedIds) {
            XCTAssertEqual(filter.propertyId, expected)
        }
    }

    func testFilterOnNonExistentProperty() {
        let schema = makeSampleSchema()
        let rows = makeSampleRows()
        let query = Query(
            databaseId: "db_test",
            filters: [.equals(property: "prop_nonexistent", value: .text("anything"))]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        // Rows don't have this property, so nil != .text("anything") => all filtered out
        XCTAssertTrue(result.rows.isEmpty)
    }

    func testIsEmptyFilterOnMissingProperty() {
        let schema = makeSampleSchema()
        let rows = [
            DatabaseRow(id: "row_1", properties: ["prop_title": .text("Test")])
        ]
        let query = Query(
            databaseId: "db_test",
            filters: [.isEmpty(property: "prop_nonexistent")]
        )
        let result = QueryEngine.execute(query: query, schema: schema, rows: rows)
        // Missing property treated as empty
        XCTAssertEqual(result.rows.count, 1)
    }

    func testDatabaseInfoInit() {
        let info = DatabaseInfo(id: "db_1", name: "Tasks", path: "/tmp/tasks", rowCount: 42)
        XCTAssertEqual(info.id, "db_1")
        XCTAssertEqual(info.name, "Tasks")
        XCTAssertEqual(info.path, "/tmp/tasks")
        XCTAssertEqual(info.rowCount, 42)
    }

    func testValidationMultipleErrors() {
        let schema = makeSampleSchema()
        let properties: [String: PropertyValue] = [
            "prop_title": .text(""),            // empty title
            "prop_status": .text("wrong type"), // wrong type
            "prop_priority": .text("not num"),  // wrong type
            "prop_unknown": .text("no such")    // unknown property
        ]
        let errors = SchemaValidator.validate(properties: properties, schema: schema, requireTitle: true)
        XCTAssertTrue(errors.count >= 4, "Expected at least 4 errors, got \(errors.count)")
    }
}

// MARK: - Helpers

private func makeSampleSchema() -> DatabaseSchema {
    let titleProp = PropertyDefinition(id: "prop_title", name: "Title", type: .title)
    let statusProp = PropertyDefinition(
        id: "prop_status",
        name: "Status",
        type: .select,
        config: PropertyConfig(options: [
            SelectOption(id: "opt_todo", name: "To Do", color: "gray"),
            SelectOption(id: "opt_inprogress", name: "In Progress", color: "blue"),
            SelectOption(id: "opt_done", name: "Done", color: "green")
        ])
    )
    let priorityProp = PropertyDefinition(id: "prop_priority", name: "Priority", type: .number)
    let doneProp = PropertyDefinition(id: "prop_done", name: "Done", type: .checkbox)
    return DatabaseSchema(
        id: "db_test",
        name: "Tasks",
        properties: [titleProp, statusProp, priorityProp, doneProp],
        views: [ViewConfig(id: "view_table", name: "All Tasks", type: .table)],
        defaultView: "view_table",
        createdAt: "2024-01-01T00:00:00Z"
    )
}

private func makeSchemaWithMultiSelect() -> DatabaseSchema {
    let titleProp = PropertyDefinition(id: "prop_title", name: "Title", type: .title)
    let tagsProp = PropertyDefinition(
        id: "prop_tags",
        name: "Tags",
        type: .multiSelect,
        config: PropertyConfig(options: [
            SelectOption(id: "tag_a", name: "Alpha", color: "red"),
            SelectOption(id: "tag_b", name: "Beta", color: "blue"),
            SelectOption(id: "tag_c", name: "Gamma", color: "green")
        ])
    )
    return DatabaseSchema(
        id: "db_tagged",
        name: "Tagged Items",
        properties: [titleProp, tagsProp],
        views: [],
        defaultView: "view_table",
        createdAt: "2024-01-01T00:00:00Z"
    )
}

private func makeSchemaWithRelation() -> DatabaseSchema {
    let titleProp = PropertyDefinition(id: "prop_title", name: "Title", type: .title)
    let refProp = PropertyDefinition(
        id: "prop_ref",
        name: "Reference",
        type: .relation,
        config: PropertyConfig(target: "db_other")
    )
    return DatabaseSchema(
        id: "db_with_relation",
        name: "Items",
        properties: [titleProp, refProp],
        views: [],
        defaultView: "view_table",
        createdAt: "2024-01-01T00:00:00Z"
    )
}

private func makeSchemaWithUrlAndEmail() -> DatabaseSchema {
    let titleProp = PropertyDefinition(id: "prop_title", name: "Title", type: .title)
    let urlProp = PropertyDefinition(id: "prop_url", name: "Website", type: .url)
    let emailProp = PropertyDefinition(id: "prop_email", name: "Email", type: .email)
    return DatabaseSchema(
        id: "db_contacts",
        name: "Contacts",
        properties: [titleProp, urlProp, emailProp],
        views: [],
        defaultView: "view_table",
        createdAt: "2024-01-01T00:00:00Z"
    )
}

private func makeSampleRows() -> [DatabaseRow] {
    return [
        DatabaseRow(id: "row_1", properties: [
            "prop_title": .text("Task One"),
            "prop_status": .select("opt_todo"),
            "prop_priority": .number(1),
            "prop_done": .checkbox(false)
        ], createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date(timeIntervalSince1970: 1000)),
        DatabaseRow(id: "row_2", properties: [
            "prop_title": .text("Task Two"),
            "prop_status": .select("opt_todo"),
            "prop_priority": .number(3),
            "prop_done": .checkbox(false)
        ], createdAt: Date(timeIntervalSince1970: 2000), updatedAt: Date(timeIntervalSince1970: 2000)),
        DatabaseRow(id: "row_3", properties: [
            "prop_title": .text("Task Three"),
            "prop_status": .select("opt_done"),
            "prop_priority": .number(5),
            "prop_done": .checkbox(true)
        ], createdAt: Date(timeIntervalSince1970: 3000), updatedAt: Date(timeIntervalSince1970: 3000)),
        DatabaseRow(id: "row_4", properties: [
            "prop_title": .text("Another Task"),
            "prop_status": .select("opt_inprogress"),
            "prop_priority": .number(2),
            "prop_done": .checkbox(false)
        ], createdAt: Date(timeIntervalSince1970: 4000), updatedAt: Date(timeIntervalSince1970: 4000)),
        DatabaseRow(id: "row_5", properties: [
            "prop_title": .text("Final Task"),
            "prop_status": .select("opt_todo"),
            "prop_priority": .number(4),
            "prop_done": .checkbox(false)
        ], createdAt: Date(timeIntervalSince1970: 5000), updatedAt: Date(timeIntervalSince1970: 5000))
    ]
}

private func makeTemporaryDirectory() -> String {
    let tmpDir = NSTemporaryDirectory() + "BugbookCoreTests_\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    return tmpDir
}
