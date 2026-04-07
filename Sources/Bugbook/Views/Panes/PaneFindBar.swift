import SwiftUI

/// Compact find-in-page bar that slides between the chrome bar and document content.
/// Searches all visible block text in the active document pane.
struct PaneFindBar: View {
    @Binding var query: String
    let matchCount: Int
    let currentMatch: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Search field
            TextField("Find...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: Typography.caption))
                .focused($isFieldFocused)
                .onSubmit {
                    if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                        onPrevious()
                    } else {
                        onNext()
                    }
                }
                .onExitCommand { onClose() }
                .frame(minWidth: 120, maxWidth: 220)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs)
                        .fill(Color.fallbackEditorBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.xs)
                                .strokeBorder(Color.fallbackBorderColor, lineWidth: 1)
                        )
                )

            // Match count
            if !query.isEmpty {
                Text(matchCount > 0 ? "\(currentMatch) of \(matchCount)" : "No results")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Previous / Next
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)
            .help("Previous match (Shift+Enter)")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(matchCount == 0)
            .help("Next match (Enter)")

            // Close
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Escape)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.fallbackEditorBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 0.5)
        }
        .onAppear { isFieldFocused = true }
    }
}
