import Foundation

enum DatabaseRowNavigationPath {
    private static let scheme = "dahso-db-row"
    private static let host = "open"
    private static let dbPathKey = "dbPath"
    private static let rowIdKey = "rowId"

    static func make(dbPath: String, rowId: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: dbPathKey, value: dbPath),
            URLQueryItem(name: rowIdKey, value: rowId),
        ]
        return components.string ?? "\(scheme)://\(host)"
    }

    static func parse(_ value: String) -> (dbPath: String, rowId: String)? {
        guard let components = URLComponents(string: value),
              components.scheme == scheme,
              components.host == host,
              let queryItems = components.queryItems,
              let dbPath = queryItems.first(where: { $0.name == dbPathKey })?.value,
              let rowId = queryItems.first(where: { $0.name == rowIdKey })?.value,
              !dbPath.isEmpty,
              !rowId.isEmpty else {
            return nil
        }
        return (dbPath, rowId)
    }
}
