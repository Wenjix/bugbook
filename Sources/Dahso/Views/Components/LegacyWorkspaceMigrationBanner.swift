import SwiftUI

struct LegacyWorkspaceMigrationBanner: View {
    let legacyWorkspace: FileSystemService.LegacyWorkspace
    let isMigrating: Bool
    let errorMessage: String?
    var onMigrate: () -> Void
    var onRevealInFinder: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(StatusColor.warning)
                .frame(width: 28, height: 28)
                .background(StatusColor.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: 6) {
                Text("Legacy workspace detected")
                    .font(.system(size: Typography.body, weight: .semibold))

                Text(legacyWorkspace.kind.title)
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(legacyWorkspace.displayPath)
                    .font(.system(size: Typography.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Migrate copies files into the current workspace and skips replacing newer files that already exist there.")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(StatusColor.error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(
                    isMigrating ? "Migrating..." : "Migrate",
                    systemImage: isMigrating ? "arrow.triangle.2.circlepath" : "square.and.arrow.down",
                    action: onMigrate
                )
                .buttonStyle(.borderedProminent)
                .disabled(isMigrating)

                Button("Reveal in Finder", systemImage: "folder", action: onRevealInFinder)
                    .buttonStyle(.bordered)
                    .disabled(isMigrating)

                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .buttonStyle(.bordered)
                    .disabled(isMigrating)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Container.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Container.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Container.cardRadius)
                .stroke(StatusColor.warning.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}
