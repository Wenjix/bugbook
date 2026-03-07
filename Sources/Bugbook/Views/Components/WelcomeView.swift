import SwiftUI

struct WelcomeView: View {
    var onNewNote: () -> Void
    var onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("BugbookLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)

            VStack(spacing: 6) {
                Text("Bugbook")
                    .font(.system(size: 24, weight: .bold))
                Text("Local-first notes for agents and humans")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 10) {
                Button(action: onNewNote) {
                    Label("New Note", systemImage: "doc.badge.plus")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onOpenFolder) {
                    Label("Open Folder", systemImage: "folder")
                        .frame(width: 140)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
    }
}
