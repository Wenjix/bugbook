import Foundation

enum ThemeMode: String, Codable {
    case light
    case dark
    case system
}

enum PreferredAIEngine: String, Codable, CaseIterable {
    case auto = "Auto"
    case codex = "Codex"
    case claude = "Claude"
    case claudeAPI = "API Key"
}

enum AnthropicModel: String, Codable, CaseIterable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-20250514"
    case opus = "claude-opus-4-20250514"

    var displayName: String {
        switch self {
        case .haiku: return "Haiku (fast)"
        case .sonnet: return "Sonnet (quality)"
        case .opus: return "Opus (best)"
        }
    }
}

enum TerminalColorSchemeMode: String, Codable, CaseIterable {
    case light
    case dark
    case system
}

enum ExecutionPolicy: String, Codable, CaseIterable {
    case ask = "Ask Before Running"
    case autoApprove = "Auto-Approve"
    case denyAll = "Deny All"
}

enum BrowserSearchEngine: String, Codable, CaseIterable {
    case google
    case duckDuckGo
    case kagi

    var displayName: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .kagi: return "Kagi"
        }
    }

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        switch self {
        case .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .duckDuckGo:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")
        case .kagi:
            return URL(string: "https://kagi.com/search?q=\(encoded)")
        }
    }
}

struct BrowserQuickLaunchItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var url: String
    var icon: String

    init(id: UUID = UUID(), title: String, url: String, icon: String) {
        self.id = id
        self.title = title
        self.url = url
        self.icon = icon
    }
}

private func sanitizeBrowserExtensionPaths(_ paths: [String]) -> [String] {
    var seen: Set<String> = []
    var normalized: [String] = []

    for rawPath in paths {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        guard seen.insert(standardized).inserted else { continue }
        normalized.append(standardized)
    }

    return normalized
}

struct BrowserChromeConfiguration: Codable, Equatable {
    var showsBackForwardButtons: Bool
    var showsBookmarksBar: Bool
    var autoHidesTabPills: Bool
    var showsSaveButton: Bool
    var showsStatusBar: Bool
    var showsNewTabGreeting: Bool
    var showsNewTabQuickLaunch: Bool
    var showsNewTabRecentVisits: Bool

    static let minimal = BrowserChromeConfiguration(
        showsBackForwardButtons: false,
        showsBookmarksBar: false,
        autoHidesTabPills: true,
        showsSaveButton: true,
        showsStatusBar: false,
        showsNewTabGreeting: true,
        showsNewTabQuickLaunch: true,
        showsNewTabRecentVisits: true
    )
}

/// A single connected Google account. Tokens are kept in Keychain by `AppSettingsStore`;
/// the fields here are hydrated on load and stripped on save so they never hit disk as JSON.
struct GoogleAccount: Codable, Equatable, Identifiable {
    var email: String
    var accessToken: String
    var refreshToken: String
    var tokenExpiry: Double
    var grantedScopes: [String]

    var id: String { email.lowercased() }

    var token: GoogleOAuthToken {
        GoogleOAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: tokenExpiry),
            grantedScopes: grantedScopes
        )
    }

    init(
        email: String,
        accessToken: String = "",
        refreshToken: String = "",
        tokenExpiry: Double = 0,
        grantedScopes: [String] = []
    ) {
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
        self.grantedScopes = grantedScopes
    }

    init(from result: GoogleOAuthResult) {
        self.email = result.email
        self.accessToken = result.accessToken
        self.refreshToken = result.refreshToken
        self.tokenExpiry = result.expiresAt.timeIntervalSince1970
        self.grantedScopes = result.grantedScopes
    }

    /// True if at least a refresh token is present.
    var isConnected: Bool { !refreshToken.isEmpty }

    /// Case-insensitive email match. Use everywhere accounts are looked up.
    func matches(email: String) -> Bool {
        self.email.caseInsensitiveCompare(email) == .orderedSame
    }
}

struct AppSettings: Codable, Equatable {
    var theme: ThemeMode
    var focusModeOnType: Bool
    var preferredAIEngine: PreferredAIEngine
    var executionPolicy: ExecutionPolicy
    var dahsoSkillEnabled: Bool
    var agentsMdContent: String
    var qmdSearchMode: QmdSearchMode
    var anthropicApiKey: String
    var anthropicModel: AnthropicModel
    var terminalColorScheme: TerminalColorSchemeMode
    var terminalLightTheme: String
    var terminalDarkTheme: String
    var mailBackgroundAnalysisEnabled: Bool
    var mailBackgroundDraftGenerationEnabled: Bool
    var mailSenderLookupEnabled: Bool
    var mailMemoryLearningEnabled: Bool
    /// Path to the page opened for new/empty tabs. Empty string = default Dahso landing page.
    var defaultNewTabPage: String
    var browserSearchEngine: BrowserSearchEngine
    var browserHistoryEnabled: Bool
    var browserSuggestionsEnabled: Bool
    var browserSuggestionLimit: Int
    var browserSuggestsDahsoPages: Bool
    var browserChrome: BrowserChromeConfiguration
    var browserQuickLaunchItems: [BrowserQuickLaunchItem]
    var browserExtensionPaths: [String]
    var browserDefaultSaveFolder: String

    // Shared Google OAuth client configuration (one client, N accounts)
    var googleClientID: String
    var googleClientSecret: String

    /// All connected Google accounts. Mail + Calendar use these.
    var googleAccounts: [GoogleAccount]

    /// Email of the currently active account for mail. Empty = defaults to first account.
    var activeGoogleAccountEmail: String

    static let `default` = AppSettings(
        theme: .system,
        focusModeOnType: false,
        preferredAIEngine: .auto,
        executionPolicy: .ask,
        dahsoSkillEnabled: false,
        agentsMdContent: "",
        qmdSearchMode: .bm25,
        anthropicApiKey: "",
        anthropicModel: .sonnet,
        terminalColorScheme: .system,
        terminalLightTheme: "",
        terminalDarkTheme: "",
        mailBackgroundAnalysisEnabled: true,
        mailBackgroundDraftGenerationEnabled: true,
        mailSenderLookupEnabled: true,
        mailMemoryLearningEnabled: true,
        defaultNewTabPage: "",
        browserSearchEngine: .duckDuckGo,
        browserHistoryEnabled: true,
        browserSuggestionsEnabled: true,
        browserSuggestionLimit: 8,
        browserSuggestsDahsoPages: true,
        browserChrome: .minimal,
        browserQuickLaunchItems: [
            BrowserQuickLaunchItem(title: "Dahso", url: "https://github.com/maxforsey/dahso", icon: "book.pages"),
            BrowserQuickLaunchItem(title: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
            BrowserQuickLaunchItem(title: "Apple Docs", url: "https://developer.apple.com/documentation", icon: "doc.text.magnifyingglass"),
        ],
        browserExtensionPaths: [],
        browserDefaultSaveFolder: "Web Clippings",
        googleClientID: "",
        googleClientSecret: "",
        googleAccounts: [],
        activeGoogleAccountEmail: ""
    )

    private enum CodingKeys: String, CodingKey {
        case theme
        case focusModeOnType
        case preferredAIEngine
        case executionPolicy
        case dahsoSkillEnabled
        case agentsMdContent
        case qmdSearchMode
        case anthropicApiKey
        case anthropicModel
        case terminalColorScheme
        case terminalLightTheme
        case terminalDarkTheme
        case mailBackgroundAnalysisEnabled
        case mailBackgroundDraftGenerationEnabled
        case mailSenderLookupEnabled
        case mailMemoryLearningEnabled
        case defaultNewTabPage
        case browserSearchEngine
        case browserHistoryEnabled
        case browserSuggestionsEnabled
        case browserSuggestionLimit
        case browserSuggestsDahsoPages
        case browserChrome
        case browserQuickLaunchItems
        case browserExtensionPaths
        case browserDefaultSaveFolder
        case googleClientID
        case googleClientSecret
        case googleAccounts
        case activeGoogleAccountEmail

        // Legacy single-account fields (pre-multi-account).
        case googleRefreshToken
        case googleAccessToken
        case googleTokenExpiry
        case googleConnectedEmail
        case googleGrantedScopes

        // Legacy calendar-only auth keys (older still).
        case googleCalendarRefreshToken
        case googleCalendarAccessToken
        case googleCalendarTokenExpiry
        case googleCalendarConnectedEmail
    }

    // Backward-compatible decoding — new fields default gracefully.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .system
        focusModeOnType = try container.decodeIfPresent(Bool.self, forKey: .focusModeOnType) ?? false
        preferredAIEngine = try container.decodeIfPresent(PreferredAIEngine.self, forKey: .preferredAIEngine) ?? .auto
        executionPolicy = try container.decodeIfPresent(ExecutionPolicy.self, forKey: .executionPolicy) ?? .ask
        dahsoSkillEnabled = try container.decodeIfPresent(Bool.self, forKey: .dahsoSkillEnabled) ?? false
        agentsMdContent = try container.decodeIfPresent(String.self, forKey: .agentsMdContent) ?? ""
        qmdSearchMode = try container.decodeIfPresent(QmdSearchMode.self, forKey: .qmdSearchMode) ?? .bm25
        anthropicApiKey = try container.decodeIfPresent(String.self, forKey: .anthropicApiKey) ?? ""
        anthropicModel = try container.decodeIfPresent(AnthropicModel.self, forKey: .anthropicModel) ?? .sonnet
        terminalColorScheme = try container.decodeIfPresent(TerminalColorSchemeMode.self, forKey: .terminalColorScheme) ?? .system
        terminalLightTheme = try container.decodeIfPresent(String.self, forKey: .terminalLightTheme) ?? ""
        terminalDarkTheme = try container.decodeIfPresent(String.self, forKey: .terminalDarkTheme) ?? ""
        mailBackgroundAnalysisEnabled = try container.decodeIfPresent(Bool.self, forKey: .mailBackgroundAnalysisEnabled) ?? true
        mailBackgroundDraftGenerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .mailBackgroundDraftGenerationEnabled) ?? true
        mailSenderLookupEnabled = try container.decodeIfPresent(Bool.self, forKey: .mailSenderLookupEnabled) ?? true
        mailMemoryLearningEnabled = try container.decodeIfPresent(Bool.self, forKey: .mailMemoryLearningEnabled) ?? true
        defaultNewTabPage = try container.decodeIfPresent(String.self, forKey: .defaultNewTabPage) ?? ""
        browserSearchEngine = try container.decodeIfPresent(BrowserSearchEngine.self, forKey: .browserSearchEngine) ?? .duckDuckGo
        browserHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .browserHistoryEnabled) ?? true
        browserSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .browserSuggestionsEnabled) ?? true
        browserSuggestionLimit = max(3, min(12, try container.decodeIfPresent(Int.self, forKey: .browserSuggestionLimit) ?? 8))
        browserSuggestsDahsoPages = try container.decodeIfPresent(Bool.self, forKey: .browserSuggestsDahsoPages) ?? true
        browserChrome = try container.decodeIfPresent(BrowserChromeConfiguration.self, forKey: .browserChrome) ?? .minimal
        browserQuickLaunchItems = try container.decodeIfPresent([BrowserQuickLaunchItem].self, forKey: .browserQuickLaunchItems) ?? AppSettings.default.browserQuickLaunchItems
        browserExtensionPaths = sanitizeBrowserExtensionPaths(
            try container.decodeIfPresent([String].self, forKey: .browserExtensionPaths) ?? []
        )
        browserDefaultSaveFolder = try container.decodeIfPresent(String.self, forKey: .browserDefaultSaveFolder) ?? "Web Clippings"
        googleClientID = try container.decodeIfPresent(String.self, forKey: .googleClientID) ?? ""
        googleClientSecret = try container.decodeIfPresent(String.self, forKey: .googleClientSecret) ?? ""

        // New multi-account shape takes precedence if present.
        if let accounts = try container.decodeIfPresent([GoogleAccount].self, forKey: .googleAccounts) {
            googleAccounts = accounts
            activeGoogleAccountEmail = try container.decodeIfPresent(String.self, forKey: .activeGoogleAccountEmail) ?? (accounts.first?.email ?? "")
        } else {
            // Legacy single-account migration: promote flat fields into a single GoogleAccount.
            let legacyRefreshToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarRefreshToken)
            let legacyAccessToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarAccessToken)
            let legacyTokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleCalendarTokenExpiry)
            let legacyConnectedEmail = try container.decodeIfPresent(String.self, forKey: .googleCalendarConnectedEmail)

            let refreshToken = try container.decodeIfPresent(String.self, forKey: .googleRefreshToken) ?? legacyRefreshToken ?? ""
            let accessToken = try container.decodeIfPresent(String.self, forKey: .googleAccessToken) ?? legacyAccessToken ?? ""
            let tokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleTokenExpiry) ?? legacyTokenExpiry ?? 0
            let connectedEmail = try container.decodeIfPresent(String.self, forKey: .googleConnectedEmail) ?? legacyConnectedEmail ?? ""
            let grantedScopes = try container.decodeIfPresent([String].self, forKey: .googleGrantedScopes) ?? []

            if !connectedEmail.isEmpty || !refreshToken.isEmpty {
                let account = GoogleAccount(
                    email: connectedEmail,
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    tokenExpiry: tokenExpiry,
                    grantedScopes: grantedScopes
                )
                googleAccounts = [account]
                activeGoogleAccountEmail = connectedEmail
            } else {
                googleAccounts = []
                activeGoogleAccountEmail = ""
            }
        }
    }

    init(
        theme: ThemeMode,
        focusModeOnType: Bool,
        preferredAIEngine: PreferredAIEngine,
        executionPolicy: ExecutionPolicy,
        dahsoSkillEnabled: Bool,
        agentsMdContent: String,
        qmdSearchMode: QmdSearchMode,
        anthropicApiKey: String,
        anthropicModel: AnthropicModel = .sonnet,
        terminalColorScheme: TerminalColorSchemeMode = .system,
        terminalLightTheme: String = "",
        terminalDarkTheme: String = "",
        mailBackgroundAnalysisEnabled: Bool = true,
        mailBackgroundDraftGenerationEnabled: Bool = true,
        mailSenderLookupEnabled: Bool = true,
        mailMemoryLearningEnabled: Bool = true,
        defaultNewTabPage: String,
        browserSearchEngine: BrowserSearchEngine = .duckDuckGo,
        browserHistoryEnabled: Bool = true,
        browserSuggestionsEnabled: Bool = true,
        browserSuggestionLimit: Int = 8,
        browserSuggestsDahsoPages: Bool = true,
        browserChrome: BrowserChromeConfiguration = .minimal,
        browserQuickLaunchItems: [BrowserQuickLaunchItem] = [],
        browserExtensionPaths: [String] = [],
        browserDefaultSaveFolder: String = "Web Clippings",
        googleClientID: String = "",
        googleClientSecret: String = "",
        googleAccounts: [GoogleAccount] = [],
        activeGoogleAccountEmail: String = ""
    ) {
        self.theme = theme
        self.focusModeOnType = focusModeOnType
        self.preferredAIEngine = preferredAIEngine
        self.executionPolicy = executionPolicy
        self.dahsoSkillEnabled = dahsoSkillEnabled
        self.agentsMdContent = agentsMdContent
        self.qmdSearchMode = qmdSearchMode
        self.anthropicApiKey = anthropicApiKey
        self.anthropicModel = anthropicModel
        self.terminalColorScheme = terminalColorScheme
        self.terminalLightTheme = terminalLightTheme
        self.terminalDarkTheme = terminalDarkTheme
        self.mailBackgroundAnalysisEnabled = mailBackgroundAnalysisEnabled
        self.mailBackgroundDraftGenerationEnabled = mailBackgroundDraftGenerationEnabled
        self.mailSenderLookupEnabled = mailSenderLookupEnabled
        self.mailMemoryLearningEnabled = mailMemoryLearningEnabled
        self.defaultNewTabPage = defaultNewTabPage
        self.browserSearchEngine = browserSearchEngine
        self.browserHistoryEnabled = browserHistoryEnabled
        self.browserSuggestionsEnabled = browserSuggestionsEnabled
        self.browserSuggestionLimit = max(3, min(12, browserSuggestionLimit))
        self.browserSuggestsDahsoPages = browserSuggestsDahsoPages
        self.browserChrome = browserChrome
        self.browserQuickLaunchItems = browserQuickLaunchItems
        self.browserExtensionPaths = sanitizeBrowserExtensionPaths(browserExtensionPaths)
        self.browserDefaultSaveFolder = browserDefaultSaveFolder
        self.googleClientID = googleClientID
        self.googleClientSecret = googleClientSecret
        self.googleAccounts = googleAccounts
        self.activeGoogleAccountEmail = activeGoogleAccountEmail
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(focusModeOnType, forKey: .focusModeOnType)
        try container.encode(preferredAIEngine, forKey: .preferredAIEngine)
        try container.encode(executionPolicy, forKey: .executionPolicy)
        try container.encode(dahsoSkillEnabled, forKey: .dahsoSkillEnabled)
        try container.encode(agentsMdContent, forKey: .agentsMdContent)
        try container.encode(qmdSearchMode, forKey: .qmdSearchMode)
        try container.encode(anthropicApiKey, forKey: .anthropicApiKey)
        try container.encode(anthropicModel, forKey: .anthropicModel)
        try container.encode(terminalColorScheme, forKey: .terminalColorScheme)
        try container.encode(terminalLightTheme, forKey: .terminalLightTheme)
        try container.encode(terminalDarkTheme, forKey: .terminalDarkTheme)
        try container.encode(mailBackgroundAnalysisEnabled, forKey: .mailBackgroundAnalysisEnabled)
        try container.encode(mailBackgroundDraftGenerationEnabled, forKey: .mailBackgroundDraftGenerationEnabled)
        try container.encode(mailSenderLookupEnabled, forKey: .mailSenderLookupEnabled)
        try container.encode(mailMemoryLearningEnabled, forKey: .mailMemoryLearningEnabled)
        try container.encode(defaultNewTabPage, forKey: .defaultNewTabPage)
        try container.encode(browserSearchEngine, forKey: .browserSearchEngine)
        try container.encode(browserHistoryEnabled, forKey: .browserHistoryEnabled)
        try container.encode(browserSuggestionsEnabled, forKey: .browserSuggestionsEnabled)
        try container.encode(browserSuggestionLimit, forKey: .browserSuggestionLimit)
        try container.encode(browserSuggestsDahsoPages, forKey: .browserSuggestsDahsoPages)
        try container.encode(browserChrome, forKey: .browserChrome)
        try container.encode(browserQuickLaunchItems, forKey: .browserQuickLaunchItems)
        try container.encode(sanitizeBrowserExtensionPaths(browserExtensionPaths), forKey: .browserExtensionPaths)
        try container.encode(browserDefaultSaveFolder, forKey: .browserDefaultSaveFolder)
        try container.encode(googleClientID, forKey: .googleClientID)
        try container.encode(googleClientSecret, forKey: .googleClientSecret)
        try container.encode(googleAccounts, forKey: .googleAccounts)
        try container.encode(activeGoogleAccountEmail, forKey: .activeGoogleAccountEmail)
    }

    // MARK: - Google Account Helpers

    var googleConfigured: Bool {
        !googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var googleConnected: Bool {
        googleAccounts.contains(where: { $0.isConnected })
    }

    /// The currently active account, or nil if none are connected.
    /// Falls back to the first account if `activeGoogleAccountEmail` doesn't resolve.
    var activeGoogleAccount: GoogleAccount? {
        if !activeGoogleAccountEmail.isEmpty,
           let match = googleAccounts.first(where: { $0.matches(email: activeGoogleAccountEmail) }) {
            return match
        }
        return googleAccounts.first
    }

    /// Back-compat: the email of the active account, or "".
    var googleConnectedEmail: String {
        activeGoogleAccount?.email ?? ""
    }

    /// Back-compat: the granted scopes of the active account, or [].
    var googleGrantedScopes: [String] {
        activeGoogleAccount?.grantedScopes ?? []
    }

    /// Back-compat: token for the active account, or nil.
    var googleToken: GoogleOAuthToken? {
        guard let account = activeGoogleAccount, account.isConnected else { return nil }
        return account.token
    }

    /// Accounts with a refresh token present — the ones mail/calendar sync can actually use.
    var connectedGoogleAccounts: [GoogleAccount] {
        googleAccounts.filter(\.isConnected)
    }

    func googleAccount(for email: String) -> GoogleAccount? {
        googleAccounts.first(where: { $0.matches(email: email) })
    }

    func googleToken(for email: String) -> GoogleOAuthToken? {
        googleAccount(for: email)?.token
    }

    // MARK: - Mutating helpers

    /// Apply a fresh OAuth result: insert or update the account and set it as active.
    mutating func applyGoogleAuthResult(_ result: GoogleOAuthResult) {
        let account = GoogleAccount(from: result)
        if let index = googleAccounts.firstIndex(where: { $0.matches(email: account.email) }) {
            googleAccounts[index] = account
        } else {
            googleAccounts.append(account)
        }
        activeGoogleAccountEmail = account.email
    }

    /// Replace the tokens on the active account (used after a refresh).
    mutating func updateGoogleToken(_ token: GoogleOAuthToken) {
        guard let email = activeGoogleAccount?.email else { return }
        updateGoogleToken(token, for: email)
    }

    mutating func updateGoogleToken(_ token: GoogleOAuthToken, for email: String) {
        guard let index = googleAccounts.firstIndex(where: { $0.matches(email: email) }) else { return }
        googleAccounts[index].accessToken = token.accessToken
        googleAccounts[index].refreshToken = token.refreshToken
        googleAccounts[index].tokenExpiry = token.expiresAt.timeIntervalSince1970
        googleAccounts[index].grantedScopes = token.grantedScopes
    }

    mutating func setActiveGoogleAccount(email: String) {
        guard googleAccounts.contains(where: { $0.matches(email: email) }) else { return }
        activeGoogleAccountEmail = email
    }

    /// Disconnect the active Google account (or a specific account by email).
    /// After disconnect, picks the next available account as active, or clears if none remain.
    mutating func disconnectGoogle(email: String? = nil) {
        let target = email ?? activeGoogleAccount?.email ?? ""
        guard !target.isEmpty else { return }
        googleAccounts.removeAll { $0.matches(email: target) }
        if activeGoogleAccountEmail.caseInsensitiveCompare(target) == .orderedSame {
            activeGoogleAccountEmail = googleAccounts.first?.email ?? ""
        }
    }
}
