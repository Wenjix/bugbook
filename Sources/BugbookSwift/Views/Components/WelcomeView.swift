import SwiftUI

struct WelcomeView: View {
    var onNewNote: () -> Void
    var onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Bugbook")
                .font(.system(size: 28, weight: .bold))

            Text("Local-first notes and knowledge workspace")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                Button(action: onNewNote) {
                    Label("New Note", systemImage: "doc.badge.plus")
                        .frame(width: 160)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onOpenFolder) {
                    Label("Open Folder", systemImage: "folder")
                        .frame(width: 160)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
