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

struct AppSettings: Codable, Equatable {
    var theme: ThemeMode
    var railPinned: Bool
    var focusModeOnType: Bool
    var preferredAIEngine: PreferredAIEngine
    var executionPolicy: ExecutionPolicy
    var bugbookSkillEnabled: Bool
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
    /// Path to the page opened for new/empty tabs. Empty string = default Bugbook landing page.
    var defaultNewTabPage: String
    var browserSearchEngine: BrowserSearchEngine
    var browserChrome: BrowserChromeConfiguration
    var browserQuickLaunchItems: [BrowserQuickLaunchItem]
    var browserDefaultSaveFolder: String

    // Shared Google account
    var googleClientID: String
    var googleClientSecret: String
    var googleRefreshToken: String
    var googleAccessToken: String
    var googleTokenExpiry: Double
    var googleConnectedEmail: String
    var googleGrantedScopes: [String]

    static let `default` = AppSettings(
        theme: .system,
        railPinned: false,
        focusModeOnType: false,
        preferredAIEngine: .auto,
        executionPolicy: .ask,
        bugbookSkillEnabled: false,
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
        browserChrome: .minimal,
        browserQuickLaunchItems: [
            BrowserQuickLaunchItem(title: "Bugbook", url: "https://github.com/maxforsey/bugbook", icon: "book.pages"),
            BrowserQuickLaunchItem(title: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
            BrowserQuickLaunchItem(title: "Apple Docs", url: "https://developer.apple.com/documentation", icon: "doc.text.magnifyingglass"),
        ],
        browserDefaultSaveFolder: "Web Clippings",
        googleClientID: "",
        googleClientSecret: "",
        googleRefreshToken: "",
        googleAccessToken: "",
        googleTokenExpiry: 0,
        googleConnectedEmail: "",
        googleGrantedScopes: []
    )

    private enum CodingKeys: String, CodingKey {
        case theme
        case railPinned
        case focusModeOnType
        case preferredAIEngine
        case executionPolicy
        case bugbookSkillEnabled
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
        case browserChrome
        case browserQuickLaunchItems
        case browserDefaultSaveFolder
        case googleClientID
        case googleClientSecret
        case googleRefreshToken
        case googleAccessToken
        case googleTokenExpiry
        case googleConnectedEmail
        case googleGrantedScopes

        // Legacy calendar-only auth keys.
        case googleCalendarRefreshToken
        case googleCalendarAccessToken
        case googleCalendarTokenExpiry
        case googleCalendarConnectedEmail
    }

    // Backward-compatible decoding — new fields default gracefully.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .system
        railPinned = try container.decodeIfPresent(Bool.self, forKey: .railPinned) ?? false
        focusModeOnType = try container.decodeIfPresent(Bool.self, forKey: .focusModeOnType) ?? false
        preferredAIEngine = try container.decodeIfPresent(PreferredAIEngine.self, forKey: .preferredAIEngine) ?? .auto
        executionPolicy = try container.decodeIfPresent(ExecutionPolicy.self, forKey: .executionPolicy) ?? .ask
        bugbookSkillEnabled = try container.decodeIfPresent(Bool.self, forKey: .bugbookSkillEnabled) ?? false
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
        browserChrome = try container.decodeIfPresent(BrowserChromeConfiguration.self, forKey: .browserChrome) ?? .minimal
        browserQuickLaunchItems = try container.decodeIfPresent([BrowserQuickLaunchItem].self, forKey: .browserQuickLaunchItems) ?? AppSettings.default.browserQuickLaunchItems
        browserDefaultSaveFolder = try container.decodeIfPresent(String.self, forKey: .browserDefaultSaveFolder) ?? "Web Clippings"
        googleClientID = try container.decodeIfPresent(String.self, forKey: .googleClientID) ?? ""
        googleClientSecret = try container.decodeIfPresent(String.self, forKey: .googleClientSecret) ?? ""
        let legacyRefreshToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarRefreshToken)
        let legacyAccessToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarAccessToken)
        let legacyTokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleCalendarTokenExpiry)
        let legacyConnectedEmail = try container.decodeIfPresent(String.self, forKey: .googleCalendarConnectedEmail)
        googleRefreshToken = try container.decodeIfPresent(String.self, forKey: .googleRefreshToken) ?? legacyRefreshToken ?? ""
        googleAccessToken = try container.decodeIfPresent(String.self, forKey: .googleAccessToken) ?? legacyAccessToken ?? ""
        googleTokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleTokenExpiry) ?? legacyTokenExpiry ?? 0
        googleConnectedEmail = try container.decodeIfPresent(String.self, forKey: .googleConnectedEmail) ?? legacyConnectedEmail ?? ""
        googleGrantedScopes = try container.decodeIfPresent([String].self, forKey: .googleGrantedScopes) ?? []
    }

    init(
        theme: ThemeMode,
        railPinned: Bool = false,
        focusModeOnType: Bool,
        preferredAIEngine: PreferredAIEngine,
        executionPolicy: ExecutionPolicy,
        bugbookSkillEnabled: Bool,
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
        browserChrome: BrowserChromeConfiguration = .minimal,
        browserQuickLaunchItems: [BrowserQuickLaunchItem] = [],
        browserDefaultSaveFolder: String = "Web Clippings",
        googleClientID: String = "",
        googleClientSecret: String = "",
        googleRefreshToken: String = "",
        googleAccessToken: String = "",
        googleTokenExpiry: Double = 0,
        googleConnectedEmail: String = "",
        googleGrantedScopes: [String] = []
    ) {
        self.theme = theme
        self.railPinned = railPinned
        self.focusModeOnType = focusModeOnType
        self.preferredAIEngine = preferredAIEngine
        self.executionPolicy = executionPolicy
        self.bugbookSkillEnabled = bugbookSkillEnabled
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
        self.browserChrome = browserChrome
        self.browserQuickLaunchItems = browserQuickLaunchItems
        self.browserDefaultSaveFolder = browserDefaultSaveFolder
        self.googleClientID = googleClientID
        self.googleClientSecret = googleClientSecret
        self.googleRefreshToken = googleRefreshToken
        self.googleAccessToken = googleAccessToken
        self.googleTokenExpiry = googleTokenExpiry
        self.googleConnectedEmail = googleConnectedEmail
        self.googleGrantedScopes = googleGrantedScopes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(railPinned, forKey: .railPinned)
        try container.encode(focusModeOnType, forKey: .focusModeOnType)
        try container.encode(preferredAIEngine, forKey: .preferredAIEngine)
        try container.encode(executionPolicy, forKey: .executionPolicy)
        try container.encode(bugbookSkillEnabled, forKey: .bugbookSkillEnabled)
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
        try container.encode(browserChrome, forKey: .browserChrome)
        try container.encode(browserQuickLaunchItems, forKey: .browserQuickLaunchItems)
        try container.encode(browserDefaultSaveFolder, forKey: .browserDefaultSaveFolder)
        try container.encode(googleClientID, forKey: .googleClientID)
        try container.encode(googleClientSecret, forKey: .googleClientSecret)
        try container.encode(googleRefreshToken, forKey: .googleRefreshToken)
        try container.encode(googleAccessToken, forKey: .googleAccessToken)
        try container.encode(googleTokenExpiry, forKey: .googleTokenExpiry)
        try container.encode(googleConnectedEmail, forKey: .googleConnectedEmail)
        try container.encode(googleGrantedScopes, forKey: .googleGrantedScopes)
    }

    var googleConfigured: Bool {
        !googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var googleConnected: Bool {
        !googleRefreshToken.isEmpty
    }

    var googleToken: GoogleOAuthToken? {
        guard googleConnected else { return nil }
        return GoogleOAuthToken(
            accessToken: googleAccessToken,
            refreshToken: googleRefreshToken,
            expiresAt: Date(timeIntervalSince1970: googleTokenExpiry),
            grantedScopes: googleGrantedScopes
        )
    }

    mutating func applyGoogleAuthResult(_ result: GoogleOAuthResult) {
        googleAccessToken = result.accessToken
        googleRefreshToken = result.refreshToken
        googleTokenExpiry = result.expiresAt.timeIntervalSince1970
        googleConnectedEmail = result.email
        googleGrantedScopes = result.grantedScopes
    }

    mutating func updateGoogleToken(_ token: GoogleOAuthToken) {
        googleAccessToken = token.accessToken
        googleRefreshToken = token.refreshToken
        googleTokenExpiry = token.expiresAt.timeIntervalSince1970
        googleGrantedScopes = token.grantedScopes
    }

    mutating func disconnectGoogle() {
        googleRefreshToken = ""
        googleAccessToken = ""
        googleTokenExpiry = 0
        googleConnectedEmail = ""
        googleGrantedScopes = []
    }
}
