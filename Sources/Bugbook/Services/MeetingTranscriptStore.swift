import Foundation

/// A single transcribed utterance.
struct MeetingTranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    /// Seconds from the start of the recording.
    var timestamp: TimeInterval
    /// Speaker label. "self" = the user, "other" = remote, or a name string. Defaults to "self".
    var speaker: String

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval = 0, speaker: String = "self") {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.speaker = speaker
    }
}

struct MeetingTranscript: Codable, Equatable {
    var entries: [MeetingTranscriptEntry] = []
    var summary: [String] = []
    var actionItems: [String] = []
    /// IDs of blocks injected into the meeting page by AI generation (Summary heading + bullets,
    /// Action Items heading + tasks). Tracked here so regenerate can find and remove them
    /// even if the user has renamed the headings.
    var generatedBlockIds: [UUID] = []
    var createdAt: Date = .now

    var fullText: String {
        entries.map(\.text).joined(separator: " ")
    }
}

enum MeetingTranscriptFormatter {
    static func copyText(entries: [MeetingTranscriptEntry], volatileText: String = "") -> String {
        var lines = entries.map(\.text)
        let trimmedVolatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVolatile.isEmpty {
            lines.append(trimmedVolatile)
        }
        return lines.joined(separator: "\n")
    }
}

/// Persists meeting transcripts to `<workspace>/.bugbook/meetings/<meetingId>.json`.
/// Stored separately from the markdown so transcript size doesn't bloat autosave.
/// Keyed by `meeting_id` UUID stored in the meeting page's YAML frontmatter, so transcripts
/// follow the page through renames and moves.
///
/// Nonisolated so callers can perform file I/O off the main actor via `Task.detached`.
final class MeetingTranscriptStore: @unchecked Sendable {
    private let fm = FileManager.default

    /// Load a transcript by meeting ID, or return an empty one.
    func load(meetingId: String, workspace: String) -> MeetingTranscript {
        let url = fileURL(meetingId: meetingId, workspace: workspace)
        guard fm.fileExists(atPath: url.path) else { return MeetingTranscript() }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(MeetingTranscript.self, from: data)
        } catch {
            Log.app.error("Failed to load meeting transcript \(meetingId): \(error.localizedDescription)")
            return MeetingTranscript()
        }
    }

    func loadAsync(meetingId: String, workspace: String) async -> MeetingTranscript {
        await Task.detached(priority: .utility) {
            self.load(meetingId: meetingId, workspace: workspace)
        }.value
    }

    /// Save a transcript by meeting ID.
    func save(_ transcript: MeetingTranscript, meetingId: String, workspace: String) {
        let url = fileURL(meetingId: meetingId, workspace: workspace)
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(transcript)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.app.error("Failed to save meeting transcript \(meetingId): \(error.localizedDescription)")
        }
    }

    func saveAsync(_ transcript: MeetingTranscript, meetingId: String, workspace: String) async {
        await Task.detached(priority: .utility) {
            self.save(transcript, meetingId: meetingId, workspace: workspace)
        }.value
    }

    private func fileURL(meetingId: String, workspace: String) -> URL {
        URL(fileURLWithPath: workspace, isDirectory: true)
            .appendingPathComponent(".bugbook", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
            .appendingPathComponent("\(meetingId).json")
    }
}
