import SwiftUI

struct HomeView: View {
    var appState: AppState
    var workspacePath: String?
    var mailService: MailService
    var onNavigateToFile: (String) -> Void
    var onOpenGatewayLink: ((GatewayLink) -> Void)?

    @State private var vm: HomeViewModel

    init(
        appState: AppState,
        workspacePath: String?,
        mailService: MailService,
        onNavigateToFile: @escaping (String) -> Void,
        onOpenGatewayLink: ((GatewayLink) -> Void)? = nil
    ) {
        self.appState = appState
        self.workspacePath = workspacePath
        self.mailService = mailService
        self.onNavigateToFile = onNavigateToFile
        self.onOpenGatewayLink = onOpenGatewayLink
        _vm = State(initialValue: HomeViewModel(appState: appState))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                Text("Home")
                    .font(.system(size: Typography.body, weight: .semibold))
                    .foregroundStyle(Color.fallbackTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        ForEach([HomeViewModel.TimeState.morning, .midday, .evening], id: \.self) { state in
                            Button(stateLabel(state)) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    vm.timeState = state
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)

                HomeTimeView(vm: vm, onOpenGatewayLink: onOpenGatewayLink)

                Divider()
                    .padding(.vertical, 10)

                if !vm.pills.isEmpty {
                    HomePillsRow(vm: vm)
                    Divider()
                        .padding(.vertical, 10)
                }

                HomeBottomZone(vm: vm, onNavigateToFile: onNavigateToFile)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fallbackEditorBg)
        .onAppear {
            reload()
            refreshMailInBackground()
        }
        .onChange(of: workspacePath) { _, _ in
            reload()
        }
        .onChange(of: appState.settings.googleConnectedEmail) { _, newEmail in
            if !newEmail.isEmpty {
                reload()
                refreshMailInBackground()
            }
        }
        .onDisappear {
            vm.markSeen()
        }
    }

    private func stateLabel(_ state: HomeViewModel.TimeState) -> String {
        switch state {
        case .morning: return "Morning"
        case .midday:  return "Midday"
        case .evening: return "Evening"
        }
    }

    private func reload() {
        guard let workspace = workspacePath ?? appState.workspacePath else { return }
        Task {
            await vm.load(workspacePath: workspace)
        }
    }

    /// Fetch fresh inbox data in the background, then reload the view model.
    private func refreshMailInBackground() {
        let email = appState.settings.googleConnectedEmail
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            // Load cached data into MailService first (fast, from disk)
            mailService.loadCachedData(accountEmail: email)

            // Then try a live Gmail fetch if we have a valid token
            do {
                _ = try await appState.withValidGoogleToken(
                    for: email,
                    scopes: GoogleScopeSet.mail
                ) { token in
                    await mailService.loadMailbox(.inbox, token: token)
                }
            } catch {
                // Token expired or not available — cached data is fine
            }

            // Reload the view model so it picks up the fresh mail cache
            reload()
        }
    }
}

// MARK: - Pills

private struct HomePillsRow: View {
    let vm: HomeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vm.pills) { pill in
                    Text(pill.label)
                        .font(.system(size: Typography.caption2, weight: .medium))
                        .foregroundStyle(pill.isUrgent ? TagColor.color(for: "blue") : Color.fallbackTextSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    pill.isUrgent
                                        ? TagColor.color(for: "blue").opacity(0.08)
                                        : Color.fallbackSurfaceSubtle
                                )
                        )
                }
            }
        }
    }
}
