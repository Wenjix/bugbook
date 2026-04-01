import Foundation
import AuthenticationServices
import AppKit

enum GoogleAuthError: LocalizedError {
    case missingClientConfiguration
    case notAuthenticated
    case missingScopes([String])
    case oauthFailed(String)
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .missingClientConfiguration:
            return "Add your Google OAuth client ID and client secret in Settings before connecting."
        case .notAuthenticated:
            return "Sign in to Google before using Mail or Calendar."
        case .missingScopes(let scopes):
            return "Google access is missing required scopes: \(scopes.joined(separator: ", ")). Sign in again to grant access."
        case .oauthFailed(let message):
            return "Google sign-in failed: \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh the Google access token. Sign in again."
        }
    }
}

struct GoogleOAuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var grantedScopes: [String]

    var isExpired: Bool { Date() >= expiresAt }
}

struct GoogleOAuthResult: Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
    var grantedScopes: [String]
}

enum GoogleScopeSet {
    static let userEmail = "https://www.googleapis.com/auth/userinfo.email"
    static let calendarReadonly = "https://www.googleapis.com/auth/calendar.readonly"
    static let calendarEvents = "https://www.googleapis.com/auth/calendar.events"
    static let calendarListReadonly = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    static let gmailModify = "https://www.googleapis.com/auth/gmail.modify"
    static let gmailSend = "https://www.googleapis.com/auth/gmail.send"

    static let calendar = [
        calendarEvents,
        calendarListReadonly,
        userEmail,
    ]

    static let mail = [
        gmailModify,
        gmailSend,
        userEmail,
    ]

    static let calendarAndMail = Array(Set(calendar + mail)).sorted()
}

enum GoogleAuthService {
    private static let redirectURI = "http://127.0.0.1"

    @MainActor
    static func signIn(using settings: AppSettings, scopes: [String]) async throws -> GoogleOAuthResult {
        let clientID = settings.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = settings.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw GoogleAuthError.missingClientConfiguration
        }

        let normalizedScopes = normalized(scopeList: scopes)
        let authCode = try await requestAuthCode(clientID: clientID, scopes: normalizedScopes)
        let tokenResult = try await exchangeCode(
            authCode,
            clientID: clientID,
            clientSecret: clientSecret,
            scopes: normalizedScopes
        )
        let email = try await fetchUserEmail(accessToken: tokenResult.accessToken)

        return GoogleOAuthResult(
            accessToken: tokenResult.accessToken,
            refreshToken: tokenResult.refreshToken,
            expiresAt: tokenResult.expiresAt,
            email: email,
            grantedScopes: normalizedScopes
        )
    }

    static func validToken(using settings: inout AppSettings, requiredScopes: [String]) async throws -> GoogleOAuthToken {
        guard settings.googleConfigured else {
            throw GoogleAuthError.missingClientConfiguration
        }
        guard var token = settings.googleToken else {
            throw GoogleAuthError.notAuthenticated
        }

        let normalizedScopes = normalized(scopeList: requiredScopes)
        let granted = Set(token.grantedScopes)
        let missingScopes = normalizedScopes.filter { !granted.contains($0) }
        guard missingScopes.isEmpty else {
            throw GoogleAuthError.missingScopes(missingScopes)
        }

        if token.isExpired {
            token = try await refreshToken(
                token,
                clientID: settings.googleClientID,
                clientSecret: settings.googleClientSecret
            )
            settings.updateGoogleToken(token)
        }

        return token
    }

    private static func normalized(scopeList: [String]) -> [String] {
        Array(Set(scopeList.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    @MainActor
    private static func requestAuthCode(clientID: String, scopes: [String]) async throws -> String {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "http"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: GoogleAuthError.oauthFailed(error.localizedDescription))
                    return
                }

                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleAuthError.oauthFailed("No authorization code received."))
                    return
                }

                continuation.resume(returning: code)
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = GoogleAuthPresentationContext.shared
            session.start()
        }
    }

    private static func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        scopes: [String]
    ) async throws -> GoogleOAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.oauthFailed("Token exchange failed: \(message)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw GoogleAuthError.oauthFailed("Unexpected token response format.")
        }

        return GoogleOAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            grantedScopes: normalizedGrantedScopes(from: json["scope"] as? String, fallback: scopes)
        )
    }

    private static func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            throw GoogleAuthError.oauthFailed("Unable to fetch the connected Google account email.")
        }

        return email
    }

    private static func refreshToken(
        _ token: GoogleOAuthToken,
        clientID: String,
        clientSecret: String
    ) async throws -> GoogleOAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: token.refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleAuthError.tokenRefreshFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw GoogleAuthError.tokenRefreshFailed
        }

        return GoogleOAuthToken(
            accessToken: accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            grantedScopes: normalizedGrantedScopes(from: json["scope"] as? String, fallback: token.grantedScopes)
        )
    }

    private static func normalizedGrantedScopes(from scopeString: String?, fallback: [String]) -> [String] {
        guard let scopeString else {
            return normalized(scopeList: fallback)
        }
        let scopes = scopeString
            .split(separator: " ")
            .map(String.init)
        return normalized(scopeList: scopes.isEmpty ? fallback : scopes)
    }
}

private final class GoogleAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
