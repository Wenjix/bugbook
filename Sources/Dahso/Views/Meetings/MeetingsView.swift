import SwiftUI
import DahsoCore

/// Meeting dashboard — lists past meetings, "New Meeting" creates a meeting page and navigates there.
/// No recording UI here; recording happens in the MeetingPageView.
struct MeetingsView: View {
    var appState: AppState
    @Bindable var viewModel: MeetingsViewModel
    var meetingNoteService: MeetingNoteService
    var onNavigateToFile: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            recentRecordings
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.fallbackEditorBg)
        .onAppear {
            if let workspace = appState.workspacePath {
                viewModel.scan(workspace: workspace)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Meetings")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Button(action: createNewMeeting) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("New Meeting")
                        .font(.system(size: Typography.caption, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(Opacity.subtle))
                .clipShape(.rect(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Recent Recordings

    @ViewBuilder
    private var recentRecordings: some View {
        let groups = viewModel.groupedMeetings
        if groups.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text("No meetings yet")
                    .font(.system(size: Typography.bodySmall))
                    .foregroundStyle(.quaternary)
                Text("Create a new meeting to get started")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.bucket) { group in
                        sectionDivider(group.bucket.rawValue)
                        ForEach(group.meetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Actions

    private func createNewMeeting() {
        guard let workspace = appState.workspacePath else { return }

        let effectiveTitle = "New Meeting"

        guard let path = meetingNoteService.createAdHocMeetingPage(
            title: effectiveTitle, date: Date(), workspace: workspace
        ) else { return }

        // Signal that the new page should auto-start recording when it loads
        appState.pendingAutoRecordPath = path
        onNavigateToFile(path)
        viewModel.scan(workspace: workspace)
    }

    // MARK: - Components

    private func sectionDivider(_ title: String) -> some View {
        Text(title)
            .font(.system(size: Typography.caption2, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func meetingRow(_ meeting: DiscoveredMeeting) -> some View {
        Button(action: { onNavigateToFile(meeting.filePath) }) {
            HStack(spacing: 8) {
                Text(formattedTime(meeting.timestamp))
                    .font(.system(size: Typography.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 60, alignment: .leading)

                Text(meeting.title)
                    .font(.system(size: Typography.body))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverHighlight())
    }

    // MARK: - Helpers

    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yest"
        } else {
            return Self.shortDateFormatter.string(from: date)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// MARK: - Hover Highlight

private struct HoverHighlight: View {
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }
    }
}
