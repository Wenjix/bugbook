import SwiftUI
import BugbookCore

/// Full-height side panel for peeking at a database row from an inline embed.
/// Loads its own schema/row from disk since it lives at the ContentView level.
struct InlineRowPeekPanel: View {
    let dbPath: String
    let rowId: String
    var onClose: () -> Void
    var onOpenFullPage: () -> Void

    @State private var vm: DatabaseRowViewModel
    @State private var showKebabMenu = false
    @Environment(\.workspacePath) private var workspacePath

    init(dbPath: String, rowId: String, onClose: @escaping () -> Void, onOpenFullPage: @escaping () -> Void) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.onClose = onClose
        self.onOpenFullPage = onOpenFullPage
        _vm = State(initialValue: DatabaseRowViewModel(dbPath: dbPath, origin: "peekPanel"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close / expand buttons
            HStack(spacing: 8) {
                Button { onClose() } label: {
                    Label("Close", systemImage: "chevron.right.2")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { onOpenFullPage() } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button("More Options", systemImage: "ellipsis") {
                    showKebabMenu.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .floatingPopover(isPresented: $showKebabMenu) {
                    kebabMenuContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let error = vm.error {
                RowLoadErrorView(message: error) { vm.loadData(rowId: rowId) }
            } else if vm.schema != nil, vm.row != nil {
                vm.rowPageView(
                    onBack: { onClose() },
                    fullWidth: true,
                    workspacePath: workspacePath,
                    templates: vm.schema?.templates ?? [],
                    onApplyTemplate: { template in applyTemplate(template) },
                    onNewTemplate: { vm.createTemplate(name: "Untitled") },
                    onSaveAsTemplate: { saveCurrentRowAsTemplate() }
                )
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            }
        }
        .background(Color.fallbackEditorBg)
        .overlay {
            Rectangle()
                .stroke(Color.fallbackChromeBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task { vm.loadData(rowId: rowId) }
        .onDisappear { vm.flushAndCancel() }
    }

    @ViewBuilder
    private var kebabMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            kebabButton(icon: "arrow.up.left.and.arrow.down.right", label: "Open as full page") {
                showKebabMenu = false
                onOpenFullPage()
            }
            kebabButton(icon: "doc.on.doc", label: "Copy file path") {
                showKebabMenu = false
                copyFilePath()
            }
            kebabButton(icon: "doc.badge.plus", label: "Save as template") {
                showKebabMenu = false
                saveCurrentRowAsTemplate()
            }
            kebabButton(icon: "trash", label: "Delete", isDestructive: true) {
                showKebabMenu = false
                deleteCurrentRow()
            }
        }
        .frame(width: 200)
        .padding(.vertical, 4)
        .popoverSurface()
    }

    private func kebabButton(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isDestructive ? Color.red : .secondary)
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(isDestructive ? Color.red : .primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyFilePath() {
        if let path = vm.rowFilePath(rowId: rowId) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }

    private func deleteCurrentRow() {
        guard let row = vm.row else { return }
        vm.deleteRow(row.id)
        onClose()
    }

    private func applyTemplate(_ template: DatabaseTemplate) {
        guard var currentRow = vm.row, let schema = vm.schema else { return }
        for (key, value) in template.defaultProperties {
            currentRow.properties[key] = value
        }
        currentRow.body = template.body
        vm.debouncedSave(currentRow, schema: schema)
    }

    private func saveCurrentRowAsTemplate() {
        guard let row = vm.row, let schema = vm.schema else { return }
        var defaults: [String: PropertyValue] = [:]
        for prop in schema.properties where prop.type != .title {
            if let val = row.properties[prop.id], val != .empty {
                defaults[prop.id] = val
            }
        }
        let titleText: String
        if let titleProp = schema.titleProperty, let val = row.properties[titleProp.id], case .text(let t) = val {
            titleText = t
        } else {
            titleText = "Untitled"
        }
        vm.createTemplate(
            name: "\(titleText) template",
            defaultProperties: defaults,
            body: row.body
        )
    }
}
