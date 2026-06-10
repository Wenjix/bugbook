import Foundation

/// Metadata embedded in a Bugbook HTML artifact via <meta> tags.
///
/// HTML has no YAML frontmatter, so artifacts declare metadata in the document
/// head. Parsing is a bounded scan of the first 4 KB with regular expressions —
/// deliberately not an HTML parser. Shared by the app, CLI, and iOS so all
/// surfaces agree on what makes a file an artifact.
///
///     <meta name="bugbook-artifact" content="1">
///     <meta name="bugbook-title" content="Sleep Trends — 2026-W23">
///     <meta name="bugbook-icon" content="sf:bed.double">
///     <meta name="bugbook-generator" content="claude-code/wreview">
///     <script type="application/bugbook-manifest">{ ... }</script>  <!-- L2+, inert at L1 -->
public struct ArtifactManifest: Equatable, Sendable {
    /// Only the first 4 KB of the file is scanned; tags beyond it are ignored.
    public static let scanByteLimit = 4096

    /// Format version from the `bugbook-artifact` marker (defaults to 1).
    public var version: Int
    public var title: String?
    public var icon: String?
    public var generator: String?
    /// True when an `application/bugbook-manifest` script block exists in the
    /// scanned window — present means the artifact *requests* capabilities.
    /// Level 1 treats it as inert; the native grant is the only authority.
    public var hasCapabilityBlock: Bool
    /// Parsed capability request, nil when absent or malformed.
    public var capabilities: CapabilityRequest?

    public struct CapabilityRequest: Equatable, Sendable, Decodable {
        public var manifestVersion: Int
        public var query: [String]
        public var mutate: [String]

        private enum CodingKeys: String, CodingKey {
            case manifestVersion
            case capabilities
        }

        private enum CapabilityKeys: String, CodingKey {
            case query
            case mutate
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1
            if let caps = try? container.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities) {
                query = (try? caps.decodeIfPresent([String].self, forKey: .query)) ?? []
                mutate = (try? caps.decodeIfPresent([String].self, forKey: .mutate)) ?? []
            } else {
                query = []
                mutate = []
            }
        }
    }

    /// Parses the manifest from HTML text. Returns nil when the
    /// `bugbook-artifact` marker is absent from the first 4 KB.
    public static func parse(_ html: String) -> ArtifactManifest? {
        let head = boundedHead(of: html)
        guard let marker = metaContent(named: "bugbook-artifact", in: head) else { return nil }

        let manifestJSON = capabilityBlockJSON(in: head)
        var capabilities: CapabilityRequest?
        if let manifestJSON, let data = manifestJSON.data(using: .utf8) {
            capabilities = try? JSONDecoder().decode(CapabilityRequest.self, from: data)
        }

        return ArtifactManifest(
            version: Int(marker.trimmingCharacters(in: .whitespaces)) ?? 1,
            title: metaContent(named: "bugbook-title", in: head),
            icon: metaContent(named: "bugbook-icon", in: head),
            generator: metaContent(named: "bugbook-generator", in: head),
            hasCapabilityBlock: manifestJSON != nil,
            capabilities: capabilities
        )
    }

    /// Reads at most `scanByteLimit` bytes from disk and parses.
    /// Returns nil for unreadable files or files without the marker.
    public static func load(contentsOf url: URL) -> ArtifactManifest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: scanByteLimit), !data.isEmpty else { return nil }
        // Lossy decode: a multi-byte character truncated at the boundary becomes
        // a replacement character instead of failing the whole scan.
        return parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Internals

    private static func boundedHead(of html: String) -> String {
        let utf8 = html.utf8
        guard utf8.count > scanByteLimit else { return html }
        return String(decoding: Array(utf8.prefix(scanByteLimit)), as: UTF8.self)
    }

    /// Extracts content for `<meta name="..." content="...">`, tolerating either
    /// attribute order, single or double quotes, and any case.
    static func metaContent(named name: String, in head: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let nameFirst = "<meta\\b[^>]*?\\bname\\s*=\\s*[\"']\(escaped)[\"'][^>]*?\\bcontent\\s*=\\s*[\"']([^\"']*)[\"']"
        let contentFirst = "<meta\\b[^>]*?\\bcontent\\s*=\\s*[\"']([^\"']*)[\"'][^>]*?\\bname\\s*=\\s*[\"']\(escaped)[\"']"
        for pattern in [nameFirst, contentFirst] {
            if let value = firstCapture(pattern: pattern, in: head) {
                return value
            }
        }
        return nil
    }

    private static func capabilityBlockJSON(in head: String) -> String? {
        let pattern = "<script\\b[^>]*?\\btype\\s*=\\s*[\"']application/bugbook-manifest[\"'][^>]*>([\\s\\S]*?)</script>"
        return firstCapture(pattern: pattern, in: head)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}
