import SwiftUI
import BugbookCore

/// Lightweight container for relation row candidates (id + display title).
struct RelationRowCandidate: Identifiable {
    let id: String
    let title: String
}

/// Lightweight container for available databases (for relation target picking).
struct RelationDatabaseCandidate: Identifiable {
    let id: String   // database id
    let name: String
    let path: String
}

struct PropertyEditorView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    var wrapText: Bool = false
    var compact: Bool = false
    var onAddOption: ((String, SelectOption) -> Void)?
    var onUpdateOption: ((String, String, String?, String?) -> Void)?  // (propId, optionId, newName?, newColor?)
    var onDeleteOption: ((String, String) -> Void)?  // (propId, optionId)
    /// Callback to load candidate rows for a relation property (returns rows from target database).
    var onLoadRelationRows: (() -> [RelationRowCandidate])?
    /// Callback to list available databases for relation target selection.
    var onListDatabases: (() -> [RelationDatabaseCandidate])?
    /// Callback to set the target database for a relation property.
    var onSetRelationTarget: ((String, String) -> Void)? // (propertyId, targetDbPath)

    /// Pre-computed formula display text (result or error). Provided by the caller for formula properties.
    var formulaResult: String?
    /// Whether the formula evaluation produced an error.
    var formulaError: Bool = false
    /// Pre-computed display string for lookup fields.
    var lookupDisplayValue: String?
    /// Pre-computed display string for rollup fields.
    var rollupDisplayValue: String?

    @State private var showSelectPopover: Bool = false
    @State private var showNewSelectOption: Bool = false
    @State private var newSelectOptionName: String = ""
    @State private var editingOptionId: String?
    @State private var editingOptionName: String = ""
    @State private var editingOptionColor: String = "default"
    @State private var showDeleteConfirm: String?
    @State private var showDeleteAlert = false
    @State private var showMultiSelectPopover: Bool = false
    @State private var showNewTag: Bool = false
    @State private var newTagName: String = ""
    @State private var showDatePicker: Bool = false
    @State private var showRelationPicker = false
    @State private var showRelationTargetPicker = false
    @State private var relationCandidates: [RelationRowCandidate] = []
    @State private var relationDatabases: [RelationDatabaseCandidate] = []
    @State private var relationSearch = ""
    @State private var relationDbSearch = ""
    @State private var isRelationHovered = false

    /// Consistent cell font matching table text (14pt scaled).
    private var cellFont: Font { DatabaseZoomMetrics.font(14) }

    /// Whether this property type uses option editing popovers (select/multiSelect only).
    private var usesOptionEditing: Bool {
        definition.type == .select || definition.type == .multiSelect
    }

    var body: some View {
        if usesOptionEditing {
            mainEditor
                .databasePointerCursor()
                .floatingPopover(item: $editingOptionId, arrowEdge: .trailing) { optId in
                    editOptionPopover(optionId: optId)
                }
                .alert("Delete Option", isPresented: $showDeleteAlert) {
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
                .onChange(of: showDeleteConfirm) { _, val in
                    showDeleteAlert = (val != nil)
                }
                .onChange(of: showDeleteAlert) { _, show in
                    if !show { showDeleteConfirm = nil }
                }
        } else {
            mainEditor
                .databasePointerCursor()
        }
    }
}

private extension PropertyEditorView {

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
            relationEditor
        case .formula:
            formulaDisplay
        case .lookup:
            lookupDisplay
        case .rollup:
            rollupDisplay
        }
    }

    private func editOptionPopover(optionId: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rename field
            TextField("Option name", text: $editingOptionName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onSubmit { commitOptionEdit(optionId: optionId) }

            // Delete
            Button {
                showDeleteConfirm = optionId
                editingOptionId = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.callout)
                    Text("Delete")
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 4)

            // Color list (Notion-style: vertical list with color swatch + name)
            Text("Colors")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ForEach(Self.optionColors, id: \.self) { color in
                OptionColorRow(
                    name: color.capitalized,
                    color: colorForName(color),
                    isSelected: editingOptionColor == color,
                    onSelect: {
                        editingOptionColor = color
                        commitOptionEdit(optionId: optionId)
                    }
                )
            }
        }
        .padding(12)
        .popoverSurface()
    }

    private func commitOptionEdit(optionId: String) {
        let trimmed = editingOptionName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onUpdateOption?(definition.id, optionId, trimmed, editingOptionColor)
        }
        editingOptionId = nil
    }

    // MARK: - Text

    private var textEditor: some View {
        plainTextField(Binding(
            get: { if case .text(let s) = value { return s } else { return "" } },
            set: { value = .text($0) }
        ))
    }

    // MARK: - Number

    private var numberEditor: some View {
        TextField(compact ? "" : "Empty", text: Binding(
            get: {
                if case .number(let n) = value {
                    return n == n.rounded() ? String(Int(n)) : String(n)
                }
                return ""
            },
            set: { value = .number(Double($0) ?? 0) }
        ))
        .textFieldStyle(.plain)
        .font(cellFont)
        .foregroundStyle(.primary)
    }

    // MARK: - Select

    private var selectEditor: some View {
        let options = definition.options ?? []
        let currentValue = { () -> String in
            if case .select(let s) = value { return s }
            return ""
        }()
        let currentOption = options.first(where: { $0.id == currentValue })

        return Button { showSelectPopover = true } label: {
            HStack(spacing: 0) {
                if let opt = currentOption {
                    Text(opt.name)
                        .font(cellFont)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colorForName(opt.color).opacity(0.12))
                        .foregroundStyle(colorForName(opt.color))
                        .clipShape(.rect(cornerRadius: 4))
                        .contextMenu { optionContextMenu(for: opt) }
                } else if !compact {
                    Text("Empty")
                        .font(cellFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showSelectPopover, arrowEdge: .bottom) {
            selectOptionList(options: options, currentValue: currentValue)
        }
        .floatingPopover(isPresented: $showNewSelectOption, arrowEdge: .bottom) {
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
                optionButton(option.name, color: option.color, isActive: option.id == currentValue, option: option) {
                    value = .select(option.id)
                    showSelectPopover = false
                }
                .contextMenu { optionContextMenu(for: option) }
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
        .popoverSurface()
    }

    // MARK: - Multi Select

    private var multiSelectEditor: some View {
        let options = definition.options ?? []
        let selectedIds: [String] = {
            if case .multiSelect(let arr) = value { return arr }
            return []
        }()

        return Button { showMultiSelectPopover = true } label: {
            HStack(spacing: 0) {
                if !selectedIds.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(selectedIds.prefix(3), id: \.self) { id in
                            if let option = options.first(where: { $0.id == id }) {
                                Text(option.name)
                                    .font(cellFont)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForName(option.color).opacity(0.12))
                                    .foregroundStyle(colorForName(option.color))
                                    .clipShape(.rect(cornerRadius: 4))
                            }
                        }
                        if selectedIds.count > 3 {
                            Text("+\(selectedIds.count - 3)")
                                .font(cellFont)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if !compact {
                    Text("Empty")
                        .font(cellFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showMultiSelectPopover, arrowEdge: .bottom) {
            multiSelectOptionList(options: options, selectedIds: selectedIds)
        }
        .floatingPopover(isPresented: $showNewTag, arrowEdge: .bottom) {
            createOptionPopover(isSelect: false)
        }
    }

    private func multiSelectOptionList(options: [SelectOption], selectedIds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                let isSelected = selectedIds.contains(option.id)
                optionButton(option.name, color: option.color, isActive: isSelected, option: option) {
                    var updated = selectedIds
                    if isSelected {
                        updated.removeAll { $0 == option.id }
                    } else {
                        updated.append(option.id)
                    }
                    value = updated.isEmpty ? .empty : .multiSelect(updated)
                }
                .contextMenu { optionContextMenu(for: option) }
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
        .popoverSurface()
    }

    // MARK: - Shared Option Button

    private func optionButton(
        _ label: String,
        color: String? = nil,
        isActive: Bool = false,
        isAction: Bool = false,
        option: SelectOption? = nil,
        action: @escaping () -> Void
    ) -> some View {
        OptionButtonRow(
            label: label,
            color: color.map { colorForName($0) },
            isActive: isActive,
            isAction: isAction,
            showKebab: option != nil,
            onSelect: action,
            onKebab: {
                if let option = option {
                    editingOptionId = option.id
                    editingOptionName = option.name
                    editingOptionColor = option.color
                }
            }
        )
    }

    // MARK: - Option Context Menu

    private static let optionColors = ["blue", "green", "purple", "orange", "pink", "teal", "yellow", "gray", "default"]

    @ViewBuilder
    private func optionContextMenu(for option: SelectOption) -> some View {
        Button("Edit...") {
            editingOptionId = option.id
            editingOptionName = option.name
            editingOptionColor = option.color
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
                .foregroundStyle(.secondary)

                Button("Add") {
                    commitNewOption(isSelect: isSelect)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled((isSelect ? newSelectOptionName : newTagName).trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .popoverSurface()
    }

    private func commitNewOption(isSelect: Bool) {
        let name = (isSelect ? newSelectOptionName : newTagName).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let colors = ["blue", "green", "purple", "orange", "pink", "teal", "yellow", "gray"]
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
        let dateValue = currentDateValue
        let hasDate = dateValue != nil
        let label = dateValue?.displayText(compact: compact) ?? ""
        let horizontalPadding: CGFloat = compact ? 8 : 10
        let verticalPadding: CGFloat = compact ? 4 : 6
        return HStack(spacing: 0) {
            Button {
                if currentDateValue == nil {
                    commitDateValue(
                        DatabaseDateValue(
                            start: DatabaseDateValue.canonicalDayString(from: Date())
                        )
                    )
                }
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    if hasDate {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(label)
                            .font(cellFont)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !compact {
                        Text("Empty")
                            .font(cellFont)
                            .foregroundStyle(.secondary)
                    } else {
                        Color.clear
                            .frame(height: 14)
                    }
                }
                .padding(.horizontal, hasDate || compact ? horizontalPadding : 0)
                .padding(.vertical, hasDate || compact ? verticalPadding : 0)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 7 : 9)
                        .fill(hasDate ? Color.fallbackSurfaceSubtle : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: compact ? 7 : 9)
                                .stroke(
                                    hasDate ? Color.fallbackBorderColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .floatingPopover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                DatePropertyPopover(
                    value: Binding(
                        get: { currentDateValue },
                        set: { commitDateValue($0) }
                    )
                )
            }

            if !compact {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .contentShape(Rectangle())
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
            plainTextField(Binding(
                get: { urlString },
                set: { value = $0.isEmpty ? .empty : .url($0) }
            ))
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
            plainTextField(Binding(
                get: { emailString },
                set: { value = $0.isEmpty ? .empty : .email($0) }
            ))
        }
    }

    @ViewBuilder
    private func plainTextField(_ text: Binding<String>) -> some View {
        let placeholder = compact ? "" : "Empty"
        if wrapText {
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(cellFont)
                .lineLimit(1...4)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        } else {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(cellFont)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Relation

    private var selectedRelationIds: Set<String> {
        switch value {
        case .relation(let id): return id.isEmpty ? [] : [id]
        case .relationMany(let ids): return Set(ids)
        default: return []
        }
    }

    private var supportsMultipleRelations: Bool {
        definition.config?.cardinality != "one_to_one"
    }

    private var hasRelationTarget: Bool {
        guard let target = definition.config?.target else { return false }
        return !target.isEmpty
    }

    private var relationEditor: some View {
        let candidates = relationCandidates
        let selected = selectedRelationIds
        let selectedCandidates = candidates.filter { selected.contains($0.id) }
        let showsRelationAction = hasRelationTarget && isRelationHovered

        return ZStack(alignment: .topTrailing) {
            RelationFlowLayout(spacing: 4) {
                if !hasRelationTarget {
                    Text(compact ? "" : "Select target database...")
                        .foregroundStyle(.secondary)
                        .font(cellFont)
                } else if !selectedCandidates.isEmpty {
                    ForEach(selectedCandidates) { candidate in
                        Button {
                            openRelatedRow(candidate.id)
                        } label: {
                            Text(candidate.title)
                                .font(cellFont)
                                .foregroundStyle(.primary)
                                .underline()
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(compact ? "" : "Empty")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsRelationAction {
                Button {
                    presentRelationPicker()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.fallbackAccentFg)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(selectedCandidates.isEmpty ? "Add related pages" : "Edit related pages")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { isRelationHovered = $0 }
        .onTapGesture {
            if !hasRelationTarget {
                presentRelationTargetPicker()
            } else if selectedCandidates.isEmpty {
                presentRelationPicker()
            }
        }
        .floatingPopover(isPresented: $showRelationTargetPicker, arrowEdge: .bottom) {
            relationTargetPickerPopover
        }
        .floatingPopover(isPresented: $showRelationPicker, arrowEdge: .bottom) {
            relationPickerPopover
        }
        .task {
            if relationDatabases.isEmpty {
                relationDatabases = onListDatabases?() ?? []
            }
            if hasRelationTarget && relationCandidates.isEmpty {
                relationCandidates = onLoadRelationRows?() ?? []
            }
        }
        .onChange(of: definition.config?.target) { _, newTarget in
            if let newTarget, !newTarget.isEmpty {
                relationCandidates = onLoadRelationRows?() ?? []
            }
        }
    }

    // MARK: - Formula

    private var formulaDisplay: some View {
        Group {
            if let result = formulaResult, !result.isEmpty {
                Text(result)
                    .font(cellFont)
                    .foregroundStyle(formulaError ? .red : .secondary)
                    .lineLimit(1)
                    .help(formulaError ? result : (definition.config?.formula ?? ""))
            } else {
                Text(compact ? "" : "No formula")
                    .font(cellFont)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Read-only display for lookup fields. The actual value is computed at render time.
    private var lookupDisplay: some View {
        let displayText = lookupDisplayValue.flatMap { $0.isEmpty ? nil : $0 } ?? "\u{2014}"
        return Text(displayText)
            .font(cellFont)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    /// Read-only display for rollup fields. The aggregated value is computed at render time.
    private var rollupDisplay: some View {
        let displayText = rollupDisplayValue.flatMap { $0.isEmpty ? nil : $0 } ?? "\u{2014}"
        return Text(displayText)
            .font(cellFont)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private var relationTargetPickerPopover: some View {
        VStack(spacing: 0) {
            TextField("Search databases...", text: $relationDbSearch)
                .textFieldStyle(.plain)
                .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let filtered = relationDbSearch.isEmpty
                        ? relationDatabases
                        : relationDatabases.filter { $0.name.localizedStandardContains(relationDbSearch) }
                    if filtered.isEmpty {
                        Text("No databases found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    } else {
                        ForEach(filtered) { db in
                            Button {
                                onSetRelationTarget?(definition.id, db.path)
                                showRelationTargetPicker = false
                                relationDbSearch = ""
                                // The schema update will re-render this view with the new
                                // definition (which has the target set). onAppear will
                                // then load the relation row candidates.
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "tablecells")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 13))
                                    Text(db.name)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 260)
        .popoverSurface()
    }

    private var targetDatabaseName: String {
        // Use the cached database list if available (has the real schema name),
        // otherwise fall back to the folder name on disk.
        guard let target = definition.config?.target, !target.isEmpty else { return "" }
        if let match = relationDatabases.first(where: { $0.path == target }) {
            return match.name
        }
        return (target as NSString).lastPathComponent
    }

    private var relationPickerPopover: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search...", text: $relationSearch)
                    .textFieldStyle(.plain)
                if !targetDatabaseName.isEmpty {
                    Text("In")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        openTargetDatabase()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "tablecells")
                                .font(.system(size: 10))
                            Text(targetDatabaseName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(targetDatabaseName)")
                }
            }
            .padding(8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let filtered = relationSearch.isEmpty
                        ? relationCandidates
                        : relationCandidates.filter { $0.title.localizedStandardContains(relationSearch) }
                    if filtered.isEmpty {
                        Text(relationCandidates.isEmpty ? "No rows available" : "No matching rows")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    } else {
                        ForEach(filtered) { candidate in
                            let isSelected = selectedRelationIds.contains(candidate.id)
                            Button {
                                toggleRelation(candidate.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(candidate.title)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 240)
        .popoverSurface()
    }

    private func toggleRelation(_ rowId: String) {
        if supportsMultipleRelations {
            var ids: [String]
            if case .relationMany(let existing) = value {
                ids = existing
            } else if case .relation(let existing) = value, !existing.isEmpty {
                ids = [existing]
            } else {
                ids = []
            }
            if ids.contains(rowId) {
                ids.removeAll { $0 == rowId }
            } else {
                ids.append(rowId)
            }
            value = ids.isEmpty ? .empty : .relationMany(ids)
        } else {
            if case .relation(let current) = value, current == rowId {
                value = .empty
            } else {
                value = .relation(rowId)
            }
            showRelationPicker = false
        }
    }

    private func presentRelationTargetPicker() {
        if relationDatabases.isEmpty {
            relationDatabases = onListDatabases?() ?? []
        }
        showRelationTargetPicker = true
    }

    private func presentRelationPicker() {
        relationCandidates = onLoadRelationRows?() ?? []
        showRelationPicker = true
    }

    private func openRelatedRow(_ rowId: String) {
        guard let target = definition.config?.target else { return }
        NotificationCenter.default.post(
            name: .inlineDatabaseRowPeek,
            object: nil,
            userInfo: [
                DatabaseNotificationKey.dbPath: target,
                DatabaseNotificationKey.rowId: rowId
            ]
        )
    }

    private func openTargetDatabase() {
        guard let target = definition.config?.target, !target.isEmpty else { return }
        showRelationPicker = false
        NotificationCenter.default.post(
            name: .databaseOpenRequested,
            object: nil,
            userInfo: [DatabaseNotificationKey.dbPath: target]
        )
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

    private var currentDateValue: DatabaseDateValue? {
        guard case .date(let raw) = value else { return nil }
        return DatabaseDateValue.decode(from: raw)
    }

    private func commitDateValue(_ dateValue: DatabaseDateValue?) {
        guard let dateValue else {
            value = .empty
            return
        }
        value = .date(dateValue.rawValue)
    }
}

private enum DatePopoverEndpoint: String, CaseIterable {
    case start
    case end

    var title: String {
        switch self {
        case .start: return "Start"
        case .end: return "End"
        }
    }
}

private struct DatePropertyPopover: View {
    @Binding var value: DatabaseDateValue?

    @State private var displayMonth: Date = Date()
    @State private var activeEndpoint: DatePopoverEndpoint = .start
    @State private var didSyncInitialState = false

    private let calendar = Calendar.current
    private let weekdaySymbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var workingValue: DatabaseDateValue {
        value ?? DatabaseDateValue(start: DatabaseDateValue.canonicalDayString(from: Date()))
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var monthTitle: String {
        Self.monthTitleFormatter.string(from: displayMonth)
    }

    private var selectedDate: Date {
        workingValue.dateForPicker(activeEndpoint == .end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryChips
            monthNavigation
            weekdayHeader
            dayGrid
            Divider()
            controls
            Divider()
            Button("Clear") {
                value = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 336)
        .popoverSurface()
        .onAppear {
            guard !didSyncInitialState else { return }
            syncFromValue()
            didSyncInitialState = true
        }
        .onChange(of: value?.rawValue) { _, _ in
            syncFromValue()
        }
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            summaryChip(for: .start)
            if workingValue.end != nil {
                summaryChip(for: .end)
            }
            Spacer()
        }
    }

    private static let summaryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let summaryDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func summaryChip(for endpoint: DatePopoverEndpoint) -> some View {
        let date = endpoint == .start ? workingValue.startDate : workingValue.endDate
        let label: String
        if let date {
            let formatter = workingValue.includeTime ? Self.summaryDateTimeFormatter : Self.summaryDateFormatter
            label = formatter.string(from: date)
        } else {
            label = endpoint == .start ? "Set start" : "Set end"
        }

        return Button {
            activeEndpoint = endpoint
            if let date {
                displayMonth = monthStart(for: date)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: endpoint == .start ? "calendar" : "calendar.badge.clock")
                    .font(.caption)
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(activeEndpoint == endpoint ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(activeEndpoint == endpoint ? Color.fallbackSurfaceHover : Color.fallbackSurfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                activeEndpoint == endpoint ? Color.fallbackAccent.opacity(0.7) : Color.fallbackBorderColor,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var monthNavigation: some View {
        HStack(spacing: 10) {
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button("Today") {
                let today = Date()
                displayMonth = monthStart(for: today)
                updateDate(
                    activeEndpoint == .start
                        ? workingValue.settingStart(today, calendar: calendar)
                        : workingValue.settingEnd(today, calendar: calendar)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(calendarCells) { cell in
                Button {
                    select(day: cell.date)
                } label: {
                    Text("\(calendar.component(.day, from: cell.date))")
                        .font(.callout)
                        .fontWeight(cell.isSelected ? .semibold : .regular)
                        .foregroundStyle(cell.isSelected ? Color.fallbackAccentFg : (cell.isCurrentMonth ? Color.primary : Color.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(cell.isSelected ? Color.fallbackAccent : (cell.isToday ? Color.fallbackAccentLight.opacity(0.35) : Color.clear))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(cell.isToday && !cell.isSelected ? Color.fallbackAccent.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("End date", isOn: Binding(
                get: { workingValue.end != nil },
                set: { enabled in
                    let updated = workingValue.togglingEndDate(enabled, calendar: calendar)
                    updateDate(updated)
                    activeEndpoint = enabled ? .end : .start
                }
            ))

            Toggle("Include time", isOn: Binding(
                get: { workingValue.includeTime },
                set: { enabled in
                    updateDate(workingValue.togglingIncludeTime(enabled, calendar: calendar))
                }
            ))

            HStack {
                Text("Date format")
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(DatabaseDateFormat.allCases, id: \.rawValue) { format in
                        Button {
                            updateDate(workingValue.settingDateFormat(format))
                        } label: {
                            HStack {
                                Text(format.displayName)
                                if workingValue.dateFormat == format {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(workingValue.dateFormat.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if workingValue.includeTime {
                timeRow(title: "Start time", usesEndDate: false)
                if workingValue.end != nil {
                    timeRow(title: "End time", usesEndDate: true)
                }
            }
        }
        .toggleStyle(.switch)
    }

    private func timeRow(title: String, usesEndDate: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: { workingValue.dateForPicker(usesEndDate) },
                    set: { newValue in
                        if usesEndDate {
                            updateDate(workingValue.settingEnd(newValue, calendar: calendar))
                        } else {
                            updateDate(workingValue.settingStart(newValue, calendar: calendar))
                        }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.field)
            .labelsHidden()
            .frame(width: 116)
        }
    }

    private var calendarCells: [MiniCalendarCell] {
        let monthStart = monthStart(for: displayMonth)
        let startWeekday = calendar.component(.weekday, from: monthStart) - 1
        let gridStart = calendar.date(byAdding: .day, value: -startWeekday, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let selected = calendar.isDate(date, inSameDayAs: selectedDate)
            return MiniCalendarCell(
                offset: offset,
                date: date,
                isCurrentMonth: calendar.isDate(date, equalTo: displayMonth, toGranularity: .month),
                isToday: calendar.isDateInToday(date),
                isSelected: selected
            )
        }
    }

    private func select(day: Date) {
        displayMonth = monthStart(for: day)
        if activeEndpoint == .end {
            updateDate(workingValue.settingEnd(day, calendar: calendar))
        } else {
            updateDate(workingValue.settingStart(day, calendar: calendar))
        }
    }

    private func updateDate(_ newValue: DatabaseDateValue) {
        value = newValue
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func syncFromValue() {
        let anchorDate = selectedDate
        displayMonth = monthStart(for: anchorDate)
        if workingValue.end == nil {
            activeEndpoint = .start
        }
    }
}

private struct MiniCalendarCell: Identifiable {
    let offset: Int
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    var id: Int { offset }
}

// MARK: - Relation Flow Layout

private struct RelationFlowLayout: Layout {
    var spacing: CGFloat = 4

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxW, sizes: cache.sizes)
        guard !rows.isEmpty else { return .zero }
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(rows.count - 1) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxW = bounds.width
        let rows = computeRows(maxWidth: maxW, sizes: cache.sizes)
        var y = bounds.minY
        var subviewIndex = 0
        for row in rows {
            var x = bounds.minX
            for _ in 0..<row.count {
                guard subviewIndex < cache.sizes.count else { break }
                let size = cache.sizes[subviewIndex]
                let clamped = min(size.width, maxW - (x - bounds.minX))
                subviews[subviewIndex].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: max(clamped, 0), height: size.height)
                )
                x += clamped + spacing
                subviewIndex += 1
            }
            y += row.height + spacing
        }
    }

    private func computeRows(maxWidth: CGFloat, sizes: [CGSize]) -> [(count: Int, height: CGFloat)] {
        var rows: [(count: Int, height: CGFloat)] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var currentCount = 0
        for size in sizes {
            let rowWidth = min(size.width, maxWidth)
            if currentCount > 0 && currentWidth + spacing + rowWidth > maxWidth {
                rows.append((count: currentCount, height: currentHeight))
                currentWidth = rowWidth
                currentHeight = size.height
                currentCount = 1
            } else {
                currentWidth += (currentCount > 0 ? spacing : 0) + rowWidth
                currentHeight = max(currentHeight, size.height)
                currentCount += 1
            }
        }
        if currentCount > 0 {
            rows.append((count: currentCount, height: currentHeight))
        }
        return rows
    }
}
