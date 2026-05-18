import SwiftUI
import BugbookCore

struct DatabaseFullSettingsPopover: View {
    let schema: DatabaseSchema
    let state: DatabaseViewState
    @Binding var showVerticalLines: Bool
    let isPinnedToHome: Bool
    let togglePinToHome: () -> Void

    private var nonTitleProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type != .title }
    }

    private var groupableProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .select || $0.type == .multiSelect }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                layoutSection
                Divider()
                filterSection
                Divider()
                sortSection
                groupBySection
                Divider()
                propertySection
                Divider().padding(.top, 4)
                titleVisibilityButton
                tableOptions
                Divider().padding(.top, 4)
                pinButton
                Spacer(minLength: 12)
            }
        }
        .frame(width: DatabaseZoomMetrics.size(280))
        .frame(maxHeight: DatabaseZoomMetrics.size(500))
        .popoverSurface()
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Layout")
            HStack(spacing: 6) {
                ForEach(ViewType.allCases, id: \.rawValue) { type in
                    viewTypeButton(type)
                }
            }
            .padding(.horizontal, DatabaseZoomMetrics.size(12))
            .padding(.bottom, DatabaseZoomMetrics.size(12))
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Filter")
            if let view = state.activeView, !view.filters.isEmpty {
                let conjunction = view.filterGroup?.conjunction ?? .and
                ForEach(Array(view.filters.enumerated()), id: \.element.id) { index, filter in
                    if index > 0 {
                        filterConjunctionButton(conjunction)
                    }
                    filterRow(filter)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            addFilterMenu
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Sort")
            if let view = state.activeView, !view.sorts.isEmpty {
                ForEach(view.sorts) { sort in
                    sortRow(sort)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            addSortMenu
        }
    }

    @ViewBuilder
    private var groupBySection: some View {
        if state.activeView?.type == .table || state.activeView?.type == .kanban {
            Divider()
            sectionHeader("Group by")
            groupByPicker
                .padding(.horizontal, DatabaseZoomMetrics.size(12))
                .padding(.bottom, DatabaseZoomMetrics.size(12))
        }
    }

    private var propertySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Properties")
            ForEach(nonTitleProperties) { property in
                let isHidden = (state.activeView?.hiddenColumns ?? []).contains(property.id)
                visibilityButton(property: property, isHidden: isHidden)
            }
        }
    }

    private var titleVisibilityButton: some View {
        Button { state.updateHideTitle(state.activeView?.hideTitle != true) } label: {
            HStack {
                Text("Show title").font(DatabaseZoomMetrics.font(15))
                Spacer()
                if state.activeView?.hideTitle != true {
                    Image(systemName: "checkmark").font(DatabaseZoomMetrics.font(12)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DatabaseZoomMetrics.size(12))
        .padding(.vertical, DatabaseZoomMetrics.size(3))
    }

    @ViewBuilder
    private var tableOptions: some View {
        if state.activeView?.type == .table {
            toggleButton(title: "Grid lines", isOn: showVerticalLines) {
                showVerticalLines.toggle()
            }
            toggleButton(title: "Wrap cell text", isOn: state.activeView?.wrapCellText == true) {
                state.toggleWrapCellText()
            }
        }
    }

    private var pinButton: some View {
        toggleButton(title: "Pin to Home", isOn: isPinnedToHome, action: togglePinToHome)
    }

    private var addFilterMenu: some View {
        addPropertyMenu(title: "Add filter") { property in
            state.addFilter(propertyId: property.id)
        }
    }

    private var addSortMenu: some View {
        addPropertyMenu(title: "Add sort") { property in
            state.addSort(propertyId: property.id, ascending: true)
        }
    }

    private var groupByPicker: some View {
        let currentGroupId = state.activeView?.groupBy ?? ""
        let currentProperty = groupableProperties.first(where: { $0.id == currentGroupId })

        return Menu {
            Button("None") { state.updateGroupBy("") }
            Divider()
            ForEach(groupableProperties) { property in
                Button {
                    state.updateGroupBy(property.id)
                } label: {
                    HStack {
                        Text(property.name)
                        if property.id == currentGroupId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentProperty?.name ?? "None")
                    .font(DatabaseZoomMetrics.font(12))
                Image(systemName: "chevron.down")
                    .font(DatabaseZoomMetrics.font(11))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func viewTypeButton(_ type: ViewType) -> some View {
        Button {
            if let view = schema.views.first(where: { $0.type == type }) {
                state.activeViewId = view.id
                state.persistActiveView(view.id)
            } else {
                state.addView(type: type)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: iconForViewType(type))
                    .font(DatabaseZoomMetrics.font(16))
                Text(type.rawValue.capitalized)
                    .font(DatabaseZoomMetrics.font(11))
            }
            .frame(width: DatabaseZoomMetrics.size(58), height: DatabaseZoomMetrics.size(48))
            .background(state.activeView?.type == type ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(6)))
            .foregroundStyle(state.activeView?.type == type ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func filterConjunctionButton(_ conjunction: FilterConjunction) -> some View {
        Button {
            state.toggleFilterConjunction()
        } label: {
            Text(conjunction == .and ? "and" : "or")
                .font(DatabaseZoomMetrics.font(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DatabaseZoomMetrics.size(6))
                .padding(.vertical, DatabaseZoomMetrics.size(2))
                .background(Color.primary.opacity(0.06))
                .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func filterRow(_ filter: FilterConfig) -> some View {
        let property = schema.properties.first(where: { $0.id == filter.property })
        let operators = operatorsForType(property?.type ?? .text)

        return HStack(spacing: 6) {
            Menu {
                ForEach(nonTitleProperties) { property in
                    Button(property.name) { state.updateFilter(filter.id, property: property.id, op: nil, value: nil) }
                }
            } label: {
                pillLabel(property?.name ?? "Property", fontSize: 12, isProminent: true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(operators, id: \.0) { (operatorKey, operatorLabel) in
                    Button(operatorLabel) { state.updateFilter(filter.id, property: nil, op: operatorKey, value: nil) }
                }
            } label: {
                pillLabel(labelForOp(filter.op), fontSize: 12)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if opNeedsValue(filter.op) {
                filterValueInput(filter, property: property)
            }

            Spacer()
            removeButton(title: "Remove Filter") { state.removeFilter(filter.id) }
        }
    }

    @ViewBuilder
    private func filterValueInput(_ filter: FilterConfig, property: PropertyDefinition?) -> some View {
        if let property,
           property.type == .select || property.type == .multiSelect,
           let options = property.options {
            Menu {
                ForEach(options) { option in
                    Button(option.name) { state.updateFilter(filter.id, property: nil, op: nil, value: option.id) }
                }
            } label: {
                let displayValue = property.options?.first(where: { $0.id == filter.value })?.name
                    ?? (filter.value.isEmpty ? "Pick value..." : filter.value)
                pillLabel(displayValue, fontSize: 12)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if property?.type == .checkbox {
            Menu {
                Button("Checked") { state.updateFilter(filter.id, property: nil, op: nil, value: "true") }
                Button("Unchecked") { state.updateFilter(filter.id, property: nil, op: nil, value: "false") }
            } label: {
                pillLabel(filter.value == "true" ? "Checked" : filter.value == "false" ? "Unchecked" : "Pick...", fontSize: 12)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            TextField(
                "Value",
                text: Binding(
                    get: { filter.value },
                    set: { state.updateFilter(filter.id, property: nil, op: nil, value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(DatabaseZoomMetrics.font(12))
            .frame(width: DatabaseZoomMetrics.size(120))
        }
    }

    private func sortRow(_ sort: SortConfig) -> some View {
        let property = schema.properties.first(where: { $0.id == sort.property })
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(DatabaseZoomMetrics.font(11))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(nonTitleProperties) { property in
                    Button(property.name) { state.updateSort(sort.id, property: property.id, ascending: nil) }
                }
            } label: {
                pillLabel(property?.name ?? "Property", fontSize: 12, isProminent: true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                state.updateSort(sort.id, property: nil, ascending: !sort.ascending)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                    Text(sort.ascending ? "Ascending" : "Descending")
                }
                .font(DatabaseZoomMetrics.font(12))
                .padding(.horizontal, DatabaseZoomMetrics.size(6))
                .padding(.vertical, DatabaseZoomMetrics.size(3))
                .background(Color.fallbackSurfaceSubtle)
                .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
            }
            .buttonStyle(.plain)

            Spacer()
            removeButton(title: "Remove Sort") { state.removeSort(sort.id) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DatabaseZoomMetrics.font(12))
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DatabaseZoomMetrics.size(12))
            .padding(.top, DatabaseZoomMetrics.size(12))
            .padding(.bottom, DatabaseZoomMetrics.size(6))
    }

    private func addPropertyMenu(title: String, action: @escaping (PropertyDefinition) -> Void) -> some View {
        Menu {
            ForEach(nonTitleProperties) { property in
                Button(property.name) { action(property) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(DatabaseZoomMetrics.font(12))
                Text(title).font(DatabaseZoomMetrics.font(12))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, DatabaseZoomMetrics.size(12))
        .padding(.bottom, DatabaseZoomMetrics.size(12))
    }

    private func visibilityButton(property: PropertyDefinition, isHidden: Bool) -> some View {
        Button { state.toggleColumnVisibility(property.id) } label: {
            HStack {
                Text(property.name).font(DatabaseZoomMetrics.font(15))
                Spacer()
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(DatabaseZoomMetrics.font(12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DatabaseZoomMetrics.size(12))
        .padding(.vertical, DatabaseZoomMetrics.size(3))
    }

    private func toggleButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(DatabaseZoomMetrics.font(15))
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").font(DatabaseZoomMetrics.font(12)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DatabaseZoomMetrics.size(12))
        .padding(.vertical, DatabaseZoomMetrics.size(3))
    }

    private func pillLabel(_ text: String, fontSize: CGFloat, isProminent: Bool = false) -> some View {
        Text(text)
            .font(DatabaseZoomMetrics.font(fontSize))
            .fontWeight(isProminent ? .medium : .regular)
            .padding(.horizontal, DatabaseZoomMetrics.size(6))
            .padding(.vertical, DatabaseZoomMetrics.size(3))
            .background(Color.fallbackSurfaceSubtle)
            .clipShape(.rect(cornerRadius: DatabaseZoomMetrics.size(4)))
    }

    private func removeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(DatabaseZoomMetrics.font(12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct DatabaseInlineSettingsPopover: View {
    let schema: DatabaseSchema
    let state: DatabaseViewState

    private var nonTitleProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type != .title }
    }

    private var groupableProperties: [PropertyDefinition] {
        schema.properties.filter { $0.type == .select || $0.type == .multiSelect }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                layoutSection
                Divider()
                filterSection
                Divider()
                sortSection
                groupBySection
                Divider()
                propertySection
                Divider().padding(.top, 4)
                titleVisibilityButton
                tableOptions
                Spacer(minLength: 12)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
        .popoverSurface()
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Layout")
            HStack(spacing: 6) {
                ForEach([ViewType.table, .list, .kanban, .calendar], id: \.rawValue) { type in
                    viewTypeButton(type)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Filter")
            if let view = state.activeView, !view.filters.isEmpty {
                ForEach(view.filters) { filter in
                    filterRow(filter)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            addFilterMenu
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Sort")
            if let view = state.activeView, !view.sorts.isEmpty {
                ForEach(view.sorts) { sort in
                    sortRow(sort)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            addSortMenu
        }
    }

    @ViewBuilder
    private var groupBySection: some View {
        if state.activeView?.type == .table || state.activeView?.type == .kanban {
            Divider()
            sectionHeader("Group by")
            groupByPicker
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var propertySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Properties")
            ForEach(nonTitleProperties) { property in
                let isHidden = (state.activeView?.hiddenColumns ?? []).contains(property.id)
                visibilityButton(property: property, isHidden: isHidden)
            }
        }
    }

    private var titleVisibilityButton: some View {
        Button { state.updateHideTitle(state.activeView?.hideTitle != true) } label: {
            HStack {
                Text("Show title").font(.callout)
                Spacer()
                if state.activeView?.hideTitle != true {
                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var tableOptions: some View {
        if state.activeView?.type == .table {
            toggleButton(title: "Wrap cell text", isOn: state.activeView?.wrapCellText == true) {
                state.toggleWrapCellText()
            }
        }
    }

    private var addFilterMenu: some View {
        addPropertyMenu(title: "Add filter") { property in
            state.addFilter(propertyId: property.id)
        }
    }

    private var addSortMenu: some View {
        addPropertyMenu(title: "Add sort") { property in
            state.addSort(propertyId: property.id, ascending: true)
        }
    }

    private var groupByPicker: some View {
        let currentGroupId = state.activeView?.groupBy ?? ""
        let currentProperty = groupableProperties.first(where: { $0.id == currentGroupId })

        return Menu {
            Button("None") { state.updateGroupBy("") }
            Divider()
            ForEach(groupableProperties) { property in
                Button {
                    state.updateGroupBy(property.id)
                } label: {
                    HStack {
                        Text(property.name)
                        if property.id == currentGroupId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentProperty?.name ?? "None")
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func viewTypeButton(_ type: ViewType) -> some View {
        Button {
            if let view = schema.views.first(where: { $0.type == type }) {
                state.activeViewId = view.id
            } else {
                state.addView(type: type)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: iconForViewType(type))
                    .font(.system(size: 16))
                Text(type.rawValue.capitalized)
                    .font(.caption2)
            }
            .frame(width: 58, height: 48)
            .background(state.activeView?.type == type ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
            .clipShape(.rect(cornerRadius: 6))
            .foregroundStyle(state.activeView?.type == type ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func filterRow(_ filter: FilterConfig) -> some View {
        let property = schema.properties.first(where: { $0.id == filter.property })
        let operators = operatorsForType(property?.type ?? .text)

        return HStack(spacing: 6) {
            Menu {
                ForEach(nonTitleProperties) { property in
                    Button(property.name) { state.updateFilter(filter.id, property: property.id, op: nil, value: nil) }
                }
            } label: {
                pillLabel(property?.name ?? "Property", isProminent: true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(operators, id: \.0) { (operatorKey, operatorLabel) in
                    Button(operatorLabel) { state.updateFilter(filter.id, property: nil, op: operatorKey, value: nil) }
                }
            } label: {
                pillLabel(labelForOp(filter.op))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if opNeedsValue(filter.op) {
                filterValueInput(filter, property: property)
            }

            Spacer()
            removeButton(title: "Remove Filter") { state.removeFilter(filter.id) }
        }
    }

    @ViewBuilder
    private func filterValueInput(_ filter: FilterConfig, property: PropertyDefinition?) -> some View {
        if let property,
           property.type == .select || property.type == .multiSelect,
           let options = property.options {
            Menu {
                ForEach(options) { option in
                    Button(option.name) { state.updateFilter(filter.id, property: nil, op: nil, value: option.id) }
                }
            } label: {
                let displayValue = property.options?.first(where: { $0.id == filter.value })?.name
                    ?? (filter.value.isEmpty ? "Pick value..." : filter.value)
                pillLabel(displayValue)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if property?.type == .checkbox {
            Menu {
                Button("Checked") { state.updateFilter(filter.id, property: nil, op: nil, value: "true") }
                Button("Unchecked") { state.updateFilter(filter.id, property: nil, op: nil, value: "false") }
            } label: {
                pillLabel(filter.value == "true" ? "Checked" : filter.value == "false" ? "Unchecked" : "Pick...")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            TextField(
                "Value",
                text: Binding(
                    get: { filter.value },
                    set: { state.updateFilter(filter.id, property: nil, op: nil, value: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(width: 120)
        }
    }

    private func sortRow(_ sort: SortConfig) -> some View {
        let property = schema.properties.first(where: { $0.id == sort.property })
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(nonTitleProperties) { property in
                    Button(property.name) { state.updateSort(sort.id, property: property.id, ascending: nil) }
                }
            } label: {
                pillLabel(property?.name ?? "Property", isProminent: true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                state.updateSort(sort.id, property: nil, ascending: !sort.ascending)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                    Text(sort.ascending ? "Ascending" : "Descending")
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.fallbackSurfaceSubtle)
                .clipShape(.rect(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            Spacer()
            removeButton(title: "Remove Sort") { state.removeSort(sort.id) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    private func addPropertyMenu(title: String, action: @escaping (PropertyDefinition) -> Void) -> some View {
        Menu {
            ForEach(nonTitleProperties) { property in
                Button(property.name) { action(property) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.caption)
                Text(title).font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func visibilityButton(property: PropertyDefinition, isHidden: Bool) -> some View {
        Button { state.toggleColumnVisibility(property.id) } label: {
            HStack {
                Text(property.name).font(.callout)
                Spacer()
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func toggleButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func pillLabel(_ text: String, isProminent: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(isProminent ? .medium : .regular)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.fallbackSurfaceSubtle)
            .clipShape(.rect(cornerRadius: 4))
    }

    private func removeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

private func operatorsForType(_ type: PropertyType) -> [(String, String)] {
    switch type {
    case .text, .title, .url, .email:
        return [("equals", "is"), ("not_equals", "is not"), ("contains", "contains"),
                ("not_contains", "doesn't contain"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .number:
        return [("equals", "="), ("not_equals", "\u{2260}"), ("greater_than", ">"), ("less_than", "<"),
                ("greater_than_or_equal", "\u{2265}"), ("less_than_or_equal", "\u{2264}"),
                ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .select, .multiSelect:
        return [("equals", "is"), ("not_equals", "is not"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .date:
        return [("equals", "is"), ("greater_than", "is after"), ("less_than", "is before"),
                ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .checkbox:
        return [("is_checked", "is checked"), ("is_not_checked", "is not checked")]
    case .relation:
        return [("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .formula:
        return [("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .lookup:
        return [("equals", "is"), ("not_equals", "is not"), ("contains", "contains"),
                ("not_contains", "doesn't contain"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    case .rollup:
        return [("equals", "is"), ("not_equals", "is not"), ("is_empty", "is empty"), ("is_not_empty", "is not empty")]
    }
}

private func labelForOp(_ op: String) -> String {
    switch op {
    case "equals": return "is"
    case "not_equals": return "is not"
    case "contains": return "contains"
    case "not_contains": return "doesn't contain"
    case "greater_than": return ">"
    case "less_than": return "<"
    case "greater_than_or_equal": return "\u{2265}"
    case "less_than_or_equal": return "\u{2264}"
    case "is_checked": return "is checked"
    case "is_not_checked": return "is not checked"
    case "is_empty": return "is empty"
    case "is_not_empty": return "is not empty"
    default: return op
    }
}

private func opNeedsValue(_ op: String) -> Bool {
    op != "is_empty" && op != "is_not_empty" && op != "is_checked" && op != "is_not_checked"
}

private func iconForViewType(_ type: ViewType) -> String {
    switch type {
    case .table: "tablecells"
    case .kanban: "rectangle.stack"
    case .list: "list.bullet"
    case .calendar: "calendar"
    }
}
