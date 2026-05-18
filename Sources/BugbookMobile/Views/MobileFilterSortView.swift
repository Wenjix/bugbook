import SwiftUI
import BugbookCore

struct MobileFilterSortView: View {
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSortProperty: String = ""
    @State private var sortAscending = true
    @State private var showAddFilter = false

    var body: some View {
        NavigationStack {
            Form {
                sortSection
                filterSection
                viewOptionsSection
            }
            .navigationTitle("View Options")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sort

    private var sortSection: some View {
        Section("Sort") {
            if let schema = viewState.schema {
                Picker("Sort by", selection: $selectedSortProperty) {
                    Text("None").tag("")
                    ForEach(schema.properties) { prop in
                        Text(prop.name).tag(prop.id)
                    }
                }
                .onChange(of: selectedSortProperty) { _, newValue in
                    if newValue.isEmpty {
                        viewState.clearViewSorts()
                    } else {
                        viewState.updateViewSort(propertyId: newValue, ascending: sortAscending)
                    }
                }

                if !selectedSortProperty.isEmpty {
                    Picker("Direction", selection: $sortAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .onChange(of: sortAscending) { _, newValue in
                        viewState.updateViewSort(propertyId: selectedSortProperty, ascending: newValue)
                    }
                }
            }
        }
        .onAppear {
            if let sort = viewState.activeView?.sorts.first {
                selectedSortProperty = sort.property
                sortAscending = sort.ascending
            }
        }
    }

    // MARK: - Filters

    @ViewBuilder
    private var filterSection: some View {
        Section("Filters") {
            if let filters = viewState.activeView?.filters, !filters.isEmpty {
                ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
                    let propName = viewState.schema?.properties.first(where: { $0.id == filter.property })?.name ?? filter.property
                    HStack {
                        Text(propName)
                            .font(.subheadline)
                        Text(filter.op)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(filter.value)
                            .font(.subheadline)
                    }
                }

                Button("Clear All Filters", role: .destructive) {
                    viewState.clearViewFilters()
                }
            } else {
                Text("No filters")
                    .foregroundStyle(.secondary)
            }

            Button("Add Filter") { showAddFilter = true }
        }
        .sheet(isPresented: $showAddFilter) {
            MobileAddFilterView(viewState: viewState)
        }
    }

    // MARK: - View Options

    @ViewBuilder
    private var viewOptionsSection: some View {
        if let schema = viewState.schema, let activeView = viewState.activeView {
            Section("Columns") {
                ForEach(schema.properties) { prop in
                    if prop.type != .title {
                        Toggle(prop.name, isOn: Binding(
                            get: { !(activeView.hiddenColumns ?? []).contains(prop.id) },
                            set: { _ in viewState.toggleColumnVisibility(prop.id) }
                        ))
                    }
                }
            }

            if activeView.type == .kanban {
                Section("Group By") {
                    let selectProps = schema.properties.filter { $0.type == .select }
                    Picker("Group by", selection: Binding(
                        get: { activeView.groupBy ?? "" },
                        set: { viewState.setViewGroupBy($0.isEmpty ? nil : $0) }
                    )) {
                        Text("None").tag("")
                        ForEach(selectProps) { prop in
                            Text(prop.name).tag(prop.id)
                        }
                    }
                }
            }

            if activeView.type == .calendar {
                Section("Date Property") {
                    let dateProps = schema.properties.filter { $0.type == .date }
                    if dateProps.isEmpty {
                        Text("No date properties available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dateProps) { prop in
                            Text(prop.name)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Add Filter Sheet

struct MobileAddFilterView: View {
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var propertyId = ""
    @State private var filterOperator = "equals"
    @State private var filterValue = ""

    private let operators = ["equals", "not_equals", "contains", "not_contains", "is_empty", "is_not_empty"]

    var body: some View {
        NavigationStack {
            Form {
                if let schema = viewState.schema {
                    Picker("Property", selection: $propertyId) {
                        Text("Select...").tag("")
                        ForEach(schema.properties) { prop in
                            Text(prop.name).tag(prop.id)
                        }
                    }

                    Picker("Operator", selection: $filterOperator) {
                        ForEach(operators, id: \.self) { op in
                            Text(op.replacingOccurrences(of: "_", with: " ")).tag(op)
                        }
                    }

                    if filterOperator != "is_empty" && filterOperator != "is_not_empty" {
                        if let prop = viewState.schema?.properties.first(where: { $0.id == propertyId }),
                           (prop.type == .select || prop.type == .multiSelect),
                           let options = prop.options {
                            Picker("Value", selection: $filterValue) {
                                Text("Select...").tag("")
                                ForEach(options) { option in
                                    Text(option.name).tag(option.id)
                                }
                            }
                        } else {
                            TextField("Value", text: $filterValue)
                        }
                    }
                }
            }
            .navigationTitle("Add Filter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !propertyId.isEmpty else { return }
                        viewState.addViewFilter(propertyId: propertyId, op: filterOperator, value: filterValue)
                        dismiss()
                    }
                    .disabled(propertyId.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - New View Sheet

struct MobileNewViewSheet: View {
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var viewName = ""
    @State private var viewType: ViewType = .table

    var body: some View {
        NavigationStack {
            Form {
                TextField("View name", text: $viewName)

                Picker("Type", selection: $viewType) {
                    Text("Table").tag(ViewType.table)
                    Text("List").tag(ViewType.list)
                    Text("Kanban").tag(ViewType.kanban)
                    Text("Calendar").tag(ViewType.calendar)
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("New View")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = viewName.isEmpty ? "\(viewType)".capitalized : viewName
                        viewState.addView(name: name, type: viewType)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
