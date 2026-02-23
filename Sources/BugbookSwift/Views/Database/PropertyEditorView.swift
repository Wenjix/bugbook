import SwiftUI

struct PropertyEditorView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue

    var body: some View {
        switch definition.type {
        case .text:
            textEditor
        case .number:
            numberEditor
        case .select:
            selectEditor
        case .multiSelect:
            multiSelectEditor
        case .date:
            dateEditor
        case .checkbox:
            checkboxEditor
        case .url:
            urlEditor
        case .email:
            emailEditor
        }
    }

    // MARK: - Text

    private var textEditor: some View {
        TextField("Empty", text: Binding(
            get: { if case .text(let s) = value { return s } else { return "" } },
            set: { value = .text($0) }
        ))
        .textFieldStyle(.plain)
    }

    // MARK: - Number

    private var numberEditor: some View {
        TextField("0", text: Binding(
            get: {
                if case .number(let n) = value {
                    return n == n.rounded() ? String(Int(n)) : String(n)
                }
                return ""
            },
            set: { value = .number(Double($0) ?? 0) }
        ))
        .textFieldStyle(.plain)
    }

    // MARK: - Select

    private var selectEditor: some View {
        let options = definition.options ?? []
        let currentValue = { () -> String in
            if case .select(let s) = value { return s }
            return ""
        }()

        return Menu {
            Button("None") { value = .empty }
            Divider()
            ForEach(options) { option in
                Button(option.name) { value = .select(option.id) }
            }
        } label: {
            let displayName = options.first(where: { $0.id == currentValue })?.name ?? currentValue
            Text(displayName.isEmpty ? "Select..." : displayName)
                .foregroundColor(displayName.isEmpty ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Multi Select

    private var multiSelectEditor: some View {
        let options = definition.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return Menu {
            ForEach(options) { option in
                let isSelected = selectedIds.contains(option.id)
                Button {
                    var updated = selectedIds
                    if isSelected {
                        updated.removeAll { $0 == option.id }
                    } else {
                        updated.append(option.id)
                    }
                    value = updated.isEmpty ? .empty : .multiSelect(updated)
                } label: {
                    HStack {
                        Text(option.name)
                        if isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if selectedIds.isEmpty {
                Text("Select...")
                    .foregroundColor(.secondary)
            } else {
                let names = selectedIds.compactMap { id in options.first(where: { $0.id == id })?.name }
                Text(names.joined(separator: ", "))
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Date

    private var dateEditor: some View {
        let dateBinding = Binding<Date>(
            get: {
                if case .date(let s) = value {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    return formatter.date(from: s) ?? Date()
                }
                return Date()
            },
            set: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                value = .date(formatter.string(from: $0))
            }
        )
        return DatePicker("", selection: dateBinding, displayedComponents: .date)
            .labelsHidden()
    }

    // MARK: - Checkbox

    private var checkboxEditor: some View {
        Toggle("", isOn: Binding(
            get: { if case .checkbox(let b) = value { return b } else { return false } },
            set: { value = .checkbox($0) }
        ))
        .labelsHidden()
        .toggleStyle(.checkbox)
    }

    // MARK: - URL

    private var urlEditor: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("https://...", text: Binding(
                get: { if case .url(let s) = value { return s } else { return "" } },
                set: { value = $0.isEmpty ? .empty : .url($0) }
            ))
            .textFieldStyle(.plain)
        }
    }

    // MARK: - Email

    private var emailEditor: some View {
        HStack(spacing: 4) {
            Image(systemName: "envelope")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("email@...", text: Binding(
                get: { if case .email(let s) = value { return s } else { return "" } },
                set: { value = $0.isEmpty ? .empty : .email($0) }
            ))
            .textFieldStyle(.plain)
        }
    }
}
