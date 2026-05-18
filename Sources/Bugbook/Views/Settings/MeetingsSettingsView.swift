import SwiftUI

struct MeetingsSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Recording") {
                Toggle("Recording consent acknowledged", isOn: $appState.settings.recordingConsentAcknowledged)
                    .toggleStyle(.switch)

                Text("Bugbook records microphone and system audio during meetings. Confirm consent before the first recording.")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)

                Button("Reset consent acknowledgement") {
                    appState.settings.recordingConsentAcknowledged = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            SettingsSection("Summary") {
                Toggle("Generate meeting summaries", isOn: $appState.settings.meetingSummaryEnabled)
                    .toggleStyle(.switch)

                TextField("Summary command", text: $appState.settings.meetingSummaryCommand)
                    .textFieldStyle(.roundedBorder)

                Text("The command receives the summary prompt on stdin. Capture still succeeds if summary generation fails.")
                    .font(.system(size: Typography.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
