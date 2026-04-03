import SwiftUI

struct HomeBottomZone: View {
    let vm: HomeViewModel
    let onNavigateToFile: (String) -> Void

    @State private var showingPinPicker = false

    var body: some View {
        VStack(spacing: 12) {
            pinnedSection
        }
    }

    private var pinnedSection: some View {
        surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("PINNED")
                    Spacer()
                    if !unpinnedDatabases.isEmpty {
                        Button {
                            showingPinPicker = true
                        } label: {
                            Text("+")
                                .font(.system(size: Typography.caption, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.fallbackTextMuted)
                                .frame(minWidth: 24, minHeight: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .floatingPopover(isPresented: $showingPinPicker) {
                            pinPickerPopover
                        }
                    }
                }

                if vm.pinnedDatabases.isEmpty {
                    Text("Pin a database to track it here.")
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(Color.fallbackTextSecondary)
                } else {
                    ForEach(vm.pinnedDatabases) { database in
                        PinnedDatabaseCard(database: database) {
                            onNavigateToFile(database.path)
                        }
                        .contextMenu {
                            Button("Unpin") {
                                vm.togglePin(database.path)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var unpinnedDatabases: [DatabaseSummary] {
        let pinnedPaths = Set(vm.pinnedDatabases.map(\.path))
        return vm.allDatabases.filter { !pinnedPaths.contains($0.path) }
    }

    private var pinPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(unpinnedDatabases) { db in
                Button {
                    vm.togglePin(db.path)
                    showingPinPicker = false
                } label: {
                    Text(db.name)
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 180)
        .popoverSurface()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Typography.caption2, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Color.fallbackTextSecondary)
    }

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PinnedDatabaseCard: View {
    let database: DatabaseSummary
    let action: () -> Void

    @State private var pulseScale = 1.0

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(database.name)
                        .font(.system(size: Typography.body, weight: .semibold))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .lineLimit(1)

                    if database.agentActiveCount > 0 {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(TagColor.color(for: "blue"))
                                .frame(width: 6, height: 6)
                                .scaleEffect(pulseScale)
                            Text("\(database.agentActiveCount) active")
                                .font(.system(size: Typography.caption2, weight: .semibold))
                        }
                        .foregroundStyle(TagColor.color(for: "blue"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TagColor.color(for: "blue").opacity(0.1))
                        .clipShape(.rect(cornerRadius: Radius.sm))
                    }

                    Spacer(minLength: 0)
                }

                Text(database.narrativeLine)
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(Color.fallbackTextSecondary)

                statusBar
                    .frame(height: 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fallbackEditorBg.opacity(0.55))
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.fallbackBorderColor.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }

    private var statusBar: some View {
        GeometryReader { geometry in
            let total = max(1, database.reviewCount + database.todoCount + database.inProgressCount + database.doneCount)

            HStack(spacing: 1) {
                segment(count: database.reviewCount, total: total, width: geometry.size.width, opacity: 1.0)
                segment(count: database.todoCount, total: total, width: geometry.size.width, opacity: 0.55)
                segment(count: database.inProgressCount, total: total, width: geometry.size.width, opacity: 0.35)
                segment(count: database.doneCount, total: total, width: geometry.size.width, opacity: 0.08)
            }
            .clipShape(.capsule)
        }
    }

    private func segment(count: Int, total: Int, width: CGFloat, opacity: Double) -> some View {
        Rectangle()
            .fill(TagColor.color(for: "blue").opacity(opacity))
            .frame(width: max(count == 0 ? 0 : 6, width * CGFloat(count) / CGFloat(total)))
    }
}
