import Foundation
import AuthenticationServices
import AppKit
import Network

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

private struct GoogleOAuthAuthorizationGrant {
    var code: String
    var redirectURI: String
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
    private static let redirectHost = "127.0.0.1"
    private static let redirectPath = "/oauth/callback"

    @MainActor
    static func signIn(using settings: AppSettings, scopes: [String]) async throws -> GoogleOAuthResult {
        let clientID = settings.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = settings.googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw GoogleAuthError.missingClientConfiguration
        }

        let normalizedScopes = normalized(scopeList: scopes)
        let grant = try await requestAuthCode(clientID: clientID, scopes: normalizedScopes)
        let tokenResult = try await exchangeCode(
            grant.code,
            redirectURI: grant.redirectURI,
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
    private static func requestAuthCode(clientID: String, scopes: [String]) async throws -> GoogleOAuthAuthorizationGrant {
        let callbackServer = try GoogleOAuthLoopbackServer.start(host: redirectHost, path: redirectPath)
        defer { callbackServer.stop() }

        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callbackServer.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let resolver = GoogleAuthRequestResolver()
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: nil
            ) { _, error in
                if let error {
                    Task {
                        resolver.resumeIfNeeded(
                            continuation,
                            result: .failure(GoogleAuthError.oauthFailed(error.localizedDescription))
                        )
                    }
                    return
                }
                Task {
                    resolver.resumeIfNeeded(
                        continuation,
                        result: .failure(GoogleAuthError.oauthFailed("No authorization code received."))
                    )
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = GoogleAuthPresentationContext.shared

            Task {
                do {
                    let response = try await callbackServer.waitForCallback()
                    guard response.state == state else {
                        throw GoogleAuthError.oauthFailed("OAuth state validation failed.")
                    }

                    resolver.resumeIfNeeded(
                        continuation,
                        result: .success(
                            GoogleOAuthAuthorizationGrant(
                                code: response.code,
                                redirectURI: callbackServer.redirectURI.absoluteString
                            )
                        )
                    )
                    await MainActor.run {
                        session.cancel()
                    }
                } catch {
                    resolver.resumeIfNeeded(continuation, result: .failure(error))
                    await MainActor.run {
                        session.cancel()
                    }
                }
            }

            if session.start() == false {
                Task {
                    resolver.resumeIfNeeded(
                        continuation,
                        result: .failure(GoogleAuthError.oauthFailed("Unable to start Google sign-in."))
                    )
                }
            }
        }
    }

    private static func exchangeCode(
        _ code: String,
        redirectURI: String,
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

private final class GoogleAuthRequestResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resumeIfNeeded(
        _ continuation: CheckedContinuation<GoogleOAuthAuthorizationGrant, Error>,
        result: Result<GoogleOAuthAuthorizationGrant, Error>
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard hasResumed == false else { return }
        hasResumed = true

        switch result {
        case .success(let grant):
            continuation.resume(returning: grant)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

struct GoogleOAuthLoopbackCallback: Equatable {
    var code: String
    var state: String
}

struct GoogleOAuthLoopbackRequestParser {
    static func parse(requestLine: String, host: String) throws -> GoogleOAuthLoopbackCallback {
        let segments = requestLine.split(separator: " ")
        guard segments.count >= 2 else {
            throw GoogleAuthError.oauthFailed("Malformed OAuth callback request.")
        }

        guard let components = URLComponents(string: "http://\(host)\(segments[1])") else {
            throw GoogleAuthError.oauthFailed("Malformed OAuth callback URL.")
        }

        let queryItems = components.queryItems ?? []
        if let errorCode = queryItems.first(where: { $0.name == "error" })?.value {
            throw GoogleAuthError.oauthFailed(errorCode)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              let state = queryItems.first(where: { $0.name == "state" })?.value,
              code.isEmpty == false,
              state.isEmpty == false else {
            throw GoogleAuthError.oauthFailed("No authorization code received.")
        }

        return GoogleOAuthLoopbackCallback(code: code, state: state)
    }
}

private final class GoogleOAuthLoopbackServer: @unchecked Sendable {
    private(set) var redirectURI: URL!

    private let listener: NWListener
    private let host: String
    private let path: String
    private let queue = DispatchQueue(label: "Bugbook.GoogleOAuthLoopback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<GoogleOAuthLoopbackCallback, Error>?
    private var pendingResult: Result<GoogleOAuthLoopbackCallback, Error>?

    static func start(host: String, path: String) throws -> GoogleOAuthLoopbackServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = GoogleOAuthLoopbackServer(listener: listener, host: host, path: path)
        try server.start()
        return server
    }

    private init(listener: NWListener, host: String, path: String) {
        self.listener = listener
        self.host = host
        self.path = path
    }

    private func start() throws {
        let readySemaphore = DispatchSemaphore(value: 0)
        var startupError: Error?

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                readySemaphore.signal()
            case .failed(let error):
                startupError = error
                readySemaphore.signal()
                self?.finish(with: .failure(GoogleAuthError.oauthFailed(error.localizedDescription)))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        readySemaphore.wait()

        if let startupError {
            throw startupError
        }

        guard let port = listener.port?.rawValue else {
            throw GoogleAuthError.oauthFailed("Unable to allocate a localhost redirect port.")
        }

        redirectURI = URL(string: "http://\(host):\(port)\(path)")!
    }

    func waitForCallback() async throws -> GoogleOAuthLoopbackCallback {
        if let pendingResult = consumePendingResult() {
            return try pendingResult.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingResult = pendingResult {
                self.pendingResult = nil
                lock.unlock()
                continuation.resume(with: pendingResult)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, data: Data())
    }

    private func receiveRequest(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(GoogleAuthError.oauthFailed(error.localizedDescription)))
                connection.cancel()
                return
            }

            var accumulated = data
            if let chunk {
                accumulated.append(chunk)
            }

            if accumulated.range(of: Data("\r\n\r\n".utf8)) == nil, isComplete == false {
                self.receiveRequest(on: connection, data: accumulated)
                return
            }

            let request = String(decoding: accumulated, as: UTF8.self)
            let requestLine = request.components(separatedBy: "\r\n").first ?? ""

            let result: Result<GoogleOAuthLoopbackCallback, Error>
            do {
                let callback = try GoogleOAuthLoopbackRequestParser.parse(requestLine: requestLine, host: self.host)
                result = .success(callback)
                self.respond(on: connection, body: """
                <html><body><p>You can close this window and return to Bugbook.</p><script>window.close()</script></body></html>
                """)
            } catch {
                result = .failure(error)
                self.respond(on: connection, body: """
                <html><body><p>Bugbook sign-in failed. You can close this window and return to the app.</p><script>window.close()</script></body></html>
                """)
            }

            self.finish(with: result)
        }
    }

    private func respond(on connection: NWConnection, body: String) {
        let data = Data("""
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """.utf8)

        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<GoogleOAuthLoopbackCallback, Error>) {
        lock.lock()
        defer { lock.unlock() }

        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }

    private func consumePendingResult() -> Result<GoogleOAuthLoopbackCallback, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let result = pendingResult
        pendingResult = nil
        return result
    }
}

private final class GoogleAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
