import SwiftUI

struct TemplatePickerView: View {
    let templates: [FileEntry]
    let onSelect: (FileEntry) -> Void
    let onDismiss: () -> Void
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Choose a template")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if templates.isEmpty {
                Text("No templates found.\nCreate .md files in the Templates/ folder.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            let displayName = template.name.hasSuffix(".md")
                                ? String(template.name.dropLast(3))
                                : template.name

                            Button(action: { onSelect(template) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    Text(displayName)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(hoveredIndex == index ? Color.primary.opacity(0.06) : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in hoveredIndex = hovering ? index : nil }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
