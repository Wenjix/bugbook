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

enum ExecutionPolicy: String, Codable, CaseIterable {
    case ask = "Ask Before Running"
    case autoApprove = "Auto-Approve"
    case denyAll = "Deny All"
}

struct AppSettings: Codable {
    var theme: ThemeMode
    var focusModeOnType: Bool
    var preferredAIEngine: PreferredAIEngine
    var executionPolicy: ExecutionPolicy
    var bugbookSkillEnabled: Bool
    var agentsMdContent: String
    var qmdSearchMode: QmdSearchMode
    var anthropicApiKey: String
    /// Path to the page opened for new/empty tabs. Empty string = default Bugbook landing page.
    var defaultNewTabPage: String

    // Google Calendar
    var googleCalendarClientId: String
    var googleCalendarClientSecret: String
    var googleCalendarRefreshToken: String
    var googleCalendarAccessToken: String
    var googleCalendarTokenExpiry: Double

    static let `default` = AppSettings(
        theme: .system,
        focusModeOnType: false,
        preferredAIEngine: .auto,
        executionPolicy: .ask,
        bugbookSkillEnabled: false,
        agentsMdContent: "",
        qmdSearchMode: .bm25,
        anthropicApiKey: "",
        defaultNewTabPage: "",
        googleCalendarClientId: "",
        googleCalendarClientSecret: "",
        googleCalendarRefreshToken: "",
        googleCalendarAccessToken: "",
        googleCalendarTokenExpiry: 0
    )

    // Backward-compatible decoding — new fields default gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .system
        focusModeOnType = try container.decodeIfPresent(Bool.self, forKey: .focusModeOnType) ?? false
        preferredAIEngine = try container.decodeIfPresent(PreferredAIEngine.self, forKey: .preferredAIEngine) ?? .auto
        executionPolicy = try container.decodeIfPresent(ExecutionPolicy.self, forKey: .executionPolicy) ?? .ask
        bugbookSkillEnabled = try container.decodeIfPresent(Bool.self, forKey: .bugbookSkillEnabled) ?? false
        agentsMdContent = try container.decodeIfPresent(String.self, forKey: .agentsMdContent) ?? ""
        qmdSearchMode = try container.decodeIfPresent(QmdSearchMode.self, forKey: .qmdSearchMode) ?? .bm25
        anthropicApiKey = try container.decodeIfPresent(String.self, forKey: .anthropicApiKey) ?? ""
        defaultNewTabPage = try container.decodeIfPresent(String.self, forKey: .defaultNewTabPage) ?? ""
        googleCalendarClientId = try container.decodeIfPresent(String.self, forKey: .googleCalendarClientId) ?? ""
        googleCalendarClientSecret = try container.decodeIfPresent(String.self, forKey: .googleCalendarClientSecret) ?? ""
        googleCalendarRefreshToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarRefreshToken) ?? ""
        googleCalendarAccessToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarAccessToken) ?? ""
        googleCalendarTokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleCalendarTokenExpiry) ?? 0
    }

    init(
        theme: ThemeMode,
        focusModeOnType: Bool,
        preferredAIEngine: PreferredAIEngine,
        executionPolicy: ExecutionPolicy,
        bugbookSkillEnabled: Bool,
        agentsMdContent: String,
        qmdSearchMode: QmdSearchMode,
        anthropicApiKey: String,
        defaultNewTabPage: String,
        googleCalendarClientId: String = "",
        googleCalendarClientSecret: String = "",
        googleCalendarRefreshToken: String = "",
        googleCalendarAccessToken: String = "",
        googleCalendarTokenExpiry: Double = 0
    ) {
        self.theme = theme
        self.focusModeOnType = focusModeOnType
        self.preferredAIEngine = preferredAIEngine
        self.executionPolicy = executionPolicy
        self.bugbookSkillEnabled = bugbookSkillEnabled
        self.agentsMdContent = agentsMdContent
        self.qmdSearchMode = qmdSearchMode
        self.anthropicApiKey = anthropicApiKey
        self.defaultNewTabPage = defaultNewTabPage
        self.googleCalendarClientId = googleCalendarClientId
        self.googleCalendarClientSecret = googleCalendarClientSecret
        self.googleCalendarRefreshToken = googleCalendarRefreshToken
        self.googleCalendarAccessToken = googleCalendarAccessToken
        self.googleCalendarTokenExpiry = googleCalendarTokenExpiry
    }
}
