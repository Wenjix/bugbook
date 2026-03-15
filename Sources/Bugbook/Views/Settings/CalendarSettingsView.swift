import SwiftUI
import BugbookCore

struct CalendarSettingsView: View {
    @Bindable var appState: AppState
    @State private var showClientSecret = false
    @State private var overlays: [CalendarOverlay] = []

    private let store = CalendarEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Google Calendar") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Client ID", text: $appState.settings.googleCalendarClientId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    HStack(spacing: 8) {
                        Group {
                            if showClientSecret {
                                TextField("Client Secret", text: $appState.settings.googleCalendarClientSecret)
                            } else {
                                SecureField("Client Secret", text: $appState.settings.googleCalendarClientSecret)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                        Button {
                            showClientSecret.toggle()
                        } label: {
                            Image(systemName: showClientSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    TextField("Refresh Token", text: $appState.settings.googleCalendarRefreshToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    Text("Create OAuth credentials in the Google Cloud Console with the Calendar API scope. Use the OAuth Playground to get a refresh token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if isConfigured {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Credentials configured")
                                .font(.system(size: 13))
                        }
                    }
                }
            }

            SettingsSection("Database Overlays") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Show database rows with date properties on your calendar. Add overlays from the calendar view's filter menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if overlays.isEmpty {
                        Text("No overlays configured yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(overlays) { overlay in
                            HStack {
                                Circle()
                                    .fill(TagColor.color(for: overlay.color))
                                    .frame(width: 8, height: 8)
                                Text("\(overlay.databaseName) — \(overlay.datePropertyName)")
                                    .font(.system(size: 13))
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if let workspace = appState.workspacePath {
                overlays = store.loadOverlays(in: workspace)
            }
        }
    }

    private var isConfigured: Bool {
        !appState.settings.googleCalendarClientId.isEmpty &&
        !appState.settings.googleCalendarClientSecret.isEmpty &&
        !appState.settings.googleCalendarRefreshToken.isEmpty
    }
}
