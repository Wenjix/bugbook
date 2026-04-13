import SwiftUI
import DahsoCore

struct DatabaseRowModalView: View {
    let dbPath: String
    let rowId: String
    var autoFocusTitle: Bool = false
    var onClose: () -> Void
    var onOpenFullPage: () -> Void

    @State private var vm: DatabaseRowViewModel
    @Environment(\.workspacePath) private var workspacePath

    init(dbPath: String, rowId: String, autoFocusTitle: Bool = false, onClose: @escaping () -> Void, onOpenFullPage: @escaping () -> Void) {
        self.dbPath = dbPath
        self.rowId = rowId
        self.autoFocusTitle = autoFocusTitle
        self.onClose = onClose
        self.onOpenFullPage = onOpenFullPage
        _vm = State(initialValue: DatabaseRowViewModel(dbPath: dbPath, origin: "rowModal"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { onOpenFullPage() } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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

            if let error = vm.error {
                RowLoadErrorView(message: error, buttonLabel: "Close") { onClose() }
            } else if vm.schema != nil, vm.row != nil {
                vm.rowPageView(
                    onBack: { onClose() },
                    autoFocusTitle: autoFocusTitle,
                    workspacePath: workspacePath,
                    templates: vm.schema?.templates ?? [],
                    onApplyTemplate: { template in
                        applyTemplate(template)
                    },
                    onNewTemplate: {
                        createNewTemplate()
                    },
                    onSaveAsTemplate: {
                        saveCurrentRowAsTemplate()
                    }
                )
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task { vm.loadData(rowId: rowId) }
        .onChange(of: rowId) { _, _ in vm.loadData(rowId: rowId) }
        .onChange(of: dbPath) { _, newDbPath in
            vm.flushAndCancel()
            vm = DatabaseRowViewModel(dbPath: newDbPath, origin: "rowModal")
            vm.loadData(rowId: rowId)
        }
        .onDisappear {
            vm.flushAndCancel()
            if vm.didEdit {
                vm.postChangeNotification()
            }
        }
    }

    private func applyTemplate(_ template: DatabaseTemplate) {
        guard var currentRow = vm.row, let schema = vm.schema else { return }
        for (key, value) in template.defaultProperties {
            currentRow.properties[key] = value
        }
        currentRow.body = template.body
        vm.debouncedSave(currentRow, schema: schema)
    }

    private func createNewTemplate() {
        vm.createTemplate(name: "Untitled")
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
