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
    var onLoadRelationRows: ((PropertyDefinition) -> [RelationRowCandidate])?
    var onListDatabases: (() -> [RelationDatabaseCandidate])?
    var onSetRelationTarget: ((String, String) -> Void)?
    var onAddProperty: ((PropertyType) -> Void)?
    var onRenameProperty: ((String, String) -> Void)?
    var onDeleteProperty: ((String) -> Void)?
    var onChangePropertyType: ((String, PropertyType) -> Void)?
    var showBreadcrumb: Bool = true
    var autoFocusTitle: Bool = false
    var fullWidth: Bool = false
    var dbPath: String = ""
    var templates: [DatabaseTemplate] = []
    var onApplyTemplate: ((DatabaseTemplate) -> Void)?
    var onNewTemplate: (() -> Void)?

    @Environment(\.workspacePath) private var workspacePath
    @State private var editingTitle: String = ""
    @State private var bodyDocument: BlockDocument?
    @FocusState private var isTitleFocused: Bool

    private var rowTitle: String {
        row.title(schema: schema)
    }

    private var storedTitle: String {
        guard let titleProp = schema.titleProperty,
              let value = row.properties[titleProp.id],
              case .text(let text) = value else {
            return ""
        }
        return text
    }

    private var propertyLabelColumnWidth: CGFloat {
        let longestName = schema.properties
            .filter { $0.type != .title }
            .map(\.name.count)
            .max() ?? 0
        let estimatedWidth = CGFloat(longestName) * 8.5 + 16
        return min(max(100, estimatedWidth), 180)
    }

    private var titleFont: Font {
        .system(size: EditorTypography.scaled(34), weight: .bold)
    }

    /// Whether the row is empty (no title, no non-empty properties, no body).
    private var isRowEmpty: Bool {
        let titleEmpty = storedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let bodyEmpty = row.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let propsEmpty = row.properties.values.allSatisfy { val in
            switch val {
            case .empty: return true
            case .text(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: return false
            }
        }
        return titleEmpty && bodyEmpty && propsEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showBreadcrumb {
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
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(rowTitle)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title + properties
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("New Page", text: $editingTitle, axis: .vertical)
                        .lineLimit(1...5)
                        .onSubmit { persistTitle() }
                        .font(titleFont)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onChange(of: editingTitle) { _, _ in
                            persistTitle()
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(schema.properties.filter({ $0.type != .title })) { prop in
                                PropertyRowView(
                                    prop: prop,
                                    row: $row,
                                    propertyLabelColumnWidth: propertyLabelColumnWidth,
                                    onSave: onSave,
                                    onAddOption: onAddOption,
                                    onUpdateOption: onUpdateOption,
                                    onDeleteOption: onDeleteOption,
                                    onLoadRelationRows: onLoadRelationRows,
                                    onListDatabases: onListDatabases,
                                    onSetRelationTarget: onSetRelationTarget,
                                    onRenameProperty: onRenameProperty,
                                    onDeleteProperty: onDeleteProperty,
                                    onChangePropertyType: onChangePropertyType
                                )
                            }

                            if onAddProperty != nil {
                                addPropertyRow
                            }

                            if !templates.isEmpty, isRowEmpty {
                                templateSection
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)

                    // Body — block editor
                    if let bodyDocument {
                        BlockEditorView(
                            document: bodyDocument,
                            onTextChange: {
                                row.body = bodyDocument.markdown
                                onSave(row)
                            },
                            horizontalPadding: 20
                        )
                    }
                }
                .frame(maxWidth: fullWidth ? .infinity : 720)
                .frame(maxWidth: .infinity, alignment: fullWidth ? .leading : .center)
            }
        }
        .task {
            editingTitle = storedTitle
            initializeBodyDocument()
            if autoFocusTitle {
                await MainActor.run {
                    isTitleFocused = true
                }
            }
        }
        .onChange(of: row.id) { _, _ in
            editingTitle = storedTitle
            initializeBodyDocument()
            if autoFocusTitle {
                Task { isTitleFocused = true }
            }
        }
    }

    private func initializeBodyDocument() {
        let doc = BlockDocument(markdown: row.body)
        if let ws = workspacePath, !ws.isEmpty {
            doc.workspacePath = ws
        } else if !dbPath.isEmpty {
            // Fall back to deriving workspace from dbPath (parent directory)
            doc.workspacePath = (dbPath as NSString).deletingLastPathComponent
        }
        // Wire up onCreateSubPage so cmd+opt+9 works in peek/modal editors.
        let pageDir = doc.workspacePath ?? (dbPath as NSString).deletingLastPathComponent
        doc.onCreateSubPage = { name in
            let sanitized = name.replacingOccurrences(of: "[/\\\\?%*:|\"<>]", with: "-", options: .regularExpression)
            let baseName = sanitized.isEmpty ? "Untitled" : sanitized
            let fm = FileManager.default
            var fileName = "\(baseName).md"
            var counter = 2
            while fm.fileExists(atPath: (pageDir as NSString).appendingPathComponent(fileName)) {
                fileName = "\(baseName) \(counter).md"
                counter += 1
            }
            let filePath = (pageDir as NSString).appendingPathComponent(fileName)
            try? "# \(baseName)\n\n".write(toFile: filePath, atomically: true, encoding: .utf8)
            return fm.fileExists(atPath: filePath) ? filePath : nil
        }
        bodyDocument = doc
    }

    private func persistTitle() {
        guard let titleProp = schema.titleProperty else { return }
        let currentStoredTitle: String
        if let value = row.properties[titleProp.id], case .text(let text) = value {
            currentStoredTitle = text
        } else {
            currentStoredTitle = ""
        }
        guard currentStoredTitle != editingTitle else { return }
        row.properties[titleProp.id] = .text(editingTitle)
        onSave(row)
    }

    @State private var showAddPropertyMenu = false

    private var addPropertyRow: some View {
        Button {
            showAddPropertyMenu = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Add a property")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showAddPropertyMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(PropertyType.allCases, id: \.rawValue) { type in
                    if type != .title {
                        Button {
                            onAddProperty?(type)
                            showAddPropertyMenu = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: type.systemImageName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(type.rawValue.capitalized)
                                    .font(.callout)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
            .frame(width: 200)
            .popoverSurface()
        }
    }

    @State private var templateHoveredId: String?

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Press \u{23CE} to continue with an empty page, or pick a template")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            ForEach(templates) { template in
                Button {
                    onApplyTemplate?(template)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: template.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(template.name)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(templateHoveredId == template.id ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: Radius.xs))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in templateHoveredId = hovering ? template.id : nil }
            }

            if onNewTemplate != nil {
                Button {
                    onNewTemplate?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("New template")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(templateHoveredId == "_new" ? Color.primary.opacity(0.06) : Color.clear)
                    .clipShape(.rect(cornerRadius: Radius.xs))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in templateHoveredId = hovering ? "_new" : nil }
            }
        }
    }
}

// MARK: - Property Row with split hover zones

private struct PropertyRowView: View {
    let prop: PropertyDefinition
    @Binding var row: DatabaseRow
    let propertyLabelColumnWidth: CGFloat
    var onSave: (DatabaseRow) -> Void
    var onAddOption: ((String, SelectOption) -> Void)?
    var onUpdateOption: ((String, String, String?, String?) -> Void)?
    var onDeleteOption: ((String, String) -> Void)?
    var onLoadRelationRows: ((PropertyDefinition) -> [RelationRowCandidate])?
    var onListDatabases: (() -> [RelationDatabaseCandidate])?
    var onSetRelationTarget: ((String, String) -> Void)?
    var onRenameProperty: ((String, String) -> Void)?
    var onDeleteProperty: ((String) -> Void)?
    var onChangePropertyType: ((String, PropertyType) -> Void)?

    @State private var labelHovered = false
    @State private var valueHovered = false
    @State private var showPropertyMenu = false
    @State private var editingName = ""

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Property label — separate hover, click opens settings
            Button {
                editingName = prop.name
                showPropertyMenu = true
            } label: {
                Text(prop.name)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: propertyLabelColumnWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(labelHovered || showPropertyMenu ? Color.primary.opacity(0.05) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { labelHovered = $0 }
            .floatingPopover(isPresented: $showPropertyMenu, arrowEdge: .bottom) {
                propertySettingsPopover
            }

            // Value cell — separate hover, click activates editor
            let propValue = Binding<PropertyValue>(
                get: { row.properties[prop.id] ?? .empty },
                set: { newVal in
                    row.properties[prop.id] = newVal
                    onSave(row)
                }
            )
            PropertyEditorView(
                definition: prop,
                value: propValue,
                compact: false,
                onAddOption: onAddOption,
                onUpdateOption: onUpdateOption,
                onDeleteOption: onDeleteOption,
                onLoadRelationRows: prop.type == .relation
                    ? { onLoadRelationRows?(prop) ?? [] } : nil,
                onListDatabases: prop.type == .relation
                    ? { onListDatabases?() ?? [] } : nil,
                onSetRelationTarget: prop.type == .relation
                    ? onSetRelationTarget : nil
            )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(valueHovered ? Color.primary.opacity(0.04) : Color.clear)
                )
                .onHover { valueHovered = $0 }
        }
    }

    private var propertySettingsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rename field
            TextField("Property name", text: $editingName)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .focusEffectDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onSubmit {
                    let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != prop.name {
                        onRenameProperty?(prop.id, trimmed)
                    }
                    showPropertyMenu = false
                }

            Divider().padding(.vertical, 2)

            // Change type
            Menu {
                ForEach(PropertyType.allCases, id: \.rawValue) { type in
                    if type != prop.type && type != .title {
                        Button {
                            onChangePropertyType?(prop.id, type)
                            showPropertyMenu = false
                        } label: {
                            Label(type.rawValue.capitalized, systemImage: type.systemImageName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Edit property")
                        .font(.callout)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Divider().padding(.vertical, 2)

            // Delete property
            Button {
                onDeleteProperty?(prop.id)
                showPropertyMenu = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("Delete property")
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 220)
        .popoverSurface()
    }
}
