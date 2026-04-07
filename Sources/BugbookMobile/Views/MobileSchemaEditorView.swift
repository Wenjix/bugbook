import SwiftUI
import BugbookCore

struct MobileSchemaEditorView: View {
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var showAddProperty = false

    var body: some View {
        NavigationStack {
            List {
                if let schema = viewState.schema {
                    Section("Properties") {
                        ForEach(schema.properties) { prop in
                            NavigationLink {
                                MobilePropertySettingsView(property: prop, viewState: viewState)
                            } label: {
                                HStack {
                                    Image(systemName: prop.type.systemImageName)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    Text(prop.name)
                                    Spacer()
                                    Text(prop.type.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    Section {
                        Button { showAddProperty = true } label: {
                            Label("Add Property", systemImage: "plus")
                        }
                    }

                    if let views = viewState.schema?.views {
                        Section("Views") {
                            ForEach(views, id: \.id) { view in
                                HStack {
                                    Image(systemName: viewTypeIcon(view.type))
                                        .foregroundStyle(.secondary)
                                    Text(view.name)
                                    Spacer()
                                    if view.id == viewState.activeViewId {
                                        Text("Active")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    viewState.deleteView(views[index].id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schema")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddProperty) {
                MobileAddPropertyView(viewState: viewState)
            }
        }
    }

    private func viewTypeIcon(_ type: ViewType) -> String {
        switch type {
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .kanban: return "rectangle.3.group"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - Property Settings

struct MobilePropertySettingsView: View {
    let property: PropertyDefinition
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var newOptionName: String = ""
    @State private var newOptionColor: String = "blue"

    private let colors = ["blue", "green", "red", "yellow", "purple", "pink", "orange", "teal", "gray"]

    var body: some View {
        Form {
            Section("Name") {
                TextField("Property name", text: $name)
                    .onSubmit {
                        if !name.isEmpty && name != property.name {
                            viewState.renameProperty(property.id, to: name)
                        }
                    }
            }

            Section("Type") {
                LabeledContent("Type") {
                    HStack {
                        Image(systemName: property.type.systemImageName)
                        Text(property.type.rawValue)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if property.type == .select || property.type == .multiSelect {
                Section("Options") {
                    if let options = property.options {
                        ForEach(options) { option in
                            HStack {
                                Circle()
                                    .fill(colorForName(option.color))
                                    .frame(width: 12, height: 12)
                                Text(option.name)
                                Spacer()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewState.deleteSelectOption(property.id, optionId: option.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("New option", text: $newOptionName)
                        Picker("", selection: $newOptionColor) {
                            ForEach(colors, id: \.self) { color in
                                Circle()
                                    .fill(colorForName(color))
                                    .frame(width: 12, height: 12)
                                    .tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        Button("Add") {
                            guard !newOptionName.isEmpty else { return }
                            viewState.addSelectOption(property.id, name: newOptionName, color: newOptionColor)
                            newOptionName = ""
                        }
                        .disabled(newOptionName.isEmpty)
                    }
                }
            }

            if property.type != .title {
                Section {
                    Button("Delete Property", role: .destructive) {
                        viewState.deleteProperty(property.id)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(property.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { name = property.name }
        .onDisappear {
            if !name.isEmpty && name != property.name {
                viewState.renameProperty(property.id, to: name)
            }
        }
    }
}

// MARK: - Add Property

struct MobileAddPropertyView: View {
    var viewState: MobileDatabaseViewState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: PropertyType = .text

    private let availableTypes: [PropertyType] = [
        .text, .number, .select, .multiSelect, .date, .checkbox, .url, .email, .relation, .formula
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Property name", text: $name)

                Section("Type") {
                    ForEach(availableTypes, id: \.rawValue) { propType in
                        Button {
                            type = propType
                        } label: {
                            HStack {
                                Image(systemName: propType.systemImageName)
                                    .frame(width: 24)
                                Text(propType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                Spacer()
                                if type == propType {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Property")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let propName = name.isEmpty ? type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized : name
                        viewState.addProperty(name: propName, type: type)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
