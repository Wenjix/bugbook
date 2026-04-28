import SwiftUI

struct BrowserSavedPageActions: View {
    let savedRecord: SavedWebPageRecord?
    let isCurrentPageSavable: Bool
    let onOpenSavedNote: (SavedWebPageRecord) -> Void
    let onToggleSavedStatus: (SavedWebPageRecord) -> Void
    let onUnsave: (SavedWebPageRecord) -> Void
    let onSave: () -> Void

    @ViewBuilder
    var body: some View {
        if let savedRecord {
            Text(savedRecord.status == .read
                 ? "Saved to \((savedRecord.folderPath as NSString).lastPathComponent)/"
                 : "Saved to view later")
            Button("Open Saved Note") {
                onOpenSavedNote(savedRecord)
            }
            Button(savedRecord.status == .read ? "Mark Read Later" : "Mark Read") {
                onToggleSavedStatus(savedRecord)
            }
            Button("Unsave") {
                onUnsave(savedRecord)
            }
        } else {
            Button("Save to Dahso", action: onSave)
                .disabled(!isCurrentPageSavable)
        }
    }
}
