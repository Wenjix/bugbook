import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom type for editor-to-sidebar page/database reference drags.
    /// Uses a custom identifier so FileTreeView's .onDrop(of: [.text]) doesn't intercept it
    /// (UTType.json conforms to .text, which caused the drag to be swallowed).
    static let sidebarReference = UTType(exportedAs: "com.dahso.sidebar-reference")
}

struct SidebarReferenceDragPayload: Codable, Transferable, Equatable {
    let path: String
    let kind: String

    static func page(path: String) -> SidebarReferenceDragPayload {
        SidebarReferenceDragPayload(path: path, kind: "page")
    }

    static func database(path: String) -> SidebarReferenceDragPayload {
        SidebarReferenceDragPayload(path: path, kind: "database")
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .sidebarReference)
    }
}
