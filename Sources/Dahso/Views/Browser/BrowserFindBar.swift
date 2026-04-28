import SwiftUI

struct BrowserFindBar: View {
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onQueryChange: (String) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find on page", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: query) { _, value in
                    onQueryChange(value)
                }

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty)

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(query.isEmpty)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.fallbackTabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 1)
        }
    }
}
