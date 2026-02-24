import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Theme") {
                HStack(spacing: 16) {
                    ThemeCard(
                        label: "Light",
                        isSelected: appState.settings.theme == .light,
                        sidebarColor: Color(hex: "f0f0f0"),
                        editorColor: .white,
                        lineColor: Color(hex: "d0d0d0")
                    ) {
                        appState.settings.theme = .light
                    }

                    ThemeCard(
                        label: "Dark",
                        isSelected: appState.settings.theme == .dark,
                        sidebarColor: Color(hex: "1a1a1a"),
                        editorColor: Color(hex: "252525"),
                        lineColor: Color(hex: "444444")
                    ) {
                        appState.settings.theme = .dark
                    }

                    ThemeCard(
                        label: "System",
                        isSelected: appState.settings.theme == .system,
                        sidebarColor: nil,
                        editorColor: nil,
                        lineColor: nil
                    ) {
                        appState.settings.theme = .system
                    }
                }
            }
        }
    }
}

// MARK: - Theme preview card

private struct ThemeCard: View {
    let label: String
    let isSelected: Bool
    let sidebarColor: Color?
    let editorColor: Color?
    let lineColor: Color?
    let action: () -> Void

    // System card shows a split light/dark preview
    private var isSystem: Bool { sidebarColor == nil }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Mini app preview
                if isSystem {
                    systemPreview
                } else {
                    normalPreview
                }

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var normalPreview: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!)
                    .frame(width: 24, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!)
                    .frame(width: 18, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!)
                    .frame(width: 22, height: 3)
            }
            .padding(6)
            .frame(width: 44, height: 64)
            .background(sidebarColor)

            // Editor
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!)
                    .frame(width: 40, height: 4)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!.opacity(0.5))
                    .frame(width: 52, height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(lineColor!.opacity(0.5))
                    .frame(width: 36, height: 3)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 64)
            .background(editorColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .frame(width: 120, height: 64)
    }

    private var systemPreview: some View {
        HStack(spacing: 0) {
            // Light half
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "d0d0d0"))
                        .frame(width: 14, height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "d0d0d0"))
                        .frame(width: 10, height: 3)
                }
                .padding(4)
                .frame(width: 22, height: 64)
                .background(Color(hex: "f0f0f0"))

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "d0d0d0"))
                        .frame(width: 24, height: 4)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "d0d0d0").opacity(0.5))
                        .frame(width: 30, height: 3)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 64)
                .background(Color.white)
            }
            .frame(width: 60)
            .clipped()

            // Dark half
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "444444"))
                        .frame(width: 14, height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "444444"))
                        .frame(width: 10, height: 3)
                }
                .padding(4)
                .frame(width: 22, height: 64)
                .background(Color(hex: "1a1a1a"))

                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "444444"))
                        .frame(width: 24, height: 4)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: "444444").opacity(0.5))
                        .frame(width: 30, height: 3)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 64)
                .background(Color(hex: "252525"))
            }
            .frame(width: 60)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .frame(width: 120, height: 64)
    }
}
