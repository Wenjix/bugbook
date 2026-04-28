import SwiftUI

struct BrowserNewTabPage: View {
    let chrome: BrowserChromeConfiguration
    let greetingTitle: String
    let quickLaunchItems: [BrowserQuickLaunchItem]
    let recentHistory: [BrowserRecentVisit]
    let suggestions: [BrowserSuggestionItem]
    let tabColor: (BrowserRecentVisit) -> Color
    let recentVisitSubtitle: (BrowserRecentVisit) -> String
    let onSubmit: () -> Void
    let onSelectSuggestion: (BrowserSuggestionItem) -> Void
    let onOpenQuickLaunch: (BrowserQuickLaunchItem) -> Void
    let onOpenVisit: (BrowserRecentVisit) -> Void

    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if chrome.showsNewTabGreeting {
                VStack(spacing: 4) {
                    Text(greetingTitle)
                        .font(.system(size: 28, weight: .semibold))
                    Text("Search the web or your notes from one place.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search the web or your notes...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .accessibilityIdentifier("browser-new-tab-search")
                .focused($isSearchFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.primary.opacity(0.05))
                )
                .onSubmit(onSubmit)

            if isSearchFocused && !suggestions.isEmpty {
                BrowserSuggestionList(suggestions: suggestions, onSelect: onSelectSuggestion)
                    .frame(maxWidth: 520)
            }

            if chrome.showsNewTabQuickLaunch, !quickLaunchItems.isEmpty {
                FlowLayout(spacing: 10) {
                    ForEach(quickLaunchItems) { item in
                        Button {
                            onOpenQuickLaunch(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon.isEmpty ? "globe" : item.icon)
                                    .font(.system(size: 12, weight: .medium))
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 620)
            }

            if chrome.showsNewTabRecentVisits, !recentHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(recentHistory.prefix(8)) { visit in
                            Button {
                                onOpenVisit(visit)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(tabColor(visit))
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(visit.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(recentVisitSubtitle(visit))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .fill(Color.primary.opacity(0.03))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
