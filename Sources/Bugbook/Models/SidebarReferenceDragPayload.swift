import CoreTransferable
import UniformTypeIdentifiers

struct SidebarReferenceDragPayload: Codable, Transferable {
    let path: String
    let kind: String

    static func page(path: String) -> SidebarReferenceDragPayload {
        SidebarReferenceDragPayload(path: path, kind: "page")
    }

    static func database(path: String) -> SidebarReferenceDragPayload {
        SidebarReferenceDragPayload(path: path, kind: "database")
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bugbookSidebarReference)
    }
}

extension UTType {
    static let bugbookSidebarReference = UTType(exportedAs: "com.bugbook.sidebar-reference")
}
