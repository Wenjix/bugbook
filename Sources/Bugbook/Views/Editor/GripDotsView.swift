import SwiftUI

/// 2×3 grid of dots used as a drag handle, similar to Notion's grip icon.
struct GripDotsView: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundColor(.secondary)
    }
}
