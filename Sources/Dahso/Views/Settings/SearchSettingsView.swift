import SwiftUI

struct SearchSettingsView: View {
    var appState: AppState
    @State private var qmdService = QmdService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            qmdStatusSection

            if case .installed = qmdService.status {
                modeSection
                indexSection
                mcpSection
            }
        }
        .task {
            await qmdService.detect()
            if let workspace = appState.workspacePath, qmdService.status.isInstalled {
                await qmdService.ensureCollection(workspace: workspace)
                await qmdService.fetchIndexStatus()
            }
        }
    }

    // MARK: - qmd Status

    private var qmdStatusSection: some View {
        SettingsSection("Search Engine") {
            switch qmdService.status {
            case .unknown:
                statusRow {
                    ProgressView().scaleEffect(0.7)
                    Text("Detecting...").foregroundStyle(.secondary)
                }

            case .notInstalled:
                notInstalledRow

            case .installing:
                statusRow {
                    ProgressView().scaleEffect(0.7)
                    Text("Installing qmd...").foregroundStyle(.secondary)
                }

            case .installed(let version, _):
                installedRow(version: version)

            case .error(let message):
                errorRow(message: message)
            }
        }
    }

    private var notInstalledRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                Text("qmd -- Not Installed")
                    .font(.system(size: 14))
                Spacer()
                Button("Install") {
                    Task { await qmdService.install() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Text("qmd adds BM25, semantic, and hybrid search to Dahso. v2 includes auto query expansion and reranking.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Requires bun or npm.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }

    private func installedRow(version: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("qmd \(version)")
                .font(.system(size: 14))
            Spacer()
            if qmdService.collectionReady {
                Text("Workspace indexed")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.55)
                    Text("Indexing...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Install failed")
                    .font(.system(size: 14))
                Spacer()
                Button("Retry") {
                    Task { await qmdService.install() }
                }
                .controlSize(.small)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
    }

    // MARK: - Mode Picker

    private var modeSection: some View {
        SettingsSection("Search Mode") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(QmdSearchMode.allCases, id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    private func modeRow(_ mode: QmdSearchMode) -> some View {
        let selected = appState.settings.qmdSearchMode == mode
        return Button {
            appState.settings.qmdSearchMode = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.system(size: 14))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.label)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Text(mode.cliCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 3))
                    }
                    Text(mode.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Index Health

    private var indexSection: some View {
        SettingsSection("Index") {
            if let status = qmdService.indexStatus {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 16) {
                        indexStat(label: "Files", value: "\(status.totalFiles)")
                        indexStat(label: "Vectors", value: "\(status.totalVectors)")
                        if !status.indexSize.isEmpty {
                            indexStat(label: "Size", value: status.indexSize)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Re-index") {
                            Task {
                                if let workspace = appState.workspacePath {
                                    await qmdService.ensureCollection(workspace: workspace)
                                    await qmdService.fetchIndexStatus()
                                }
                            }
                        }
                        .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.55)
                    Text("Loading index status...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func indexStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }

    // MARK: - MCP tip

    private var mcpSection: some View {
        SettingsSection("MCP Server") {
            VStack(alignment: .leading, spacing: 8) {
                Text("qmd also runs as a standalone MCP server. Add it to Claude Code, Cursor, or any MCP-compatible client to get search across your notes outside of Dahso.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("github.com/tobi/qmd", destination: URL(string: "https://github.com/tobi/qmd")!)
                    .font(.system(size: 13))
            }
        }
    }
}
