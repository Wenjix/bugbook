import SwiftUI
import BugbookCore

struct CalendarSettingsView: View {
    @Bindable var appState: AppState
    @State private var overlays: [CalendarOverlay] = []
    @State private var isSigningIn = false
    @State private var signInError: String?

    private let store = CalendarEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("Google Calendar") {
                if isConnected {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected to Google Calendar")
                                .font(.system(size: 13, weight: .medium))
                            if !appState.settings.googleCalendarConnectedEmail.isEmpty {
                                Text(appState.settings.googleCalendarConnectedEmail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Disconnect") {
                            disconnect()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.system(size: 13))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await signIn() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSigningIn {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "person.badge.key")
                                }
                                Text("Sign in with Google")
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSigningIn)

                        if let signInError {
                            Text(signInError)
                                .font(.caption)
                                .foregroundStyle(.red)
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

    private func signIn() async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            let result = try await GoogleOAuthFlow.signIn()
            appState.settings.googleCalendarAccessToken = result.accessToken
            appState.settings.googleCalendarRefreshToken = result.refreshToken
            appState.settings.googleCalendarTokenExpiry = result.expiresAt.timeIntervalSince1970
            appState.settings.googleCalendarConnectedEmail = result.email
            appState.settings.googleCalendarBannerDismissed = false
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func disconnect() {
        appState.settings.googleCalendarAccessToken = ""
        appState.settings.googleCalendarRefreshToken = ""
        appState.settings.googleCalendarTokenExpiry = 0
        appState.settings.googleCalendarConnectedEmail = ""
    }

    private var isConnected: Bool {
        !appState.settings.googleCalendarRefreshToken.isEmpty
    }
}
