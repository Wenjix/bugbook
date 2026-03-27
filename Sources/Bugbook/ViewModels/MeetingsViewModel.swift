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
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let weekday = cal.component(.weekday, from: now)
        // Monday-based: weekday 1 = Sunday, 2 = Monday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7
        let startOfThisWeek = cal.date(byAdding: .day, value: -daysSinceMonday, to: startOfToday)!
        let startOfLastWeek = cal.date(byAdding: .day, value: -7, to: startOfThisWeek)!

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
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: workspace),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [DiscoveredMeeting] = []

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            if WorkspacePathRules.shouldIgnoreAbsolutePath(url.path) {
                continue
            }
            // Skip trash
            if url.path.contains("/.trash/") { continue }

            let filePath = url.path
            let filename = url.lastPathComponent
            let pageName = String(filename.dropLast(3)) // strip .md

            // Compute parent page name relative to workspace
            let relativePath = String(filePath.dropFirst(workspace.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parentPageName = (relativePath as NSString).deletingLastPathComponent
            let displayParent = parentPageName.isEmpty ? pageName : "\(parentPageName)/\(pageName)"

            // Strategy 1: Look for <!-- meeting --> blocks inside file content
            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                let meetingMatches = parseMeetingBlocks(content: content, pageName: pageName, parentDisplay: displayParent, filePath: filePath)
                results.append(contentsOf: meetingMatches)
                if !meetingMatches.isEmpty { continue }
            }

            // Strategy 2: Date-prefixed meeting note pattern (YYYY-MM-DD - Title.md)
            if let meeting = parseDatePrefixedMeeting(filename: filename, displayParent: displayParent, filePath: filePath) {
                results.append(meeting)
            }
        }

        return results
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

    /// Parse date-prefixed meeting note files like "2024-01-15 - Weekly Standup.md"
    /// or "2024-01-15 \u{2014} Weekly Standup.md"
    private nonisolated static func parseDatePrefixedMeeting(
        filename: String,
        displayParent: String,
        filePath: String
    ) -> DiscoveredMeeting? {
        let name = String(filename.dropLast(3)) // strip .md
        // Match YYYY-MM-DD followed by separator
        guard name.count >= 10 else { return nil }
        let datePrefix = String(name.prefix(10))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: datePrefix) else { return nil }

        // Extract title after separator (dash, em-dash, or pipe)
        let afterDate = String(name.dropFirst(10)).trimmingCharacters(in: .whitespaces)
        let title: String
        if afterDate.hasPrefix("\u{2014}") || afterDate.hasPrefix("-") || afterDate.hasPrefix("|") {
            title = String(afterDate.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if afterDate.isEmpty {
            title = datePrefix
        } else {
            // Doesn't match the meeting note pattern
            return nil
        }

        guard !title.isEmpty else { return nil }

        return DiscoveredMeeting(
            title: title,
            timestamp: date,
            parentPageName: displayParent,
            filePath: filePath
        )
    }

    // MARK: - Helpers

    private nonisolated static func extractFirstHeading(from text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // Strip leading #s and space
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                guard level <= 6, trimmed.count > level else { continue }
                let idx = trimmed.index(trimmed.startIndex, offsetBy: level)
                if trimmed[idx] == " " {
                    let heading = String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                    if !heading.isEmpty { return heading }
                }
            }
        }
        return nil
    }

    private nonisolated static func extractDateFromMetadata(_ text: String) -> Date? {
        // Look for **Date:** EEEE, MMMM d, yyyy  or  yyyy-MM-dd
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("**Date:**") else { continue }
            let dateStr = String(trimmed.dropFirst("**Date:**".count)).trimmingCharacters(in: .whitespaces)

            // Try long format first
            let longFmt = DateFormatter()
            longFmt.dateFormat = "EEEE, MMMM d, yyyy"
            longFmt.locale = Locale(identifier: "en_US_POSIX")
            if let date = longFmt.date(from: dateStr) { return date }

            // Try ISO-style
            let isoFmt = DateFormatter()
            isoFmt.dateFormat = "yyyy-MM-dd"
            isoFmt.locale = Locale(identifier: "en_US_POSIX")
            if let date = isoFmt.date(from: dateStr) { return date }
        }
        return nil
    }

    private nonisolated static func fileModDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
    }
}
