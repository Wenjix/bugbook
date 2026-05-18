import SwiftUI

struct BrowserReadLaterDrawer: View {
    let records: [SavedWebPageRecord]
    let relativeDateText: (SavedWebPageRecord) -> String
    let onOpenRecord: (SavedWebPageRecord) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Read Later")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(records) { record in
                        Button {
                            onOpenRecord(record)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(record.status == .unread ? Color.orange : Color.teal)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(relativeDateText(record))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.fallbackEditorBg)
    }
}
