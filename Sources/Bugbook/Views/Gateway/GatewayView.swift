import SwiftUI
import BugbookCore

/// Navigation targets for Gateway quick links.
enum GatewayLink {
    case calendar
    case graph
    case meetings
    case database(path: String)
    case terminal
}

/// Native mission-control dashboard — the home screen of Bugbook.
/// Shows live workspace state: databases with status breakdowns, ticket counts, and quick-nav links.
struct GatewayView: View {
    var appState: AppState
    var workspacePath: String?
    var mailService: MailService
    var onNavigateToFile: (String) -> Void
    var onOpenGatewayLink: (GatewayLink) -> Void

    @State private var viewModel = GatewayViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        HomeView(
            appState: appState,
            workspacePath: workspacePath,
            mailService: mailService,
            onNavigateToFile: onNavigateToFile,
            onOpenGatewayLink: onOpenGatewayLink
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Home")
                .font(.system(size: Typography.title2, weight: .semibold))

            Spacer()

            Text(formattedDate)
                .font(.system(size: Typography.body))
                .foregroundStyle(.secondary)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Ticket Overview

    @ViewBuilder
    private var ticketOverview: some View {
        if !viewModel.ticketSummary.statusCounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tickets")
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    statBadge(
                        label: "Total",
                        value: "\(viewModel.ticketSummary.total)",
                        color: .primary
                    )

                    ForEach(sortedStatuses, id: \.0) { status, count in
                        statBadge(
                            label: status,
                            value: "\(count)",
                            color: colorForStatus(status)
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var sortedStatuses: [(String, Int)] {
        viewModel.ticketSummary.statusCounts.sorted { a, b in
            statusOrder(a.key) < statusOrder(b.key)
        }
    }

    // MARK: - Quick Links

    private var quickLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Links")
                .font(.system(size: Typography.bodySmall, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickLinkButton(icon: "calendar", label: "Today") {
                    NotificationCenter.default.post(name: .openDailyNote, object: nil)
                }
                quickLinkButton(icon: "calendar.badge.clock", label: "Calendar") {
                    onOpenGatewayLink(.calendar)
                }
                quickLinkButton(icon: "point.3.connected.trianglepath.dotted", label: "Graph") {
                    onOpenGatewayLink(.graph)
                }
                quickLinkButton(icon: "waveform", label: "Meetings") {
                    onOpenGatewayLink(.meetings)
                }
            }
        }
    }

    private func quickLinkButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: Typography.bodySmall))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Databases Grid

    @ViewBuilder
    private var databasesGrid: some View {
        if !viewModel.databases.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Databases")
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.databases) { db in
                        databaseCard(db)
                    }
                }
            }
        }
    }

    private func databaseCard(_ db: GatewayViewModel.DatabaseSummary) -> some View {
        Button {
            onOpenGatewayLink(.database(path: db.path))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(db.name)
                        .font(.system(size: Typography.body, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(db.rowCount)")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(Opacity.light))
                        .clipShape(Capsule())
                }

                if !db.statusCounts.isEmpty {
                    statusBar(db.statusCounts)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Bar

    private func statusBar(_ counts: [String: Int]) -> some View {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return AnyView(EmptyView()) }

        let sorted = counts.sorted { statusOrder($0.key) < statusOrder($1.key) }

        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(sorted, id: \.key) { status, count in
                        let fraction = CGFloat(count) / CGFloat(total)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForStatus(status))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
        )
    }

    // MARK: - Stat Badge

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: Typography.title3, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: Typography.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private func refresh() {
        if let workspace = workspacePath {
            viewModel.scan(workspacePath: workspace)
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("done") || lower.contains("complete") || lower.contains("closed") {
            return StatusColor.success
        }
        if lower.contains("progress") || lower.contains("doing") || lower.contains("active") || lower.contains("review") {
            return StatusColor.active
        }
        if lower.contains("block") || lower.contains("stuck") {
            return StatusColor.blocked
        }
        if lower.contains("cancel") || lower.contains("wont") {
            return StatusColor.cancelled
        }
        if lower.contains("todo") || lower.contains("backlog") || lower.contains("queued") || lower.contains("not started") {
            return StatusColor.info
        }
        return StatusColor.neutral
    }

    private func statusOrder(_ status: String) -> Int {
        let lower = status.lowercased()
        if lower.contains("progress") || lower.contains("doing") || lower.contains("active") { return 0 }
        if lower.contains("review") { return 1 }
        if lower.contains("block") || lower.contains("stuck") { return 2 }
        if lower.contains("todo") || lower.contains("backlog") || lower.contains("queued") || lower.contains("not started") { return 3 }
        if lower.contains("done") || lower.contains("complete") || lower.contains("closed") { return 4 }
        if lower.contains("cancel") { return 5 }
        return 3
    }
}
