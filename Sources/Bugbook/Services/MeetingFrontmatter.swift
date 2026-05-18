import Foundation

enum MeetingFrontmatter {
    static func upsertingScalar(key: String, value: String, in yaml: String) -> String {
        guard !yaml.isEmpty else { return "\(key): \(value)" }

        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for index in lines.indices {
            let indentation = lines[index].prefix { $0 == " " || $0 == "\t" }
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            lines[index] = "\(indentation)\(key): \(value)"
            return lines.joined(separator: "\n")
        }

        lines.append("\(key): \(value)")
        return lines.joined(separator: "\n")
    }

    static func parseParticipants(from yaml: String) -> [String] {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inParticipants = false
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("attendees:") {
                return parseInlineList(String(trimmed.dropFirst("attendees:".count)))
            }
            if trimmed.hasPrefix("participants:") {
                inParticipants = true
                continue
            }
            if inParticipants {
                if trimmed.hasPrefix("- ") {
                    result.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                } else {
                    break
                }
            }
        }
        return result
    }

    private static func parseInlineList(_ raw: String) -> [String] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner: Substring
        if value.hasPrefix("["), value.hasSuffix("]") {
            inner = value.dropFirst().dropLast()
        } else {
            inner = Substring(value)
        }
        return inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
enum MeetingRecordingDocumentFinalizer {
    static func finalize(
        document: BlockDocument,
        finalSegments: [String],
        fallbackText: String,
        startDate: Date,
        recordedAt: Date
    ) -> [String] {
        let entries = transcriptEntries(finalSegments: finalSegments, fallbackText: fallbackText)
        upsertFrontmatterScalar(
            key: "recorded_at",
            value: MeetingNoteService.isoDateFormatter.string(from: recordedAt),
            in: document
        )
        updateFrontmatterDuration(Int(recordedAt.timeIntervalSince(startDate)), in: document)
        persistTranscriptInDocument(entries: entries, document: document)
        return entries
    }

    static func transcriptEntries(finalSegments: [String], fallbackText: String) -> [String] {
        if !finalSegments.isEmpty {
            return finalSegments
        }
        let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private static func updateFrontmatterDuration(_ seconds: Int, in document: BlockDocument) {
        let minutes = seconds / 60
        upsertFrontmatterScalar(key: "duration_minutes", value: "\(minutes)", in: document)
        upsertFrontmatterScalar(key: "duration", value: "\(minutes)m", in: document)
    }

    private static func upsertFrontmatterScalar(key: String, value: String, in document: BlockDocument) {
        document.yamlFrontmatter = MeetingFrontmatter.upsertingScalar(
            key: key,
            value: value,
            in: document.yamlFrontmatter
        )
    }

    private static func persistTranscriptInDocument(entries: [String], document: BlockDocument) {
        guard !entries.isEmpty else { return }

        let transcriptText = entries.joined(separator: "\n\n")
        let transcriptBlock = Block(type: .codeBlock, text: transcriptText, language: "text")
        if let index = document.blocks.firstIndex(where: {
            $0.type == .toggle && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "Transcript"
        }) {
            document.blocks[index].children = [transcriptBlock]
            document.blocks[index].isExpanded = false
            return
        }

        document.blocks.append(Block(
            type: .toggle,
            text: "Transcript",
            children: [transcriptBlock],
            isExpanded: false
        ))
    }
}
