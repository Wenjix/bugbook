import SwiftUI
import DahsoCore

/// Modal for editing a database row template. Follows the same pattern as DatabaseRowModalView
/// but shows a banner identifying it as a template editor.
struct DatabaseTemplateEditorModal: View {
    let dbPath: String
    let schema: DatabaseSchema
    @Binding var template: DatabaseTemplate
    var onSave: (DatabaseTemplate) -> Void
    var onDelete: ((String) -> Void)?
    var onClose: () -> Void

    @State private var editingTitle: String = ""
    @State private var bodyDocument: BlockDocument?
    @FocusState private var isTitleFocused: Bool
    @State private var showAddPropertyMenu = false

    @Environment(\.workspacePath) private var workspacePath

    private var propertyLabelColumnWidth: CGFloat {
        let longestName = schema.properties
            .filter { $0.type != .title }
            .map(\.name.count)
            .max() ?? 0
        let estimatedWidth = CGFloat(longestName) * 8.5 + 16
        return min(max(100, estimatedWidth), 180)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                if onDelete != nil {
                    Button {
                        onDelete?(template.id)
                        onClose()
                    } label: {
                        Label("Delete template", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                Button { onClose() } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Template banner
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                Text("You're editing a template in \(schema.name)")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Template name (acts as title)
                        TextField("Template name", text: $editingTitle, axis: .vertical)
                            .lineLimit(1...3)
                            .font(.system(size: EditorTypography.scaled(34), weight: .bold))
                            .textFieldStyle(.plain)
                            .focused($isTitleFocused)
                            .onChange(of: editingTitle) { _, newValue in
                                template.name = newValue
                                onSave(template)
                            }

                        // Property defaults
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                                TemplatePropertyRow(
                                    prop: prop,
                                    value: Binding(
                                        get: { template.defaultProperties[prop.id] ?? .empty },
                                        set: { newVal in
                                            template.defaultProperties[prop.id] = newVal
                                            onSave(template)
                                        }
                                    ),
                                    propertyLabelColumnWidth: propertyLabelColumnWidth
                                )
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)

                    // Body editor
                    if let bodyDocument {
                        BlockEditorView(
                            document: bodyDocument,
                            onTextChange: {
                                template.body = bodyDocument.markdown
                                onSave(template)
                            },
                            horizontalPadding: 20
                        )
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: 880, maxHeight: 700)
        .background(Elevation.popoverBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Elevation.popoverBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(
            color: Elevation.shadowColor.opacity(0.18),
            radius: 24,
            y: Elevation.shadowY * 2
        )
        .onTapGesture { }
        .onExitCommand { onClose() }
        .task {
            editingTitle = template.name
            initializeBodyDocument()
            isTitleFocused = true
        }
    }

    private func initializeBodyDocument() {
        let doc = BlockDocument(markdown: template.body)
        if let ws = workspacePath, !ws.isEmpty {
            doc.workspacePath = ws
        } else if !dbPath.isEmpty {
            doc.workspacePath = (dbPath as NSString).deletingLastPathComponent
        }
        bodyDocument = doc
    }
}

// MARK: - Template Property Row (simplified, no rename/delete)

private struct TemplatePropertyRow: View {
    let prop: PropertyDefinition
    @Binding var value: PropertyValue
    let propertyLabelColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(prop.name)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: propertyLabelColumnWidth, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            PropertyEditorView(
                definition: prop,
                value: $value,
                compact: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
    }
}
