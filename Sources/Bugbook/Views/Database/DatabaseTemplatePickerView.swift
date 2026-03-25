import SwiftUI
import BugbookCore

/// Template picker shown when creating a new row in a database that has templates.
/// Displays "Empty" and available templates, plus a "New template" option.
struct DatabaseTemplatePickerView: View {
    let templates: [DatabaseTemplate]
    let onSelectEmpty: () -> Void
    let onSelectTemplate: (DatabaseTemplate) -> Void
    let onNewTemplate: () -> Void
    let onDismiss: () -> Void

    @State private var hoveredId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Press \u{23CE} to continue with an empty page, or pick a template")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    // Empty option
                    templateButton(
                        id: "_empty",
                        icon: "doc",
                        label: "Empty",
                        action: onSelectEmpty
                    )

                    // Template list
                    ForEach(templates) { template in
                        templateButton(
                            id: template.id,
                            icon: template.icon,
                            label: template.name,
                            action: { onSelectTemplate(template) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 200)

            Divider()

            // New template
            Button(action: onNewTemplate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("New template")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredId == "_new" ? Color.primary.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in hoveredId = hovering ? "_new" : nil }
        }
        .frame(width: 280)
        .popoverSurface(cornerRadius: Radius.lg)
    }

    private func templateButton(id: String, icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(hoveredId == id ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(.rect(cornerRadius: Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredId = hovering ? id : nil }
    }
}
