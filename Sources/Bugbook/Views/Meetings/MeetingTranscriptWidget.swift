import SwiftUI

struct MeetingTranscriptWidget: View {
    let entries: [MeetingTranscriptEntry]
    let volatileText: String
    let isRecording: Bool
    @Binding var isExpanded: Bool
    @Binding var searchText: String
    @Binding var copyConfirmation: Bool

    private var filteredEntries: [MeetingTranscriptEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            MeetingTranscriptFormatter.readableText($0.text).lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                transcriptBody
                Divider()
                transcriptControls
                Divider()
            }
            transcriptHeader
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.fallbackCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(Opacity.medium), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var transcriptHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))

                Image(systemName: isRecording ? "waveform" : "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(isRecording ? StatusColor.error : .secondary)

                Text("Transcript")
                    .font(.system(size: Typography.bodySmall, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isRecording {
                    PulsingRecordDot()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transcriptControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search transcript", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: Typography.caption))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(Opacity.subtle))
            .clipShape(.rect(cornerRadius: Radius.xs))

            Spacer()

            Button(action: copyTranscript) {
                HStack(spacing: 4) {
                    Image(systemName: copyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(copyConfirmation ? "Copied" : "Copy")
                        .font(.system(size: Typography.caption, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(Opacity.light))
                .clipShape(.rect(cornerRadius: Radius.xs))
            }
            .buttonStyle(.plain)
            .disabled(copyableTranscriptText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if filteredEntries.isEmpty && entries.isEmpty {
            transcriptEmptyState(isRecording ? "Listening..." : "No transcript")
        } else if filteredEntries.isEmpty {
            transcriptEmptyState("No matches")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredEntries) { entry in
                        transcriptBubble(entry: entry)
                    }
                    if isRecording, !volatileText.isEmpty {
                        transcriptBubble(
                            entry: MeetingTranscriptEntry(text: volatileText),
                            isVolatile: true
                        )
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 300)
        }
    }

    private func transcriptEmptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typography.bodySmall))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    private func transcriptBubble(entry: MeetingTranscriptEntry, isVolatile: Bool = false) -> some View {
        let isSelf = entry.speaker == "self"
        return HStack {
            if isSelf { Spacer(minLength: 40) }
            Text(MeetingTranscriptFormatter.readableText(entry.text))
                .font(.system(size: Typography.bodySmall))
                .foregroundStyle(isVolatile ? .tertiary : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelf ? Color.accentColor.opacity(0.18) : Color.primary.opacity(Opacity.light))
                )
                .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
            if !isSelf { Spacer(minLength: 40) }
        }
    }

    private func copyTranscript() {
        let text = copyableTranscriptText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copyConfirmation = false
        }
    }

    private var copyableTranscriptText: String {
        MeetingTranscriptFormatter.copyText(entries: entries, volatileText: volatileText)
    }
}

struct MeetingRecordingNoticeToast: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StatusColor.warning)
                Text(message)
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsPrivacySettingsButton {
                Button(action: openPrivacySettings) {
                    Label("Open Settings", systemImage: "gearshape")
                        .font(.system(size: Typography.caption, weight: .medium))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.fallbackCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(StatusColor.warning.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    private var showsPrivacySettingsButton: Bool {
        MeetingRecordingNoticePrivacySettings.showsButton(message: message)
    }

    private var privacySettingsAnchors: [String] {
        MeetingRecordingNoticePrivacySettings.anchors(for: message)
    }

    private func openPrivacySettings() {
        for anchor in privacySettingsAnchors {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

enum MeetingRecordingNoticePrivacySettings {
    static func showsButton(message: String) -> Bool {
        message.localizedCaseInsensitiveContains("microphone") ||
            message.localizedCaseInsensitiveContains("system audio") ||
            message.localizedCaseInsensitiveContains("screen") ||
            message.localizedCaseInsensitiveContains("privacy")
    }

    static func anchors(for message: String) -> [String] {
        if message.localizedCaseInsensitiveContains("microphone") {
            return ["Privacy_Microphone", "Privacy"]
        }
        if message.localizedCaseInsensitiveContains("system audio") ||
            message.localizedCaseInsensitiveContains("screen") {
            return ["Privacy_AudioCapture", "Privacy_ScreenCapture", "Privacy"]
        }
        return ["Privacy_Microphone", "Privacy_AudioCapture", "Privacy_ScreenCapture", "Privacy"]
    }
}

struct PulsingRecordDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(StatusColor.error)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
