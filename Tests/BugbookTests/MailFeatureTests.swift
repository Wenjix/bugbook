import Foundation
import XCTest
@testable import Bugbook

@MainActor
final class MailFeatureTests: XCTestCase {
    func testMailDocumentFactoryProducesMailOpenFile() throws {
        let content = PaneContent.mailDocument()

        guard case .document(let openFile) = content else {
            XCTFail("Expected a document pane.")
            return
        }

        XCTAssertEqual(openFile.kind, .mail)
        XCTAssertTrue(openFile.isMail)
        XCTAssertEqual(openFile.path, "bugbook://mail")
        XCTAssertEqual(openFile.displayName, "Mail")
        XCTAssertEqual(openFile.icon, "envelope")
        XCTAssertFalse(openFile.isEmptyTab)
    }

    func testTabKindMailFlags() {
        XCTAssertTrue(TabKind.mail.isMail)
        XCTAssertFalse(TabKind.mail.isCalendar)
        XCTAssertFalse(TabKind.mail.isMeetings)
        XCTAssertFalse(TabKind.mail.isDatabase)
    }

    func testAppSettingsDecodesLegacyCalendarGoogleFields() throws {
        let json = """
        {
          "googleClientID": "client-id",
          "googleClientSecret": "client-secret",
          "googleCalendarRefreshToken": "legacy-refresh",
          "googleCalendarAccessToken": "legacy-access",
          "googleCalendarTokenExpiry": 1234,
          "googleCalendarConnectedEmail": "legacy@example.com"
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.googleClientID, "client-id")
        XCTAssertEqual(settings.googleClientSecret, "client-secret")
        XCTAssertEqual(settings.googleRefreshToken, "legacy-refresh")
        XCTAssertEqual(settings.googleAccessToken, "legacy-access")
        XCTAssertEqual(settings.googleTokenExpiry, 1234)
        XCTAssertEqual(settings.googleConnectedEmail, "legacy@example.com")
    }

    func testAppSettingsGoogleTokenHelpers() throws {
        var settings = AppSettings.default
        let result = GoogleOAuthResult(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            email: "user@example.com",
            grantedScopes: GoogleScopeSet.calendarAndMail
        )

        settings.applyGoogleAuthResult(result)

        XCTAssertTrue(settings.googleConfigured == false)
        XCTAssertTrue(settings.googleConnected)
        XCTAssertEqual(settings.googleConnectedEmail, "user@example.com")
        XCTAssertEqual(settings.googleGrantedScopes, GoogleScopeSet.calendarAndMail)

        let initialToken = try XCTUnwrap(settings.googleToken)
        XCTAssertEqual(initialToken.accessToken, "access-token")
        XCTAssertEqual(initialToken.refreshToken, "refresh-token")
        XCTAssertEqual(initialToken.expiresAt, Date(timeIntervalSince1970: 1_000))

        let refreshedToken = GoogleOAuthToken(
            accessToken: "new-access",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 2_000),
            grantedScopes: GoogleScopeSet.mail
        )
        settings.updateGoogleToken(refreshedToken)

        let updatedToken = try XCTUnwrap(settings.googleToken)
        XCTAssertEqual(updatedToken.accessToken, "new-access")
        XCTAssertEqual(updatedToken.expiresAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(updatedToken.grantedScopes, GoogleScopeSet.mail)

        settings.disconnectGoogle()
        XCTAssertFalse(settings.googleConnected)
        XCTAssertNil(settings.googleToken)
        XCTAssertEqual(settings.googleConnectedEmail, "")
        XCTAssertTrue(settings.googleGrantedScopes.isEmpty)
    }

    func testAppSettingsStorePersistsSharedGoogleSettings() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = AppSettingsStore(fileURL: directoryURL.appendingPathComponent("app-settings.json"))
        var settings = AppSettings.default
        settings.googleClientID = "client-id"
        settings.googleClientSecret = "client-secret"
        settings.googleAccessToken = "access-token"
        settings.googleRefreshToken = "refresh-token"
        settings.googleTokenExpiry = 9_999
        settings.googleConnectedEmail = "user@example.com"
        settings.googleGrantedScopes = GoogleScopeSet.calendarAndMail

        store.save(settings)
        let loaded = store.load()

        XCTAssertEqual(loaded, settings)
    }

    func testMailCacheStoreRoundTripsSnapshot() throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = MailCacheStore(directoryURL: directoryURL)
        let snapshot = sampleSnapshot(savedAt: Date(timeIntervalSince1970: 4_242))

        store.save(snapshot, accountEmail: "Test.User+alias@gmail.com")
        let loaded = try XCTUnwrap(store.load(accountEmail: "Test.User+alias@gmail.com"))

        XCTAssertEqual(loaded, snapshot)
    }

    func testMailServiceLoadCachedDataClearsPreviousStateWithoutSnapshot() {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let service = MailService(cacheStore: MailCacheStore(directoryURL: directoryURL))
        let snapshot = sampleSnapshot(savedAt: Date(timeIntervalSince1970: 200))
        service.mailboxThreads = snapshot.mailboxThreads
        service.threadDetails = snapshot.threadDetails
        service.selectedThreadID = "thread-1"
        service.searchState = MailSearchState(query: "old")
        service.searchResults = snapshot.mailboxThreads[.inbox] ?? []
        service.lastSyncDate = snapshot.savedAt

        service.loadCachedData(accountEmail: "new-account@example.com")

        XCTAssertTrue(service.mailboxThreads.isEmpty)
        XCTAssertTrue(service.threadDetails.isEmpty)
        XCTAssertEqual(service.searchState, MailSearchState())
        XCTAssertTrue(service.searchResults.isEmpty)
        XCTAssertNil(service.selectedThreadID)
        XCTAssertNil(service.lastSyncDate)
    }

    func testMailComposerEncoderBuildsBase64URLReplyPayload() throws {
        let draft = MailDraft(
            mode: .replyAll,
            to: "alice@example.com",
            cc: "bob@example.com",
            bcc: "carol@example.com",
            subject: "Re: Project",
            body: "Thanks for the update.",
            threadId: "thread-1",
            replyToMessageID: "<message-1@example.com>",
            referencesHeader: "<message-0@example.com> <message-1@example.com>"
        )

        let encoded = MailComposerEncoder.buildRawMessage(draft: draft, connectedEmail: "me@example.com")
        let decoded = try XCTUnwrap(decodeBase64URL(encoded))

        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertTrue(decoded.contains("From: me@example.com\r\n"))
        XCTAssertTrue(decoded.contains("To: alice@example.com\r\n"))
        XCTAssertTrue(decoded.contains("Cc: bob@example.com\r\n"))
        XCTAssertTrue(decoded.contains("Bcc: carol@example.com\r\n"))
        XCTAssertTrue(decoded.contains("In-Reply-To: <message-1@example.com>\r\n"))
        XCTAssertTrue(decoded.contains("References: <message-0@example.com> <message-1@example.com>\r\n"))
        XCTAssertTrue(decoded.hasSuffix("\r\n\r\nThanks for the update."))
    }

    func testMailThreadLabelReducerArchiveAndUnreadMutations() {
        let initialLabels = ["INBOX", "STARRED", "UNREAD"]

        let archived = MailThreadLabelReducer.mutatedLabels(initialLabels, action: .archive)
        XCTAssertFalse(archived.contains("INBOX"))
        XCTAssertTrue(archived.contains("STARRED"))
        XCTAssertTrue(archived.contains("UNREAD"))
        XCTAssertFalse(MailThreadLabelReducer.mailbox(.inbox, contains: archived))
        XCTAssertTrue(MailThreadLabelReducer.mailbox(.starred, contains: archived))

        let markedRead = MailThreadLabelReducer.mutatedLabels(archived, action: .setUnread(false))
        XCTAssertFalse(markedRead.contains("UNREAD"))

        let trashed = MailThreadLabelReducer.mutatedLabels(markedRead, action: .trash)
        XCTAssertTrue(trashed.contains("TRASH"))
        XCTAssertTrue(MailThreadLabelReducer.mailbox(.trash, contains: trashed))

        let restored = MailThreadLabelReducer.mutatedLabels(trashed, action: .untrash)
        XCTAssertTrue(restored.contains("INBOX"))
        XCTAssertFalse(restored.contains("TRASH"))
    }

    private func sampleSnapshot(savedAt: Date) -> MailCacheSnapshot {
        let sender = MailMessageRecipient(name: "Alice", email: "alice@example.com")
        let message = MailMessage(
            id: "message-1",
            threadId: "thread-1",
            subject: "Hello",
            snippet: "Test snippet",
            labelIds: ["INBOX", "UNREAD"],
            from: sender,
            to: [MailMessageRecipient(name: "Me", email: "me@example.com")],
            cc: [],
            bcc: [],
            date: Date(timeIntervalSince1970: 100),
            plainBody: "Hello world",
            htmlBody: nil,
            messageIDHeader: "<message-1@example.com>",
            referencesHeader: nil
        )

        let detail = MailThreadDetail(
            id: "thread-1",
            mailbox: .inbox,
            subject: "Hello",
            snippet: "Test snippet",
            participants: [sender.displayName],
            messages: [message],
            labelIds: ["INBOX", "UNREAD"],
            historyId: "history-1"
        )

        let summary = MailThreadSummary(
            id: "thread-1",
            mailbox: .inbox,
            subject: "Hello",
            snippet: "Test snippet",
            participants: [sender.displayName],
            date: Date(timeIntervalSince1970: 100),
            messageCount: 1,
            labelIds: ["INBOX", "UNREAD"]
        )

        return MailCacheSnapshot(
            mailboxThreads: [.inbox: [summary]],
            threadDetails: ["thread-1": detail],
            savedAt: savedAt
        )
    }

    private func temporaryDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func decodeBase64URL(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
