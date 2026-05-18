import SwiftUI

struct BrowserSuggestionList: View {
    let suggestions: [BrowserSuggestionItem]
    let onSelect: (BrowserSuggestionItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, 38)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Container.cardBg)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
