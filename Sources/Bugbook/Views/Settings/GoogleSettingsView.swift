import SwiftUI
import BugbookCore

struct GoogleSettingsView: View {
    @Bindable var appState: AppState
    @State private var overlays: [CalendarOverlay] = []
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var showClientSecret = false

    private let store = CalendarEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection("OAuth App") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Google OAuth Client ID", text: $appState.settings.googleClientID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    HStack(spacing: 8) {
                        Group {
                            if showClientSecret {
                                TextField("Google OAuth Client Secret", text: $appState.settings.googleClientSecret)
                            } else {
                                SecureField("Google OAuth Client Secret", text: $appState.settings.googleClientSecret)
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

                    Text("Use a Google desktop OAuth client. Bugbook uses this one account for both Mail and Calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Enable the Gmail API and Google Calendar API in the same project, then use that desktop client here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Google Account") {
                if isConnected {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected to Google")
                                .font(.system(size: 13, weight: .medium))
                            if !appState.settings.googleConnectedEmail.isEmpty {
                                Text(appState.settings.googleConnectedEmail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            Text(scopeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Disconnect") {
                                disconnect()
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                        }
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
                        .disabled(isSigningIn || !appState.settings.googleConfigured)

                        if let signInError {
                            Text(signInError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !appState.settings.googleConfigured {
                            Text("Add your Google OAuth client ID and secret above before signing in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let reconnectMessage {
                    Text(reconnectMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Used By") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Mail uses Gmail threads, search, compose, and thread actions.", systemImage: "envelope")
                        .font(.system(size: 13))
                    Label("Calendar uses Google Calendar sync, event creation, and database overlays.", systemImage: "calendar.badge.plus")
                        .font(.system(size: 13))
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
            let result = try await GoogleAuthService.signIn(using: appState.settings, scopes: GoogleScopeSet.calendarAndMail)
            appState.settings.applyGoogleAuthResult(result)
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func disconnect() {
        appState.settings.disconnectGoogle()
    }

    private var isConnected: Bool {
        appState.settings.googleConnected
    }

    private var scopeSummary: String {
        guard !appState.settings.googleGrantedScopes.isEmpty else { return "Scopes not recorded" }

        let grantedScopes = Set(appState.settings.googleGrantedScopes)
        var descriptions: [String] = []
        if grantedScopes.contains(GoogleScopeSet.gmailModify) {
            descriptions.append("Gmail read/modify")
        }
        if grantedScopes.contains(GoogleScopeSet.gmailSend) {
            descriptions.append("Gmail send")
        }
        if grantedScopes.contains(GoogleScopeSet.calendarEvents) {
            descriptions.append("Calendar create/edit")
        } else if grantedScopes.contains(GoogleScopeSet.calendarReadonly) {
            descriptions.append("Calendar read")
        }
        if grantedScopes.contains(GoogleScopeSet.calendarListReadonly) && !grantedScopes.contains(GoogleScopeSet.calendarEvents) {
            descriptions.append("Calendar list")
        }
        return descriptions.joined(separator: " • ")
    }

    private var reconnectMessage: String? {
        guard isConnected else { return nil }

        let missingScopes = GoogleScopeSet.calendarAndMail.filter { !appState.settings.googleGrantedScopes.contains($0) }
        guard !missingScopes.isEmpty else { return nil }

        if missingScopes.contains(GoogleScopeSet.calendarEvents) {
            return "Reconnect Google access to grant calendar event creation."
        }
        return "Reconnect Google access if Mail or Calendar starts reporting missing scopes."
    }
}
