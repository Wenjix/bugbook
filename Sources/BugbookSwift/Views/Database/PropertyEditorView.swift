import SwiftUI
import BugbookCore

struct PropertyEditorView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    var onAddOption: ((String, SelectOption) -> Void)?

    var body: some View {
        switch definition.type {
        case .title, .text:
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
        case .relation:
            textEditor
        }
    }

    // MARK: - Text

    private var textEditor: some View {
        TextField("", text: Binding(
            get: { if case .text(let s) = value { return s } else { return "" } },
            set: { value = .text($0) }
        ))
        .textFieldStyle(.plain)
        .foregroundColor(.primary)
    }

    // MARK: - Number

    private var numberEditor: some View {
        TextField("", text: Binding(
            get: {
                if case .number(let n) = value {
                    return n == n.rounded() ? String(Int(n)) : String(n)
                }
                return ""
            },
            set: { value = .number(Double($0) ?? 0) }
        ))
        .textFieldStyle(.plain)
        .foregroundColor(.primary)
    }

    // MARK: - Select

    @State private var showNewSelectOption: Bool = false
    @State private var newSelectOptionName: String = ""

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
            if onAddOption != nil {
                Divider()
                Button("Create option...") {
                    newSelectOptionName = ""
                    showNewSelectOption = true
                }
            }
        } label: {
            if let opt = currentOption {
                Text(opt.name)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colorForName(opt.color).opacity(0.12))
                    .foregroundColor(colorForName(opt.color))
                    .cornerRadius(4)
            } else {
                Color.clear.frame(height: 22)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showNewSelectOption, arrowEdge: .bottom) {
            createOptionPopover(isSelect: true)
        }
    }

    // MARK: - Multi Select

    @State private var showNewTag: Bool = false
    @State private var newTagName: String = ""

    private var multiSelectEditor: some View {
        let options = definition.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return HStack(spacing: 3) {
            // Compact tag pills — no X buttons, remove via dropdown
            ForEach(selectedIds.prefix(3), id: \.self) { id in
                if let option = options.first(where: { $0.id == id }) {
                    Text(option.name)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForName(option.color).opacity(0.12))
                        .foregroundColor(colorForName(option.color))
                        .cornerRadius(4)
                }
            }
            if selectedIds.count > 3 {
                Text("+\(selectedIds.count - 3)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Add/remove menu
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
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if onAddOption != nil {
                    Divider()
                    Button("Create tag...") {
                        newTagName = ""
                        showNewTag = true
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .popover(isPresented: $showNewTag, arrowEdge: .bottom) {
                createOptionPopover(isSelect: false)
            }
        }
    }

    // MARK: - Create Option Popover (shared by select & multiSelect)

    private func createOptionPopover(isSelect: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSelect ? "New option" : "New tag")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("Name", text: isSelect ? $newSelectOptionName : $newTagName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    commitNewOption(isSelect: isSelect)
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    if isSelect { showNewSelectOption = false } else { showNewTag = false }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Add") {
                    commitNewOption(isSelect: isSelect)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled((isSelect ? newSelectOptionName : newTagName).trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func commitNewOption(isSelect: Bool) {
        let name = (isSelect ? newSelectOptionName : newTagName).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let colors = ["blue", "green", "purple", "orange", "pink", "teal", "yellow", "red"]
        let color = colors.randomElement() ?? "blue"
        let option = SelectOption(id: "opt_\(UUID().uuidString)", name: name, color: color)
        onAddOption?(definition.id, option)

        if isSelect {
            value = .select(option.id)
            showNewSelectOption = false
            newSelectOptionName = ""
        } else {
            var current: [String] = []
            if case .multiSelect(let arr) = value { current = arr }
            current.append(option.id)
            value = .multiSelect(current)
            showNewTag = false
            newTagName = ""
        }
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
        let urlString = { () -> String in
            if case .url(let s) = value { return s }
            return ""
        }()

        return HStack(spacing: 4) {
            Image(systemName: "link")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("", text: Binding(
                get: { urlString },
                set: { value = $0.isEmpty ? .empty : .url($0) }
            ))
            .textFieldStyle(.plain)
        }
    }

    // MARK: - Email

    private var emailEditor: some View {
        let emailString = { () -> String in
            if case .email(let s) = value { return s }
            return ""
        }()

        return HStack(spacing: 4) {
            Image(systemName: "envelope")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("", text: Binding(
                get: { emailString },
                set: { value = $0.isEmpty ? .empty : .email($0) }
            ))
            .textFieldStyle(.plain)
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
