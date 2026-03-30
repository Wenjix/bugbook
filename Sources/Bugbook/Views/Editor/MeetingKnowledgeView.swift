import SwiftUI

/// Collapsible panel that surfaces relevant workspace knowledge during meetings.
/// Designed to be embedded in the page editor when live meeting context is active.
/// Queries the WorkspaceKnowledgeService periodically based on transcript/note content.
struct MeetingKnowledgeView: View {
    var knowledgeService: WorkspaceKnowledgeService
    /// The current text to search against (e.g. recent transcript or note content).
    let sourceText: String
    /// Called when the user taps a result to navigate to its source page.
    var onNavigate: ((String) -> Void)?

    @State private var isExpanded = true
    @State private var results: [KnowledgeResult] = []
    @State private var queryTask: Task<Void, Never>?
    @State private var lastQueryText = ""

    var body: some View {
        if !results.isEmpty || !sourceText.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded && !results.isEmpty {
                    resultsList
                }
            }
            .background(Color.fallbackSurfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(Color.fallbackDividerColor, lineWidth: 1)
            )
            .padding(.horizontal, 76)
            .padding(.vertical, 8)
            .onAppear { scheduleQuery() }
            .onChange(of: sourceText) { _, _ in scheduleQuery() }
            .onDisappear { queryTask?.cancel() }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: "sparkles")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(Color.fallbackAccent)

                Text("Related Notes")
                    .font(.system(size: Typography.caption, weight: .medium))
                    .foregroundStyle(Color.fallbackTextSecondary)

                Spacer()

                if !results.isEmpty {
                    Text("\(results.count)")
                        .font(.system(size: Typography.caption2, weight: .medium))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.fallbackBadgeBg)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, 12)

            ForEach(results) { result in
                resultRow(result)
            }
        }
    }

    private func resultRow(_ result: KnowledgeResult) -> some View {
        Button {
            onNavigate?(result.filePath)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.fallbackTextSecondary)

                    Text(result.title)
                        .font(.system(size: Typography.bodySmall, weight: .medium))
                        .foregroundStyle(Color.fallbackTextPrimary)
                        .lineLimit(1)
                }

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.system(size: Typography.caption))
                        .foregroundStyle(Color.fallbackTextSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }

    // MARK: - Query Logic

    private func scheduleQuery() {
        queryTask?.cancel()
        queryTask = Task {
            // Debounce — wait before querying
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            let text = sourceText
            guard text != lastQueryText, !text.isEmpty else { return }

            let newResults = knowledgeService.query(text, limit: 5)
            guard !Task.isCancelled else { return }

            lastQueryText = text
            withAnimation(.easeInOut(duration: 0.2)) {
                results = newResults
            }
        }
    }
}
