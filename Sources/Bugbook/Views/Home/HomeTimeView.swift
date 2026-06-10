import SwiftUI

struct HomeTimeView: View {
    let vm: HomeViewModel
    var onOpenGatewayLink: ((GatewayLink) -> Void)?

    @State private var morningPage = 0
    @State private var prepRunning = false

    var body: some View {
        switch vm.timeState {
        case .morning:
            morningView
        case .midday:
            middayView
        case .evening:
            eveningView
        }
    }

    // MARK: - Morning

    private var morningView: some View {
        VStack(spacing: 10) {
            // Stacked card depth illusion
            ZStack(alignment: .bottom) {
                if morningCards.count >= 3 {
                    // Back card (deepest)
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.fallbackSurfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.fallbackBorderColor.opacity(0.5), lineWidth: 1)
                        )
                        .scaleEffect(x: 0.95, y: 1, anchor: .bottom)
                        .offset(y: 10)
                        .opacity(0.35)
                }

                if morningCards.count >= 3 {
                    // Middle card
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.fallbackSurfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.fallbackBorderColor.opacity(0.7), lineWidth: 1)
                        )
                        .scaleEffect(x: 0.975, y: 1, anchor: .bottom)
                        .offset(y: 5)
                        .opacity(0.6)
                }

                // Main card content
                VStack(alignment: .leading, spacing: 0) {
                    morningCardContent
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fallbackSurfaceSubtle)
                .clipShape(.rect(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { // Card pagination — not a primary action, VoiceOver uses the "All caught up" Button
                    guard morningCards.count > 1 else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        morningPage = (morningPage + 1) % morningCards.count
                    }
                }
            }
            .padding(.bottom, morningCards.count > 1 ? 8 : 0)

            // Dots — only show when there are multiple pages
            if morningCards.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<morningCards.count, id: \.self) { i in
                        Circle()
                            .fill(i == morningPage ? TagColor.color(for: "blue") : Color.fallbackBorderColor)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Which card types are available, in display order.
    private enum MorningCard { case overnight, todaysShape, stale }

    private var morningCards: [MorningCard] {
        var cards: [MorningCard] = []
        if vm.overnightCount > 0 { cards.append(.overnight) }
        cards.append(.todaysShape)
        if !vm.staleItems.isEmpty { cards.append(.stale) }
        return cards
    }

    @ViewBuilder
    private var morningCardContent: some View {
        let cards = morningCards
        let card = morningPage < cards.count ? cards[morningPage] : .todaysShape

        switch card {
        case .overnight:
            cardLabel("OVERNIGHT")
                .padding(.bottom, 5)
            Text("\(vm.overnightCount) thing\(vm.overnightCount == 1 ? "" : "s") while you were out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.overnightItems) { item in
                    activityRow(item)
                }
            }

            Divider()
                .padding(.top, 12)
                .padding(.bottom, 10)

            HStack {
                Spacer()
                Button("All caught up →") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.timeState = .midday
                        vm.markSeen()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: Typography.caption2, weight: .medium))
                .foregroundStyle(TagColor.color(for: "blue"))
            }

        case .todaysShape:
            cardLabel("TODAY'S SHAPE")
                .padding(.bottom, 5)
            Text("\(vm.totalEventsToday) event\(vm.totalEventsToday == 1 ? "" : "s") today")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 4) {
                activityRow(HomeViewModel.ActivityLine(text: "First free gap: \(vm.firstFreeGapLabel)", isAgentActivity: false))
                if vm.humanMeetingsToday > 0 {
                    activityRow(HomeViewModel.ActivityLine(text: "\(vm.humanMeetingsToday) meeting\(vm.humanMeetingsToday == 1 ? "" : "s") scheduled", isAgentActivity: false))
                }
            }

        case .stale:
            cardLabel("STALE ITEMS")
                .padding(.bottom, 5)
            Text("\(vm.staleItems.count) need attention")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.fallbackTextPrimary)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.staleItems, id: \.self) { item in
                    activityRow(HomeViewModel.ActivityLine(text: item, isAgentActivity: false))
                }
            }
        }
    }

    // MARK: - Midday

    private var middayView: some View {
        VStack(spacing: 8) {
            // Delta bar
            surface {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 4) {
                        Text("\(vm.deltaCount) thing\(vm.deltaCount == 1 ? "" : "s")")
                            .font(.system(size: Typography.caption2, weight: .medium))
                            .foregroundStyle(Color.fallbackTextSecondary)
                        Text("since \(vm.lastSeenDate.formatted(.dateTime.hour().minute()))")
                            .font(.system(size: Typography.caption2))
                            .foregroundStyle(Color.fallbackTextMuted)
                    }

                    if vm.deltaItems.isEmpty {
                        Text("Nothing new since you last looked.")
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(Color.fallbackTextSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(vm.deltaItems) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("·")
                                        .foregroundStyle(Color.fallbackTextMuted)
                                    Text(item.text)
                                        .foregroundStyle(item.isAgentActivity ? TagColor.color(for: "blue") : Color.fallbackTextSecondary)
                                }
                                .font(.system(size: Typography.caption))
                                .lineLimit(2)
                            }
                        }
                    }
                }
            }

            // Agent blocked card
            if vm.blockedAgentCount > 0 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(TagColor.color(for: "blue"))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("AGENT NEEDS YOU")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(TagColor.color(for: "blue"))

                        Text(vm.blockedAgentTask ?? "A blocked agent is waiting.")
                            .font(.system(size: Typography.bodySmall, weight: .medium))
                            .foregroundStyle(Color.fallbackTextPrimary)

                        if let finishedAt = vm.blockedAgentFinishedAt {
                            Text("finished \(finishedAt)")
                                .font(.system(size: Typography.caption2))
                                .foregroundStyle(Color.fallbackTextSecondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TagColor.color(for: "blue").opacity(0.05))
                .clipShape(.rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(TagColor.color(for: "blue").opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Evening

    private var prepSubtitle: String {
        var parts: [String] = []
        if !vm.carryOverItems.isEmpty {
            parts.append("\(vm.carryOverItems.count) ticket\(vm.carryOverItems.count == 1 ? "" : "s") to stage")
        }
        if vm.needsReplyCount > 0 {
            parts.append("draft \(vm.needsReplyCount) repl\(vm.needsReplyCount == 1 ? "y" : "ies")")
        }
        if vm.activeAgentCount > 0 {
            parts.append("\(vm.activeAgentCount) agent\(vm.activeAgentCount == 1 ? "" : "s") running")
        } else {
            parts.append("queue agents")
        }
        return parts.isEmpty ? "Nothing to prep" : parts.joined(separator: " · ")
    }

    private var youHasActivity: Bool {
        vm.humanCompletedToday > 0 || vm.humanMeetingsToday > 0
    }

    private var agentsHasActivity: Bool {
        vm.agentCompletedToday > 0 || vm.activeAgentCount > 0
    }

    private var eveningView: some View {
        VStack(spacing: 8) {
            // YOU / AGENTS split
            HStack(spacing: 0) {
                // YOU column
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOU")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.fallbackTextMuted)

                    if !youHasActivity {
                        Text("No ticket activity today")
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(Color.fallbackTextSecondary)
                    } else {
                        if vm.humanCompletedToday > 0 {
                            eveningStat(
                                value: "\(vm.humanCompletedToday)",
                                caption: vm.humanCompletedToday == 1 ? "ticket closed" : "tickets closed",
                                color: Color.fallbackTextPrimary
                            )
                        }
                        if vm.humanMeetingsToday > 0 {
                            eveningStat(
                                value: "\(vm.humanMeetingsToday)",
                                caption: vm.humanMeetingsToday == 1 ? "meeting" : "meetings",
                                color: Color.fallbackTextPrimary
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                Rectangle()
                    .fill(Color.fallbackBorderColor)
                    .frame(width: 1)

                // AGENTS column
                VStack(alignment: .leading, spacing: 10) {
                    Text("AGENTS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(TagColor.color(for: "blue").opacity(0.6))

                    if !agentsHasActivity {
                        Text("No agent activity today")
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(Color.fallbackTextSecondary)
                    } else {
                        if vm.agentCompletedToday > 0 {
                            eveningStat(
                                value: "\(vm.agentCompletedToday)",
                                caption: vm.agentCompletedToday == 1 ? "ticket closed" : "tickets closed",
                                color: TagColor.color(for: "blue")
                            )
                        }
                        if vm.activeAgentCount > 0 {
                            eveningStat(
                                value: "\(vm.activeAgentCount)",
                                caption: "active",
                                color: TagColor.color(for: "blue")
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .background(Color.fallbackSurfaceSubtle)
            .clipShape(.rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
            )

            // Carry-over
            surface {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel("CARRYING OVER")
                    if vm.carryOverItems.isEmpty {
                        Text("Nothing leaking into tomorrow.")
                            .font(.system(size: Typography.caption))
                            .foregroundStyle(Color.fallbackTextSecondary)
                    } else {
                        let grouped = Dictionary(grouping: vm.carryOverItems, by: \.databaseName)
                        let sortedKeys = grouped.keys.sorted()
                        ForEach(sortedKeys, id: \.self) { dbName in
                            if sortedKeys.count > 1 {
                                Text(dbName)
                                    .font(.system(size: Typography.caption2, weight: .medium))
                                    .foregroundStyle(Color.fallbackTextMuted)
                                    .padding(.top, sortedKeys.first == dbName ? 0 : 4)
                            }
                            ForEach(grouped[dbName] ?? []) { item in
                                HStack(spacing: 8) {
                                    Text("→")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.fallbackTextMuted)
                                    Text(item.title)
                                        .font(.system(size: Typography.caption))
                                        .foregroundStyle(Color.fallbackTextSecondary)
                                }
                            }
                        }
                    }
                }
            }

            // Prep launchpad
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prep for tomorrow")
                        .font(.system(size: Typography.caption, weight: .medium))
                        .foregroundStyle(Color.fallbackTextPrimary)
                    Text(prepSubtitle)
                        .font(.system(size: Typography.caption2))
                        .foregroundStyle(Color.fallbackTextSecondary)
                }
                Spacer()
                Button {
                    prepRunning = true
                } label: {
                    Text(prepRunning ? "Starting…" : "Run overnight prep")
                        .font(.system(size: Typography.caption2, weight: .semibold))
                        .foregroundStyle(Color.fallbackEditorBg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(prepRunning ? Color.fallbackTextMuted : TagColor.color(for: "blue"))
                        )
                }
                .buttonStyle(.plain)
                .disabled(prepRunning)
            }
            .padding(12)
            .background(Color.fallbackSurfaceSubtle)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
            )
        }
    }

    // MARK: - Shared helpers

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fallbackSurfaceSubtle)
        .clipShape(.rect(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
        )
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color.fallbackTextMuted)
    }

    private func activityRow(_ item: HomeViewModel.ActivityLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.isAgentActivity ? TagColor.color(for: "blue") : Color.fallbackTextMuted)
                .frame(width: 3, height: 3)
                .padding(.top, 5)
            Text(item.text)
                .font(.system(size: Typography.caption))
                .foregroundStyle(item.isAgentActivity ? TagColor.color(for: "blue") : Color.fallbackTextSecondary)
                .lineLimit(2)
        }
    }

    private func eveningStat(value: String, caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(caption)
                .font(.system(size: Typography.caption2))
                .foregroundStyle(Color.fallbackTextSecondary)
        }
    }
}
