import Foundation
import BugbookCore

/// A meeting discovered from a workspace page.
struct DiscoveredMeeting: Identifiable {
    let id = UUID()
    let title: String
    let timestamp: Date
    let parentPageName: String
    let filePath: String
}

/// Recency bucket for grouping meetings.
enum RecencyBucket: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case older = "Older"
}

@MainActor
@Observable
final class MeetingsViewModel {
    var meetings: [DiscoveredMeeting] = []
    var isScanning = false
    var error: String?

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    // MARK: - Grouped Accessor

    var groupedMeetings: [(bucket: RecencyBucket, meetings: [DiscoveredMeeting])] {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: now)
        // Monday-based: weekday 1 = Sunday, 2 = Monday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7
        guard let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfThisWeek = cal.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday),
              let startOfLastWeek = cal.date(byAdding: .day, value: -7, to: startOfThisWeek) else {
            let sortedMeetings = meetings.sorted { $0.timestamp > $1.timestamp }
            return sortedMeetings.isEmpty ? [] : [(.older, sortedMeetings)]
        }

        var buckets: [RecencyBucket: [DiscoveredMeeting]] = [:]
        for meeting in meetings {
            let bucket: RecencyBucket
            if meeting.timestamp >= startOfToday {
                bucket = .today
            } else if meeting.timestamp >= startOfYesterday {
                bucket = .yesterday
            } else if meeting.timestamp >= startOfThisWeek {
                bucket = .thisWeek
            } else if meeting.timestamp >= startOfLastWeek {
                bucket = .lastWeek
            } else {
                bucket = .older
            }
            buckets[bucket, default: []].append(meeting)
        }

        // Sort meetings within each bucket by timestamp descending
        for key in buckets.keys {
            buckets[key]?.sort { $0.timestamp > $1.timestamp }
        }

        return RecencyBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return (bucket: bucket, meetings: items)
        }
    }

    // MARK: - Scanning

    func scan(workspace: String) {
        scanTask?.cancel()
        isScanning = true
        error = nil

        scanTask = Task {
            let results = await scanWorkspace(workspace)
            guard !Task.isCancelled else { return }
            self.meetings = results
            self.isScanning = false
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
    }

    // MARK: - Background Scan

    private func scanWorkspace(_ workspace: String) async -> [DiscoveredMeeting] {
        await Task.detached(priority: .utility) {
            Self.performScan(workspace: workspace)
        }.value
    }

    private nonisolated static func performScan(workspace: String) -> [DiscoveredMeeting] {
        let fm = FileManager.default
        let workspaceURL = resolvedWorkspaceURL(for: workspace, fileManager: fm)
        let workspacePath = workspaceURL.path
        guard let enumerator = fm.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [DiscoveredMeeting] = []

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            if WorkspacePathRules.shouldIgnoreAbsolutePath(url.path) {
                continue
            }
            if url.path.contains("/.trash/") { continue }

            let filePath = url.path
            let filename = url.lastPathComponent
            let pageName = String(filename.dropLast(3)) // strip .md

            let relativePath = String(filePath.dropFirst(workspacePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parentPageName = (relativePath as NSString).deletingLastPathComponent
            let displayParent = parentPageName.isEmpty ? pageName : "\(parentPageName)/\(pageName)"

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            // Strategy 1: YAML frontmatter with `type: meeting` — the canonical meeting format
            if let meeting = parseFrontmatterMeeting(content: content, pageName: pageName, displayParent: displayParent, filePath: filePath) {
                results.append(meeting)
                continue
            }

            // Strategy 2: legacy `<!-- meeting -->` blocks embedded in any page
            let meetingMatches = parseMeetingBlocks(content: content, pageName: pageName, parentDisplay: displayParent, filePath: filePath)
            results.append(contentsOf: meetingMatches)
        }

        return results
    }

    private nonisolated static func resolvedWorkspaceURL(for workspace: String, fileManager: FileManager) -> URL {
        let workspaceURL = URL(fileURLWithPath: workspace, isDirectory: true)
        guard let symlinkDestination = try? fileManager.destinationOfSymbolicLink(atPath: workspace) else {
            return workspaceURL
        }

        let destinationPath: String
        if symlinkDestination.hasPrefix("/") {
            destinationPath = symlinkDestination
        } else {
            destinationPath = (workspaceURL.deletingLastPathComponent().path as NSString)
                .appendingPathComponent(symlinkDestination)
        }

        return URL(fileURLWithPath: destinationPath, isDirectory: true).standardizedFileURL
    }

    /// Parse a meeting page that uses `type: meeting` YAML frontmatter.
    /// Returns nil if the file isn't a frontmatter-typed meeting page.
    private nonisolated static func parseFrontmatterMeeting(
        content: String,
        pageName: String,
        displayParent: String,
        filePath: String
    ) -> DiscoveredMeeting? {
        let (yaml, body) = MarkdownBlockParser.stripYAMLFrontmatter(content)
        guard !yaml.isEmpty,
              MarkdownBlockParser.yamlValue(for: "type", in: yaml) == "meeting" else {
            return nil
        }

        let titleField = MarkdownBlockParser.yamlValue(for: "title", in: yaml)
        let dateField = MarkdownBlockParser.yamlValue(for: "date", in: yaml)

        // Prefer the live H1 heading so AI-generated / user-edited titles flow through
        // to the meetings list. Fall back to the YAML field (set at creation) and
        // finally the filename.
        let title = extractFirstHeading(from: body)
            ?? titleField.flatMap { $0.isEmpty ? nil : $0 }
            ?? pageName
        let timestamp = dateField.flatMap(parseISODate) ?? fileModDate(filePath)

        return DiscoveredMeeting(
            title: title,
            timestamp: timestamp,
            parentPageName: displayParent,
            filePath: filePath
        )
    }

    /// Parse `<!-- meeting -->...<!-- /meeting -->` blocks from markdown content.
    /// Extracts title from first heading inside the block, or uses page name.
    /// Extracts timestamp from **Date:** metadata or falls back to file mod date.
    private nonisolated static func parseMeetingBlocks(
        content: String,
        pageName: String,
        parentDisplay: String,
        filePath: String
    ) -> [DiscoveredMeeting] {
        var results: [DiscoveredMeeting] = []

        // Find all <!-- meeting --> ... <!-- /meeting --> blocks
        var searchRange = content.startIndex..<content.endIndex
        let openTag = "<!-- meeting -->"
        let closeTag = "<!-- /meeting -->"

        while let openRange = content.range(of: openTag, range: searchRange) {
            let afterOpen = openRange.upperBound
            guard let closeRange = content.range(of: closeTag, range: afterOpen..<content.endIndex) else {
                break
            }

            let blockContent = String(content[afterOpen..<closeRange.lowerBound])

            // Extract title: first # heading in the block, or page name
            let title = extractFirstHeading(from: blockContent) ?? pageName

            // Extract date: look for **Date:** line
            let timestamp = extractDateFromMetadata(blockContent) ?? fileModDate(filePath)

            results.append(DiscoveredMeeting(
                title: title,
                timestamp: timestamp,
                parentPageName: parentDisplay,
                filePath: filePath
            ))

            searchRange = closeRange.upperBound..<content.endIndex
        }

        return results
    }

    // MARK: - Helpers

    private nonisolated static func extractFirstHeading(from text: String) -> String? {
        var found: String?
        text.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { return }
            var level = 0
            for ch in trimmed {
                if ch == "#" { level += 1 } else { break }
            }
            guard level <= 6, trimmed.count > level else { return }
            let idx = trimmed.index(trimmed.startIndex, offsetBy: level)
            guard trimmed[idx] == " " else { return }
            let heading = String(trimmed[trimmed.index(after: idx)...])
                .trimmingCharacters(in: .whitespaces)
            if !heading.isEmpty {
                found = heading
                stop = true
            }
        }
        return found
    }

    private nonisolated static let legacyLongDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private nonisolated static let legacyShortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private nonisolated static func parseISODate(_ rawValue: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: rawValue)
    }

    private nonisolated static func extractDateFromMetadata(_ text: String) -> Date? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("**Date:**") else { continue }
            let dateStr = String(trimmed.dropFirst("**Date:**".count)).trimmingCharacters(in: .whitespaces)
            if let date = legacyLongDateFormatter.date(from: dateStr) { return date }
            if let date = legacyShortDateFormatter.date(from: dateStr) { return date }
        }
        return nil
    }

    private nonisolated static func fileModDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
    }
}
