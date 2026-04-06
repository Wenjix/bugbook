import UIKit
import Social
import BugbookCore

class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let text = contentText ?? ""
        let title = text.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "Shared Note" : String(title)

        // Resolve the canonical iCloud workspace. This works from app extensions
        // as long as the entitlements include the ubiquity container identifier.
        let workspace = WorkspaceResolver.defaultWorkspacePath(allowBlockingICloudLookup: true)

        do {
            try RawInboxWriter.writeRawNote(
                workspace: workspace,
                title: displayTitle,
                body: text
            )
        } catch {
            NSLog("[BugbookShareExtension] Failed to write note: %@", "\(error)")
        }

        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
