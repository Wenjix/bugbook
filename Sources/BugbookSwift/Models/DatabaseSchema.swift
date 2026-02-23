import Foundation
import SwiftUI

enum PropertyType: String, Codable, CaseIterable {
    case text
    case number
    case select
    case multiSelect = "multi_select"
    case date
    case checkbox
    case url
    case email
}

struct SelectOption: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var color: String
}

struct PropertyDefinition: Identifiable, Codable {
    let id: String
    var name: String
    var type: PropertyType
    var options: [SelectOption]?
}

enum ViewType: String, Codable, CaseIterable {
    case table
    case kanban
    case list
    case calendar
}

struct SortConfig: Codable, Identifiable {
    let id: String
    var propertyId: String
    var ascending: Bool
}

struct FilterConfig: Codable, Identifiable {
    let id: String
    var propertyId: String
    var `operator`: FilterOperator
    var value: String
}

enum FilterOperator: String, Codable {
    case equals
    case notEquals
    case contains
    case doesNotContain
    case isEmpty
    case isNotEmpty
    case greaterThan
    case lessThan
}

struct ViewConfig: Identifiable, Codable {
    let id: String
    var name: String
    var type: ViewType
    var sorts: [SortConfig]
    var filters: [FilterConfig]
    var columnWidths: [String: CGFloat]?
    var hiddenColumns: [String]?
    var groupByPropertyId: String?
    var datePropertyId: String?
}

struct DatabaseSchema: Codable, Identifiable {
    let id: String
    var name: String
    var properties: [PropertyDefinition]
    var views: [ViewConfig]
    var defaultViewId: String
}
