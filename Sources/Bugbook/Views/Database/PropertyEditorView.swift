import SwiftUI
import BugbookCore

struct PropertyEditorView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    var onAddOption: ((String, SelectOption) -> Void)?
    var onUpdateOption: ((String, String, String?, String?) -> Void)?  // (propId, optionId, newName?, newColor?)
    var onDeleteOption: ((String, String) -> Void)?  // (propId, optionId)

    var body: some View {
        mainEditor
            .popover(item: $editingOptionId) { optId in
                editOptionPopover(optionId: optId)
            }
            .alert("Delete Option", isPresented: Binding(
                get: { showDeleteConfirm != nil },
                set: { if !$0 { showDeleteConfirm = nil } }
            )) {
                Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
                Button("Delete", role: .destructive) {
                    if let optId = showDeleteConfirm {
                        onDeleteOption?(definition.id, optId)
                    }
                    showDeleteConfirm = nil
                }
            } message: {
                Text("This will remove the option from all rows that use it.")
            }
    }

    @ViewBuilder
    private var mainEditor: some View {
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

    private func editOptionPopover(optionId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename Option")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("Name", text: $editingOptionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit {
                    let trimmed = editingOptionName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onUpdateOption?(definition.id, optionId, trimmed, nil)
                    }
                    editingOptionId = nil
                }

            HStack {
                Spacer()
                Button("Cancel") { editingOptionId = nil }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Button("Save") {
                    let trimmed = editingOptionName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onUpdateOption?(definition.id, optionId, trimmed, nil)
                    }
                    editingOptionId = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editingOptionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
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

    @State private var showSelectPopover: Bool = false
    @State private var showNewSelectOption: Bool = false
    @State private var newSelectOptionName: String = ""
    @State private var editingOptionId: String? = nil
    @State private var editingOptionName: String = ""
    @State private var showDeleteConfirm: String? = nil

    private var selectEditor: some View {
        let options = definition.options ?? []
        let currentValue = { () -> String in
            if case .select(let s) = value { return s }
            return ""
        }()
        let currentOption = options.first(where: { $0.id == currentValue })

        return HStack(spacing: 0) {
            if let opt = currentOption {
                Text(opt.name)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(colorForName(opt.color).opacity(0.12))
                    .foregroundColor(colorForName(opt.color))
                    .cornerRadius(4)
                    .contextMenu { optionContextMenu(for: opt) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
        .onTapGesture { showSelectPopover = true }
        .popover(isPresented: $showSelectPopover, arrowEdge: .bottom) {
            selectOptionList(options: options, currentValue: currentValue)
        }
        .popover(isPresented: $showNewSelectOption, arrowEdge: .bottom) {
            createOptionPopover(isSelect: true)
        }
    }

    private func selectOptionList(options: [SelectOption], currentValue: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            optionButton("None", isActive: currentValue.isEmpty) {
                value = .empty
                showSelectPopover = false
            }
            Divider().padding(.vertical, 2)
            ForEach(options) { option in
                optionButton(option.name, color: option.color, isActive: option.id == currentValue) {
                    value = .select(option.id)
                    showSelectPopover = false
                }
            }
            if onAddOption != nil {
                Divider().padding(.vertical, 2)
                optionButton("Create option...", isAction: true) {
                    newSelectOptionName = ""
                    showSelectPopover = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showNewSelectOption = true
                    }
                }
            }
        }
        .frame(width: 200)
        .padding(6)
    }

    // MARK: - Multi Select

    @State private var showMultiSelectPopover: Bool = false
    @State private var showNewTag: Bool = false
    @State private var newTagName: String = ""

    private var multiSelectEditor: some View {
        let options = definition.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return HStack(spacing: 0) {
            if !selectedIds.isEmpty {
                HStack(spacing: 3) {
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
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
        .onTapGesture { showMultiSelectPopover = true }
        .popover(isPresented: $showMultiSelectPopover, arrowEdge: .bottom) {
            multiSelectOptionList(options: options, selectedIds: selectedIds)
        }
        .popover(isPresented: $showNewTag, arrowEdge: .bottom) {
            createOptionPopover(isSelect: false)
        }
    }

    private func multiSelectOptionList(options: [SelectOption], selectedIds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                let isSelected = selectedIds.contains(option.id)
                optionButton(option.name, color: option.color, isActive: isSelected) {
                    var updated = selectedIds
                    if isSelected {
                        updated.removeAll { $0 == option.id }
                    } else {
                        updated.append(option.id)
                    }
                    value = updated.isEmpty ? .empty : .multiSelect(updated)
                }
            }
            if onAddOption != nil {
                Divider().padding(.vertical, 2)
                optionButton("Create tag...", isAction: true) {
                    newTagName = ""
                    showMultiSelectPopover = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showNewTag = true
                    }
                }
            }
        }
        .frame(width: 200)
        .padding(6)
    }

    // MARK: - Shared Option Button

    private func optionButton(_ label: String, color: String? = nil, isActive: Bool = false, isAction: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color = color {
                    Circle()
                        .fill(colorForName(color))
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.callout)
                    .foregroundColor(isAction ? .accentColor : .primary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Option Context Menu

    private static let optionColors = ["blue", "green", "purple", "orange", "pink", "teal", "yellow", "red", "gray", "default"]

    @ViewBuilder
    private func optionContextMenu(for option: SelectOption) -> some View {
        Button("Rename...") {
            editingOptionId = option.id
            editingOptionName = option.name
        }
        Menu("Color") {
            ForEach(Self.optionColors, id: \.self) { color in
                Button {
                    onUpdateOption?(definition.id, option.id, nil, color)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorForName(color))
                            .frame(width: 8, height: 8)
                        Text(color.capitalized)
                        if option.color == color {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            showDeleteConfirm = option.id
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

    @State private var showDatePicker: Bool = false

    private var dateEditor: some View {
        let hasDate = { if case .date = value { return true } else { return false } }()
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

        return HStack(spacing: 0) {
            if hasDate {
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            if !hasDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                value = .date(formatter.string(from: Date()))
            }
        }
    }

    // MARK: - Checkbox

    private var checkboxEditor: some View {
        let isChecked = { if case .checkbox(let b) = value { return b } else { return false } }()
        return HStack(spacing: 0) {
            if isChecked {
                Toggle("", isOn: Binding(
                    get: { true },
                    set: { if !$0 { value = .empty } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isChecked { value = .checkbox(true) }
        }
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
