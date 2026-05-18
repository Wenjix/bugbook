import SwiftUI

/// Single banner that aggregates all detected legacy workspaces. The previous design
/// stacked one banner per detected location, which was visually noisy and forced users to
/// reason about distinctions ("Old Bugbook application support data" vs "Bugbook application
/// support data") they don't need to care about. Migrate runs the operation across every
/// detected location; per-location detail and Reveal-in-Finder live behind a Details
/// disclosure for power users.
struct LegacyWorkspaceMigrationBanner: View {
    let legacyWorkspaces: [FileSystemService.LegacyWorkspace]
    let isMigrating: Bool
    let errorMessage: String?
    var onMigrateAll: () -> Void
    var onRevealInFinder: (FileSystemService.LegacyWorkspace) -> Void
    var onDismissAll: () -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StatusColor.warning)
                    .frame(width: 28, height: 28)
                    .background(StatusColor.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 4) {
                    Text("We found data from a previous version of Bugbook")
                        .font(.system(size: Typography.body, weight: .semibold))
                    Text(summary)
                        .font(.system(size: Typography.bodySmall))
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
                        isMigrating ? "Migrating…" : "Migrate",
                        systemImage: isMigrating ? "arrow.triangle.2.circlepath" : "square.and.arrow.down",
                        action: onMigrateAll
                    )
                    .buttonStyle(.borderedProminent)
                    .disabled(isMigrating)

                    Button("Dismiss", action: onDismissAll)
                        .buttonStyle(.borderless)
                        .disabled(isMigrating)
                }
            }

            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(legacyWorkspaces) { ws in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ws.kind.title)
                                    .font(.system(size: Typography.bodySmall, weight: .medium))
                                Text(ws.displayPath)
                                    .font(.system(size: Typography.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 12)
                            Button("Reveal", systemImage: "folder") { onRevealInFinder(ws) }
                                .buttonStyle(.borderless)
                                .disabled(isMigrating)
                        }
                    }
                    Text("Migrate copies files into the current workspace and skips replacing newer files that already exist there. The legacy data stays in place.")
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Text("Details")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(.secondary)
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

    private var summary: String {
        legacyWorkspaces.count == 1
            ? "1 location can be migrated into your current workspace."
            : "\(legacyWorkspaces.count) locations can be migrated into your current workspace."
    }
}
