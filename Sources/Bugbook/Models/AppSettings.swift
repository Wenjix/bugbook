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

    var displayName: String {
        switch self {
        case .haiku: return "Haiku (fast)"
        case .sonnet: return "Sonnet (quality)"
        }
    }
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
    var anthropicModel: AnthropicModel
    /// Path to the page opened for new/empty tabs. Empty string = default Bugbook landing page.
    var defaultNewTabPage: String

    // Google Calendar
    var googleCalendarRefreshToken: String
    var googleCalendarAccessToken: String
    var googleCalendarTokenExpiry: Double
    var googleCalendarConnectedEmail: String
    var googleCalendarBannerDismissed: Bool

    static let `default` = AppSettings(
        theme: .system,
        focusModeOnType: false,
        preferredAIEngine: .auto,
        executionPolicy: .ask,
        bugbookSkillEnabled: false,
        agentsMdContent: "",
        qmdSearchMode: .bm25,
        anthropicApiKey: "",
        anthropicModel: .sonnet,
        defaultNewTabPage: "",
        googleCalendarRefreshToken: "",
        googleCalendarAccessToken: "",
        googleCalendarTokenExpiry: 0,
        googleCalendarConnectedEmail: "",
        googleCalendarBannerDismissed: false
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
        anthropicModel = try container.decodeIfPresent(AnthropicModel.self, forKey: .anthropicModel) ?? .sonnet
        defaultNewTabPage = try container.decodeIfPresent(String.self, forKey: .defaultNewTabPage) ?? ""
        googleCalendarRefreshToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarRefreshToken) ?? ""
        googleCalendarAccessToken = try container.decodeIfPresent(String.self, forKey: .googleCalendarAccessToken) ?? ""
        googleCalendarTokenExpiry = try container.decodeIfPresent(Double.self, forKey: .googleCalendarTokenExpiry) ?? 0
        googleCalendarConnectedEmail = try container.decodeIfPresent(String.self, forKey: .googleCalendarConnectedEmail) ?? ""
        googleCalendarBannerDismissed = try container.decodeIfPresent(Bool.self, forKey: .googleCalendarBannerDismissed) ?? false
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
        anthropicModel: AnthropicModel = .sonnet,
        defaultNewTabPage: String,
        googleCalendarRefreshToken: String = "",
        googleCalendarAccessToken: String = "",
        googleCalendarTokenExpiry: Double = 0,
        googleCalendarConnectedEmail: String = "",
        googleCalendarBannerDismissed: Bool = false
    ) {
        self.theme = theme
        self.focusModeOnType = focusModeOnType
        self.preferredAIEngine = preferredAIEngine
        self.executionPolicy = executionPolicy
        self.bugbookSkillEnabled = bugbookSkillEnabled
        self.agentsMdContent = agentsMdContent
        self.qmdSearchMode = qmdSearchMode
        self.anthropicApiKey = anthropicApiKey
        self.anthropicModel = anthropicModel
        self.defaultNewTabPage = defaultNewTabPage
        self.googleCalendarRefreshToken = googleCalendarRefreshToken
        self.googleCalendarAccessToken = googleCalendarAccessToken
        self.googleCalendarTokenExpiry = googleCalendarTokenExpiry
        self.googleCalendarConnectedEmail = googleCalendarConnectedEmail
        self.googleCalendarBannerDismissed = googleCalendarBannerDismissed
    }
}
