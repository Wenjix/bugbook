import SwiftUI
import BugbookCore

struct MobileDatabaseRowView: View {
    let dbPath: String
    let schema: DatabaseSchema
    let existingRow: DatabaseRow?

    @Environment(\.dismiss) private var dismiss

    @State private var properties: [String: PropertyValue] = [:]
    @State private var bodyText: String = ""
    @State private var saveError: String?
    @State private var showRelationPicker: IdentifiableString?

    private var isCreate: Bool { existingRow == nil }
    private let rowStore = RowStore()
    private let indexManager = IndexManager()
    private let dbStore = DatabaseStore()

    var body: some View {
        Form {
            Section("Properties") {
                ForEach(schema.properties) { prop in
                    propertyField(prop)
                }
            }

            Section("Body") {
                NavigationLink {
                    MobileRowBodyEditorView(bodyText: $bodyText, onSave: { scheduleSave() })
                } label: {
                    if bodyText.isEmpty {
                        Text("Tap to add content...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(bodyText)
                            .lineLimit(4)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(isCreate ? "New Row" : rowTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if let existingRow {
                properties = existingRow.properties
                // Load body separately if needed
                if existingRow.body.isEmpty {
                    let loadedBody = rowStore.loadRowBody(rowId: existingRow.id, dbPath: dbPath)
                bodyText = loadedBody
                } else {
                    bodyText = existingRow.body
                }
            } else {
                for prop in schema.properties {
                    properties[prop.id] = defaultValue(for: prop.type)
                }
            }
        }
        .sheet(item: $showRelationPicker) { wrapper in
            MobileRelationPickerView(
                propertyId: wrapper.id,
                property: schema.properties.first(where: { $0.id == wrapper.id })!,
                currentValue: properties[wrapper.id] ?? .empty,
                dbPath: dbPath,
                onSelect: { newValue in
                    properties[wrapper.id] = newValue
                }
            )
        }
    }

    private var rowTitle: String {
        if let titleProp = schema.titleProperty, case .text(let t) = properties[titleProp.id] {
            return t.isEmpty ? "Edit Row" : t
        }
        return "Edit Row"
    }

    // MARK: - Property Fields

    @ViewBuilder
    private func propertyField(_ prop: PropertyDefinition) -> some View {
        switch prop.type {
        case .title:
            TextField(prop.name, text: textBinding(for: prop.id))
                .font(.headline)
        case .text:
            TextField(prop.name, text: textBinding(for: prop.id))
        case .number:
            HStack {
                Text(prop.name)
                Spacer()
                TextField("0", text: numberBinding(for: prop.id))
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .frame(maxWidth: 120)
            }
        case .select:
            Picker(prop.name, selection: selectBinding(for: prop.id)) {
                Text("None").tag("")
                if let options = prop.options {
                    ForEach(options) { option in
                        HStack {
                            Circle().fill(colorForName(option.color)).frame(width: 8, height: 8)
                            Text(option.name)
                        }
                        .tag(option.id)
                    }
                }
            }
        case .multiSelect:
            DisclosureGroup(prop.name) {
                if let options = prop.options {
                    ForEach(options) { option in
                        Toggle(isOn: multiSelectToggle(propId: prop.id, optionId: option.id)) {
                            HStack {
                                Circle().fill(colorForName(option.color)).frame(width: 8, height: 8)
                                Text(option.name)
                            }
                        }
                    }
                }
            }
        case .date:
            MobileDatePropertyEditor(
                propertyName: prop.name,
                value: dateValueBinding(for: prop.id)
            )
        case .checkbox:
            Toggle(prop.name, isOn: checkboxBinding(for: prop.id))
        case .url:
            HStack {
                TextField(prop.name, text: urlBinding(for: prop.id))
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if case .url(let urlString) = properties[prop.id],
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        case .email:
            HStack {
                TextField(prop.name, text: emailBinding(for: prop.id))
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if case .email(let email) = properties[prop.id],
                   !email.isEmpty,
                   let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) {
                        Image(systemName: "envelope")
                    }
                }
            }
        case .relation:
            Button {
                showRelationPicker = IdentifiableString(prop.id)
            } label: {
                HStack {
                    Text(prop.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(relationDisplayText(for: prop))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        case .formula:
            LabeledContent(prop.name) {
                Text(formulaDisplay(for: prop))
                    .foregroundStyle(.secondary)
            }
        case .lookup:
            LabeledContent(prop.name) {
                Text(lookupDisplay(for: prop))
                    .foregroundStyle(.secondary)
            }
        case .rollup:
            LabeledContent(prop.name) {
                Text(rollupDisplay(for: prop))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings

    private func textBinding(for propId: String) -> Binding<String> {
        Binding(
            get: { if case .text(let s) = properties[propId] { return s }; return "" },
            set: { properties[propId] = .text($0) }
        )
    }

    private func numberBinding(for propId: String) -> Binding<String> {
        Binding(
            get: {
                if case .number(let n) = properties[propId] {
                    return n == n.rounded() && n < 1e15 ? String(Int(n)) : String(n)
                }
                return ""
            },
            set: {
                if let n = Double($0) { properties[propId] = .number(n) }
                else if $0.isEmpty { properties[propId] = .empty }
            }
        )
    }

    private func selectBinding(for propId: String) -> Binding<String> {
        Binding(
            get: { if case .select(let s) = properties[propId] { return s }; return "" },
            set: { properties[propId] = $0.isEmpty ? .empty : .select($0) }
        )
    }

    private func multiSelectToggle(propId: String, optionId: String) -> Binding<Bool> {
        Binding(
            get: {
                if case .multiSelect(let ids) = properties[propId] { return ids.contains(optionId) }
                return false
            },
            set: { isOn in
                var current: [String] = []
                if case .multiSelect(let ids) = properties[propId] { current = ids }
                if isOn { if !current.contains(optionId) { current.append(optionId) } }
                else { current.removeAll { $0 == optionId } }
                properties[propId] = current.isEmpty ? .empty : .multiSelect(current)
            }
        )
    }

    private func dateValueBinding(for propId: String) -> Binding<DatabaseDateValue?> {
        Binding(
            get: {
                if case .date(let raw) = properties[propId] {
                    return DatabaseDateValue.decode(from: raw)
                }
                return nil
            },
            set: { newValue in
                if let val = newValue {
                    properties[propId] = .date(val.rawValue)
                } else {
                    properties[propId] = .empty
                }
            }
        )
    }

    private func checkboxBinding(for propId: String) -> Binding<Bool> {
        Binding(
            get: { if case .checkbox(let b) = properties[propId] { return b }; return false },
            set: { properties[propId] = .checkbox($0) }
        )
    }

    private func urlBinding(for propId: String) -> Binding<String> {
        Binding(
            get: { if case .url(let s) = properties[propId] { return s }; return "" },
            set: { properties[propId] = .url($0) }
        )
    }

    private func emailBinding(for propId: String) -> Binding<String> {
        Binding(
            get: { if case .email(let s) = properties[propId] { return s }; return "" },
            set: { properties[propId] = .email($0) }
        )
    }

    // MARK: - Computed Display

    private func relationDisplayText(for prop: PropertyDefinition) -> String {
        let val = properties[prop.id] ?? .empty
        switch val {
        case .relation(let id): return id.isEmpty ? "None" : resolveRowTitle(id, prop: prop)
        case .relationMany(let ids): return ids.isEmpty ? "None" : ids.map { resolveRowTitle($0, prop: prop) }.joined(separator: ", ")
        default: return "None"
        }
    }

    private func resolveRowTitle(_ rowId: String, prop: PropertyDefinition) -> String {
        guard let targetPath = prop.config?.target else { return rowId }
        let fullPath: String
        if targetPath.hasPrefix("/") {
            fullPath = targetPath
        } else {
            let wsPath = (dbPath as NSString).deletingLastPathComponent
            fullPath = (wsPath as NSString).appendingPathComponent(targetPath)
        }
        guard let targetSchema = try? dbStore.loadSchema(at: fullPath) else { return rowId }
        let targetRows = rowStore.loadAllRows(in: fullPath, schema: targetSchema)
        return targetRows.first(where: { $0.id == rowId })?.title(schema: targetSchema) ?? rowId
    }

    private func formulaDisplay(for prop: PropertyDefinition) -> String {
        guard let formula = prop.config?.formula else { return "No formula" }
        var values: [String: Double] = [:]
        for p in schema.properties {
            if case .number(let n) = properties[p.id] { values[p.id] = n }
        }
        do {
            let result = try FormulaEngine.evaluate(expression: formula, values: values)
            let format = prop.config?.format
            return formatNumber(result, format: format)
        } catch {
            return "Error"
        }
    }

    private func lookupDisplay(for prop: PropertyDefinition) -> String {
        if case .text(let s) = properties[prop.id], !s.isEmpty { return s }
        return "\u{2014}"
    }

    private func rollupDisplay(for prop: PropertyDefinition) -> String {
        if case .number(let n) = properties[prop.id] {
            return formatNumber(n, format: prop.config?.format)
        }
        if case .text(let s) = properties[prop.id], !s.isEmpty { return s }
        return "\u{2014}"
    }

    // MARK: - Save

    private func save() {
        let rowId = existingRow?.id ?? RowStore.generateRowId()
        let now = Date()
        let row = DatabaseRow(
            id: rowId,
            properties: properties,
            body: bodyText,
            createdAt: existingRow?.createdAt ?? now,
            updatedAt: now
        )

        do {
            try rowStore.saveRow(row, schema: schema, dbPath: dbPath)
            let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
            let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
            try indexManager.saveIndex(index, at: dbPath)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func scheduleSave() {
        // Body changes are persisted when the user taps Save
    }

    private func defaultValue(for type: PropertyType) -> PropertyValue {
        switch type {
        case .title, .text, .url, .email: return .text("")
        case .number: return .empty
        case .select: return .empty
        case .multiSelect: return .empty
        case .date: return .empty
        case .checkbox: return .checkbox(false)
        case .relation: return .empty
        case .formula: return .empty
        case .lookup: return .empty
        case .rollup: return .empty
        }
    }
}

// MARK: - Number Formatting

func formatNumber(_ value: Double, format: String?) -> String {
    switch format {
    case "dollar":
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    case "percent":
        return "\(Int(value * 100))%"
    default:
        if value == value.rounded() && value < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Date Property Editor

struct MobileDatePropertyEditor: View {
    let propertyName: String
    @Binding var value: DatabaseDateValue?

    @State private var showDatePicker = false

    var body: some View {
        DisclosureGroup(propertyName) {
            if let dateVal = value {
                DatePicker("Start", selection: startBinding(dateVal), displayedComponents: dateVal.includeTime ? [.date, .hourAndMinute] : .date)

                if dateVal.end != nil {
                    DatePicker("End", selection: endBinding(dateVal), displayedComponents: dateVal.includeTime ? [.date, .hourAndMinute] : .date)
                }

                Toggle("Include time", isOn: Binding(
                    get: { dateVal.includeTime },
                    set: { newValue in value = dateVal.togglingIncludeTime(newValue) }
                ))

                Toggle("End date", isOn: Binding(
                    get: { dateVal.end != nil },
                    set: { newValue in value = dateVal.togglingEndDate(newValue) }
                ))

                Button("Clear date", role: .destructive) { value = nil }
            } else {
                Button("Set date") {
                    value = DatabaseDateValue(start: DatabaseDateValue.canonicalDayString(from: Date()))
                }
            }
        }
    }

    private func startBinding(_ dateVal: DatabaseDateValue) -> Binding<Date> {
        Binding(
            get: { dateVal.startDate ?? Date() },
            set: { value = dateVal.settingStart($0) }
        )
    }

    private func endBinding(_ dateVal: DatabaseDateValue) -> Binding<Date> {
        Binding(
            get: { dateVal.endDate ?? Date() },
            set: { value = dateVal.settingEnd($0) }
        )
    }
}

// MARK: - Body Editor

struct MobileRowBodyEditorView: View {
    @Binding var bodyText: String
    var onSave: () -> Void

    @State private var blocks: [EditableBlock] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                MobileBlockEditorView(
                    blocks: $blocks,
                    onBlocksChanged: {
                        bodyText = BlockMarkdownConverter.serialize(blocks)
                        onSave()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            BlockEditingToolbar(blocks: $blocks, onBlocksChanged: {
                bodyText = BlockMarkdownConverter.serialize(blocks)
                onSave()
            })
        }
        .navigationTitle("Body")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            blocks = BlockMarkdownConverter.parse(bodyText)
        }
    }
}

// MARK: - Relation Picker

struct MobileRelationPickerView: View {
    let propertyId: String
    let property: PropertyDefinition
    let currentValue: PropertyValue
    let dbPath: String
    let onSelect: (PropertyValue) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var targetRows: [DatabaseRow] = []
    @State private var targetSchema: DatabaseSchema?
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []

    private var isMany: Bool {
        property.config?.cardinality == "many"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRows) { row in
                    Button {
                        if isMany {
                            if selectedIds.contains(row.id) {
                                selectedIds.remove(row.id)
                            } else {
                                selectedIds.insert(row.id)
                            }
                        } else {
                            onSelect(.relation(row.id))
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(targetSchema.map { row.title(schema: $0) } ?? row.id)
                            Spacer()
                            if selectedIds.contains(row.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            #if os(iOS)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            #else
            .searchable(text: $searchText)
            #endif
            .navigationTitle("Select \(property.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isMany {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onSelect(.relationMany(Array(selectedIds)))
                            dismiss()
                        }
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear") {
                        onSelect(.empty)
                        dismiss()
                    }
                }
                #endif
            }
        }
        .onAppear { loadTargetRows() }
    }

    private var filteredRows: [DatabaseRow] {
        guard let schema = targetSchema else { return [] }
        if searchText.isEmpty { return targetRows }
        let q = searchText.lowercased()
        return targetRows.filter { $0.title(schema: schema).lowercased().contains(q) }
    }

    private func loadTargetRows() {
        guard let targetPath = property.config?.target else { return }
        let fullPath: String
        if targetPath.hasPrefix("/") {
            fullPath = targetPath
        } else {
            let wsPath = (dbPath as NSString).deletingLastPathComponent
            fullPath = (wsPath as NSString).appendingPathComponent(targetPath)
        }
        guard let schema = try? DatabaseStore().loadSchema(at: fullPath) else { return }
        targetSchema = schema
        targetRows = RowStore().loadAllRows(in: fullPath, schema: schema)

        // Initialize selected IDs
        switch currentValue {
        case .relation(let id): selectedIds = [id]
        case .relationMany(let ids): selectedIds = Set(ids)
        default: break
        }
    }
}

// Wrapper for sheet(item:) with String values
struct IdentifiableString: Identifiable {
    let id: String
    init(_ value: String) { self.id = value }
}
