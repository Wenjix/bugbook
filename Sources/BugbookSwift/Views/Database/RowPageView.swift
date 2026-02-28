import SwiftUI
import BugbookCore

struct RowPageView: View {
    let schema: DatabaseSchema
    @Binding var row: DatabaseRow
    var onSave: (DatabaseRow) -> Void
    var onBack: () -> Void
    var onAddOption: ((String, SelectOption) -> Void)?
    var onUpdateOption: ((String, String, String?, String?) -> Void)?
    var onDeleteOption: ((String, String) -> Void)?

    @State private var editingTitle: String = ""

    private var rowTitle: String {
        row.title(schema: schema)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Breadcrumb / back bar
            HStack(spacing: 4) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(schema.name)
                    }
                    .font(.body)
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(rowTitle)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    TextField("New Page", text: $editingTitle, onCommit: {
                        if let titleProp = schema.titleProperty {
                            row.properties[titleProp.id] = .text(editingTitle)
                            onSave(row)
                        }
                    })
                    .font(.title)
                    .fontWeight(.bold)
                    .textFieldStyle(.plain)

                    // Properties (skip title property — shown above)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                            HStack(alignment: .top) {
                                HStack(spacing: 4) {
                                    Image(systemName: iconForPropertyType(prop.type))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(prop.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 140, alignment: .leading)

                                let propValue = Binding<PropertyValue>(
                                    get: { row.properties[prop.id] ?? .empty },
                                    set: { newVal in
                                        row.properties[prop.id] = newVal
                                        onSave(row)
                                    }
                                )
                                PropertyEditorView(definition: prop, value: propValue, onAddOption: onAddOption, onUpdateOption: onUpdateOption, onDeleteOption: onDeleteOption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 8)

                    Divider()

                    // Body
                    TextEditor(text: Binding(
                        get: { row.body },
                        set: { newVal in
                            row.body = newVal
                            onSave(row)
                        }
                    ))
                    .font(.body)
                    .frame(minHeight: 300)
                }
                .frame(maxWidth: 720)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .task {
            editingTitle = rowTitle
        }
        .onChange(of: row.id) {
            editingTitle = rowTitle
        }
    }

    private func iconForPropertyType(_ type: PropertyType) -> String {
        switch type {
        case .title: return "textformat.abc"
        case .text: return "textformat"
        case .number: return "number"
        case .select: return "tag"
        case .multiSelect: return "tag"
        case .date: return "calendar"
        case .checkbox: return "checkmark.square"
        case .url: return "link"
        case .email: return "envelope"
        case .relation: return "link"
        }
    }
}
