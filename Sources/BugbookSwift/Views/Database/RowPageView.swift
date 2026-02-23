import SwiftUI

struct RowPageView: View {
    let schema: DatabaseSchema
    @Binding var row: DatabaseRow
    var onSave: (DatabaseRow) -> Void
    var onBack: () -> Void

    @State private var editingTitle: String = ""

    private var contentMaxWidth: CGFloat {
        row.fullWidth ? .infinity : 720
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

                Text(row.title)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()

                // Full-width toggle
                Toggle(isOn: Binding(
                    get: { row.fullWidth },
                    set: { newVal in
                        row.fullWidth = newVal
                        onSave(row)
                    }
                )) {
                    Text("Full width")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    TextField("Untitled", text: $editingTitle, onCommit: {
                        row.title = editingTitle
                        onSave(row)
                    })
                    .font(.title)
                    .fontWeight(.bold)
                    .textFieldStyle(.plain)

                    // Properties
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(schema.properties) { prop in
                            HStack(alignment: .top) {
                                Text(prop.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 120, alignment: .leading)

                                let propValue = Binding<PropertyValue>(
                                    get: { row.properties[prop.name] ?? .empty },
                                    set: { newVal in
                                        row.properties[prop.name] = newVal
                                        onSave(row)
                                    }
                                )
                                PropertyEditorView(definition: prop, value: propValue)
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
                .frame(maxWidth: contentMaxWidth)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: row.fullWidth ? .leading : .center)
            }
        }
        .onAppear {
            editingTitle = row.title
        }
        .onChange(of: row.id) {
            editingTitle = row.title
        }
    }
}
