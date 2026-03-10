import SwiftUI

struct TemplatePickerView: View {
    let templates: [FileEntry]
    let onSelect: (FileEntry) -> Void
    let onDismiss: () -> Void
    let onCreateTemplate: (() -> Void)?
    @State private var hoveredIndex: Int?
    @State private var createHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Choose a template")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Close", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if templates.isEmpty {
                Text("No templates yet.\nCreate your first template from any note.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(templates.enumerated(), id: \.element.id) { index, template in
                            let displayName = template.name.hasSuffix(".md")
                                ? String(template.name.dropLast(3))
                                : template.name

                            Button(action: { onSelect(template) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Text(displayName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(hoveredIndex == index ? Color.primary.opacity(0.06) : Color.clear)
                                .clipShape(.rect(cornerRadius: 6))
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

            if let onCreateTemplate {
                Divider()

                Button(action: onCreateTemplate) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("Save current note as template")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(createHovered ? Color.primary.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in createHovered = hovering }
            }
        }
        .frame(width: 260)
        .popoverSurface(cornerRadius: Radius.lg)
    }
}
