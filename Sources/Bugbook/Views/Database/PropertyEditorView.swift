import SwiftUI
import BugbookCore

struct PropertyEditorView: View {
    let definition: PropertyDefinition
    @Binding var value: PropertyValue
    var wrapText: Bool = false
    var compact: Bool = false
    var onAddOption: ((String, SelectOption) -> Void)?
    var onUpdateOption: ((String, String, String?, String?) -> Void)?  // (propId, optionId, newName?, newColor?)
    var onDeleteOption: ((String, String) -> Void)?  // (propId, optionId)

    var body: some View {
        mainEditor
            .databasePointerCursor()
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
            } else if !compact {
                Text("Empty")
                    .font(.body)
                    .foregroundColor(.secondary)
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
            } else if !compact {
                Text("Empty")
                    .font(.body)
                    .foregroundColor(.secondary)
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
        let dateValue = currentDateValue
        let hasDate = dateValue != nil
        let label = dateValue?.displayText(compact: compact) ?? ""
        let horizontalPadding: CGFloat = compact ? 8 : 10
        let verticalPadding: CGFloat = compact ? 4 : 6
        let textFont: Font = compact ? .caption : .body

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
                            .foregroundColor(.secondary)
                        Text(label)
                            .font(textFont)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !compact {
                        Text("Empty")
                            .font(textFont)
                            .foregroundColor(.secondary)
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
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
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
        let textFont: Font = compact ? .callout : .body
        if wrapText {
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(textFont)
                .lineLimit(1...4)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
        } else {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(textFont)
                .lineLimit(1)
                .foregroundColor(.primary)
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
            .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 336)
        .background(Color.fallbackBgSecondary)
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
            .foregroundColor(activeEndpoint == endpoint ? .primary : .secondary)
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
            .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
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
                        .foregroundColor(cell.isSelected ? .white : (cell.isCurrentMonth ? .primary : .secondary))
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
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.primary)
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
                .foregroundColor(.secondary)
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
