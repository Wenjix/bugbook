import SwiftUI

struct BrowserActionMenu: View {
    let savedRecord: SavedWebPageRecord?
    let isCurrentPageSavable: Bool
    let isSinglePane: Bool
    let isReadLaterDrawerOpen: Bool
    let readLaterRecords: [SavedWebPageRecord]
    let isLoading: Bool
    let isFindBarVisible: Bool
    let canViewSource: Bool
    let onOpenSavedNote: (SavedWebPageRecord) -> Void
    let onToggleSavedStatus: (SavedWebPageRecord) -> Void
    let onUnsave: (SavedWebPageRecord) -> Void
    let onSave: () -> Void
    let onToggleReadLaterDrawer: () -> Void
    let onOpenReadLaterRecord: (SavedWebPageRecord) -> Void
    let onNewTab: () -> Void
    let onCleanTabs: () -> Void
    let onReloadOrStop: () -> Void
    let onOpenExternalBrowser: () -> Void
    let onPrint: () -> Void
    let onToggleFindBar: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetZoom: () -> Void
    let onOpenMail: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenTerminal: () -> Void
    let onViewSource: () -> Void

    var body: some View {
        Menu {
            BrowserSavedPageActions(
                savedRecord: savedRecord,
                isCurrentPageSavable: isCurrentPageSavable,
                onOpenSavedNote: onOpenSavedNote,
                onToggleSavedStatus: onToggleSavedStatus,
                onUnsave: onUnsave,
                onSave: onSave
            )

            if isSinglePane {
                Button(isReadLaterDrawerOpen ? "Hide View Later Queue" : "Show View Later Queue") {
                    onToggleReadLaterDrawer()
                }
            }

            if !readLaterRecords.isEmpty {
                Menu("View Later Queue") {
                    ForEach(readLaterRecords.prefix(10)) { record in
                        Button(record.title) {
                            onOpenReadLaterRecord(record)
                        }
                    }
                }
            }

            Divider()

            Button("New Browser Page", action: onNewTab)
            Button("Clean Browser Pages", action: onCleanTabs)
            Button(isLoading ? "Stop Loading" : "Reload", action: onReloadOrStop)
            Button("Open in External Browser", action: onOpenExternalBrowser)
            Button("Print", action: onPrint)
            Button(isFindBarVisible ? "Hide Find Bar" : "Find on Page", action: onToggleFindBar)
            Menu("Zoom") {
                Button("Zoom In", action: onZoomIn)
                Button("Zoom Out", action: onZoomOut)
                Button("Actual Size", action: onResetZoom)
            }
            Menu("Quick Pane Switching") {
                Button("Mail", action: onOpenMail)
                Button("Calendar", action: onOpenCalendar)
                Button("Terminal", action: onOpenTerminal)
            }
            if canViewSource {
                Button("View Source", action: onViewSource)
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
