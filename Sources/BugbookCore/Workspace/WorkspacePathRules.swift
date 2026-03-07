import Foundation

public enum WorkspacePathRules {
    public static func shouldIgnoreRelativePath(_ relativePath: String) -> Bool {
        let components = normalizedComponents(from: relativePath)
        return shouldIgnoreComponents(components)
    }

    public static func shouldIgnoreAbsolutePath(_ absolutePath: String) -> Bool {
        let components = URL(fileURLWithPath: absolutePath).pathComponents.filter { $0 != "/" }
        return shouldIgnoreComponents(components)
    }

    public static func shouldIgnoreComponents(_ components: [String]) -> Bool {
        guard !components.isEmpty else { return false }

        if components.contains(where: { $0.hasPrefix(".") }) {
            return true
        }

        let lowered = components.map { $0.lowercased() }
        if containsSequence(["logseq", "bak"], in: lowered) {
            return true
        }

        return false
    }

    private static func normalizedComponents(from path: String) -> [String] {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func containsSequence(_ sequence: [String], in values: [String]) -> Bool {
        guard !sequence.isEmpty, values.count >= sequence.count else { return false }
        for start in 0...(values.count - sequence.count) {
            if Array(values[start..<(start + sequence.count)]) == sequence {
                return true
            }
        }
        return false
    }
}
