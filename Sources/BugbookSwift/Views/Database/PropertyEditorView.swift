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

    // MARK: - Select (colored badges)

    private var selectEditor: some View {
        let options = definition.options ?? []
        let currentValue = { () -> String in
            if case .select(let s) = value { return s }
            return ""
        }()
        let currentOption = options.first(where: { $0.id == currentValue })

        return Menu {
            Button("None") { value = .empty }
            Divider()
            ForEach(options) { option in
                Button {
                    value = .select(option.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorForName(option.color))
                            .frame(width: 8, height: 8)
                        Text(option.name)
                    }
                }
            }
        } label: {
            if let opt = currentOption {
                Text(opt.name)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colorForName(opt.color).opacity(0.2))
                    .foregroundColor(colorForName(opt.color))
                    .cornerRadius(4)
            } else {
                Text("Select...")
                    .foregroundColor(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Multi Select (tags with X buttons)

    private var multiSelectEditor: some View {
        let options = definition.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return HStack(spacing: 4) {
            // Show selected tags
            ForEach(selectedIds, id: \.self) { id in
                if let option = options.first(where: { $0.id == id }) {
                    HStack(spacing: 2) {
                        Text(option.name)
                            .font(.caption2)
                        Button {
                            var updated = selectedIds
                            updated.removeAll { $0 == id }
                            value = updated.isEmpty ? .empty : .multiSelect(updated)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorForName(option.color).opacity(0.2))
                    .foregroundColor(colorForName(option.color))
                    .cornerRadius(4)
                }
            }

            // Add menu
            Menu {
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
                            Circle()
                                .fill(colorForName(option.color))
                                .frame(width: 8, height: 8)
                            Text(option.name)
                            if isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Date (native DatePicker)

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

    // MARK: - URL (with validation indicator)

    private var urlEditor: some View {
        let urlString = { () -> String in
            if case .url(let s) = value { return s }
            return ""
        }()
        let isValid = urlString.isEmpty || urlString.hasPrefix("http://") || urlString.hasPrefix("https://")

        return HStack(spacing: 4) {
            Image(systemName: "link")
                .foregroundColor(isValid ? .secondary : .red)
                .font(.caption)
            TextField("https://...", text: Binding(
                get: { urlString },
                set: { value = $0.isEmpty ? .empty : .url($0) }
            ))
            .textFieldStyle(.plain)
            if !urlString.isEmpty && !isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .help("URL should start with http:// or https://")
            }
        }
    }

    // MARK: - Email (with validation indicator)

    private var emailEditor: some View {
        let emailString = { () -> String in
            if case .email(let s) = value { return s }
            return ""
        }()
        let isValid = emailString.isEmpty || emailString.contains("@")

        return HStack(spacing: 4) {
            Image(systemName: "envelope")
                .foregroundColor(isValid ? .secondary : .red)
                .font(.caption)
            TextField("email@...", text: Binding(
                get: { emailString },
                set: { value = $0.isEmpty ? .empty : .email($0) }
            ))
            .textFieldStyle(.plain)
            if !emailString.isEmpty && !isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .help("Enter a valid email address")
            }
        }
    }

    // MARK: - Color Helper

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "orange": return .orange
        case "teal": return .teal
        default: return .gray
        }
    }
}
