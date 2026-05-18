import SwiftUI

struct BrowserChromeBar<ActionMenu: View>: View {
    let chrome: BrowserChromeConfiguration
    let securityIconName: String
    let canGoBack: Bool
    let canGoForward: Bool
    let isCurrentPageSavable: Bool
    let saveMessage: String?
    let quickLaunchItems: [BrowserQuickLaunchItem]
    let suggestions: [BrowserSuggestionItem]
    let onBack: () -> Void
    let onForward: () -> Void
    let onSubmitOmnibar: () -> Void
    let onSave: () -> Void
    let onSelectSuggestion: (BrowserSuggestionItem) -> Void
    let onOpenQuickLaunch: (BrowserQuickLaunchItem) -> Void
    let actionMenu: ActionMenu

    @Binding var omnibarText: String
    @FocusState.Binding var isOmnibarFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if chrome.showsBackForwardButtons {
                    navButton("chevron.left", enabled: canGoBack, action: onBack)
                    navButton("chevron.right", enabled: canGoForward, action: onForward)
                }

                HStack(spacing: 8) {
                    Image(systemName: securityIconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search or enter URL", text: $omnibarText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .accessibilityIdentifier("browser-omnibar")
                        .focused($isOmnibarFocused)
                        .onSubmit(onSubmitOmnibar)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Container.urlBarBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(isOmnibarFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                        )
                )

                if chrome.showsSaveButton {
                    Button(action: onSave) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isCurrentPageSavable)
                }

                actionMenu
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if isOmnibarFocused && !suggestions.isEmpty {
                BrowserSuggestionList(suggestions: suggestions, onSelect: onSelectSuggestion)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }

            if chrome.showsBookmarksBar && !quickLaunchItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickLaunchItems) { item in
                            Button {
                                onOpenQuickLaunch(item)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: item.icon.isEmpty ? "globe" : item.icon)
                                        .font(.system(size: 11, weight: .medium))
                                    Text(item.title)
                                        .font(.system(size: 12))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }

            if let saveMessage, !saveMessage.isEmpty {
                HStack {
                    Text(saveMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(Container.cardBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
