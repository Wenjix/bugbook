import SwiftUI

struct ViewModePickerButton: View {
    @Binding var viewMode: CalendarViewMode
    @State private var showPicker = false

    var body: some View {
        Button(action: { showPicker.toggle() }) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                Text(viewMode.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .floatingPopover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Button(action: {
                        viewMode = mode
                        showPicker = false
                    }) {
                        HStack {
                            if viewMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .frame(width: 16)
                            } else {
                                Color.clear.frame(width: 16, height: 1)
                            }

                            Text(mode.rawValue)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 140)
            .popoverSurface()
        }
    }
}
