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

        // Resolve workspace off the main thread — url(forUbiquityContainerIdentifier:)
        // can block for seconds and share extensions have tight time budgets.
        let context = extensionContext
        DispatchQueue.global(qos: .userInitiated).async {
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
            context?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }
}
