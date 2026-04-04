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

    private var isCreate: Bool { existingRow == nil }
    private let rowStore = RowStore()
    private let indexManager = IndexManager()

    var body: some View {
        Form {
            Section("Properties") {
                ForEach(schema.properties) { prop in
                    propertyField(prop)
                }
            }

            Section("Body") {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 120)
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(isCreate ? "New Row" : "Edit Row")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .onAppear {
            if let existingRow {
                properties = existingRow.properties
                bodyText = existingRow.body
            } else {
                // Initialize empty values for each property
                for prop in schema.properties {
                    properties[prop.id] = defaultValue(for: prop.type)
                }
            }
        }
    }

    // MARK: - Property Fields

    @ViewBuilder
    private func propertyField(_ prop: PropertyDefinition) -> some View {
        switch prop.type {
        case .title, .text:
            TextField(prop.name, text: textBinding(for: prop.id))
        case .number:
            TextField(prop.name, text: numberBinding(for: prop.id))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        case .select:
            Picker(prop.name, selection: selectBinding(for: prop.id)) {
                Text("None").tag("")
                if let options = prop.options {
                    ForEach(options) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
        case .multiSelect:
            DisclosureGroup(prop.name) {
                if let options = prop.options {
                    ForEach(options) { option in
                        Toggle(option.name, isOn: multiSelectToggle(propId: prop.id, optionId: option.id))
                    }
                }
            }
        case .date:
            DatePicker(prop.name, selection: dateBinding(for: prop.id), displayedComponents: .date)
        case .checkbox:
            Toggle(prop.name, isOn: checkboxBinding(for: prop.id))
        case .url:
            TextField(prop.name, text: textBinding(for: prop.id))
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        case .email:
            TextField(prop.name, text: textBinding(for: prop.id))
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        case .relation:
            let value: String = {
                if case .relation(let id) = properties[prop.id] { return id }
                if case .relationMany(let ids) = properties[prop.id] { return ids.joined(separator: ", ") }
                return ""
            }()
            LabeledContent(prop.name) {
                Text(value.isEmpty ? "None" : value)
                    .foregroundStyle(.secondary)
            }
        case .formula:
            LabeledContent(prop.name) {
                Text("Computed")
                    .foregroundStyle(.secondary)
            }
        case .lookup:
            let value: String = {
                if case .text(let s) = properties[prop.id] { return s }
                return ""
            }()
            LabeledContent(prop.name) {
                Text(value.isEmpty ? "\u{2014}" : value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings

    private func textBinding(for propId: String) -> Binding<String> {
        Binding<String>(
            get: {
                if case .text(let s) = properties[propId] { return s }
                return ""
            },
            set: { properties[propId] = .text($0) }
        )
    }

    private func numberBinding(for propId: String) -> Binding<String> {
        Binding<String>(
            get: {
                if case .number(let n) = properties[propId] {
                    return n == n.rounded() && n < 1e15 ? String(Int(n)) : String(n)
                }
                return ""
            },
            set: {
                if let n = Double($0) {
                    properties[propId] = .number(n)
                } else if $0.isEmpty {
                    properties[propId] = .empty
                }
            }
        )
    }

    private func selectBinding(for propId: String) -> Binding<String> {
        Binding<String>(
            get: {
                if case .select(let s) = properties[propId] { return s }
                return ""
            },
            set: {
                properties[propId] = $0.isEmpty ? .empty : .select($0)
            }
        )
    }

    private func multiSelectToggle(propId: String, optionId: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .multiSelect(let ids) = properties[propId] {
                    return ids.contains(optionId)
                }
                return false
            },
            set: { isOn in
                var current: [String] = []
                if case .multiSelect(let ids) = properties[propId] {
                    current = ids
                }
                if isOn {
                    if !current.contains(optionId) { current.append(optionId) }
                } else {
                    current.removeAll { $0 == optionId }
                }
                properties[propId] = current.isEmpty ? .empty : .multiSelect(current)
            }
        )
    }

    private func dateBinding(for propId: String) -> Binding<Date> {
        Binding<Date>(
            get: {
                if case .date(let raw) = properties[propId] {
                    return DatabaseDateValue.decode(from: raw)?.startDate ?? Date()
                }
                return Date()
            },
            set: {
                let existing = {
                    if case .date(let raw) = properties[propId] {
                        return DatabaseDateValue.decode(from: raw)
                    }
                    return nil
                }()
                let updated = (existing ?? DatabaseDateValue(start: DatabaseDateValue.canonicalDayString(from: $0)))
                    .settingStart($0)
                properties[propId] = .date(updated.rawValue)
            }
        )
    }

    private func checkboxBinding(for propId: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .checkbox(let b) = properties[propId] { return b }
                return false
            },
            set: { properties[propId] = .checkbox($0) }
        )
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

            // Rebuild index
            let allRows = rowStore.loadAllRows(in: dbPath, schema: schema)
            let index = indexManager.rebuild(dbPath: dbPath, schema: schema, rows: allRows)
            try indexManager.saveIndex(index, at: dbPath)

            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Helpers

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
        }
    }
}
