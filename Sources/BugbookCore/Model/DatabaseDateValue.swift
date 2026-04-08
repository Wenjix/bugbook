import Foundation

public enum DatabaseDateFormat: String, Codable, CaseIterable, Sendable {
    case full
    case long
    case medium
    case short

    public var displayName: String {
        switch self {
        case .full: return "Full date"
        case .long: return "Long"
        case .medium: return "Medium"
        case .short: return "Short"
        }
    }

    fileprivate var formatterStyle: DateFormatter.Style {
        switch self {
        case .full: return .full
        case .long: return .long
        case .medium: return .medium
        case .short: return .short
        }
    }
}

public struct DatabaseDateValue: Equatable, Codable, Sendable {
    public var start: String
    public var end: String?
    public var includeTime: Bool
    public var dateFormat: DatabaseDateFormat

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case includeTime = "include_time"
        case dateFormat = "date_format"
    }

    public init(
        start: String,
        end: String? = nil,
        includeTime: Bool? = nil,
        dateFormat: DatabaseDateFormat = .long
    ) {
        let resolvedIncludeTime = includeTime ?? Self.looksLikeDateTime(start) || (end.map(Self.looksLikeDateTime) ?? false)
        self.start = Self.normalizedString(from: start, includeTime: resolvedIncludeTime) ?? start
        if let end, !end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.end = Self.normalizedString(from: end, includeTime: resolvedIncludeTime) ?? end
        } else {
            self.end = nil
        }
        self.includeTime = resolvedIncludeTime
        self.dateFormat = dateFormat
        self = self.normalized()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let start = try container.decode(String.self, forKey: .start)
        let end = try container.decodeIfPresent(String.self, forKey: .end)
        let includeTime = try container.decodeIfPresent(Bool.self, forKey: .includeTime)
        let dateFormat = try container.decodeIfPresent(DatabaseDateFormat.self, forKey: .dateFormat) ?? .long
        self.init(start: start, end: end, includeTime: includeTime, dateFormat: dateFormat)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encode(includeTime, forKey: .includeTime)
        try container.encode(dateFormat, forKey: .dateFormat)
    }

    private static nonisolated(unsafe) let sharedJSONDecoder = JSONDecoder()

    public static func decode(from raw: String) -> DatabaseDateValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let decoded = try? sharedJSONDecoder.decode(DatabaseDateValue.self, from: data) {
            return decoded.normalized()
        }

        // Fast path: if the string is already in canonical format (yyyy-MM-dd or yyyy-MM-ddTHH:mm),
        // skip the full init → normalizedString → date → canonicalString round-trip.
        if isCanonicalDate(trimmed) {
            let hasTime = trimmed.count > 10 && (trimmed[trimmed.index(trimmed.startIndex, offsetBy: 10)] == "T")
            return DatabaseDateValue(
                canonicalStart: trimmed,
                end: nil,
                includeTime: hasTime,
                dateFormat: .long
            )
        }

        return DatabaseDateValue(start: trimmed)
    }

    /// Private fast-path init that skips normalization for already-canonical strings.
    private init(canonicalStart: String, end: String?, includeTime: Bool, dateFormat: DatabaseDateFormat) {
        self.start = canonicalStart
        self.end = end
        self.includeTime = includeTime
        self.dateFormat = dateFormat
    }

    /// Check if a string matches yyyy-MM-dd or yyyy-MM-ddTHH:mm format exactly.
    /// Uses direct UTF8View indexing to avoid heap-allocating a byte array.
    @inline(__always)
    private static func isCanonicalDate(_ s: String) -> Bool {
        let u = s.utf8
        let count = u.count
        guard count == 10 || count == 16 else { return false }
        // All characters must be ASCII (single-byte UTF-8)
        guard s.count == count else { return false }

        @inline(__always) func byte(_ offset: Int) -> UInt8 {
            u[u.index(u.startIndex, offsetBy: offset)]
        }
        @inline(__always) func isDigit(_ offset: Int) -> Bool {
            let b = byte(offset); return b >= 0x30 && b <= 0x39
        }

        // yyyy-MM-dd
        guard byte(4) == 0x2D, byte(7) == 0x2D else { return false }
        guard isDigit(0), isDigit(1), isDigit(2), isDigit(3),
              isDigit(5), isDigit(6), isDigit(8), isDigit(9) else { return false }

        if count == 16 {
            // yyyy-MM-ddTHH:mm
            guard byte(10) == 0x54, byte(13) == 0x3A else { return false }
            guard isDigit(11), isDigit(12), isDigit(14), isDigit(15) else { return false }
        }
        return true
    }

    public var rawValue: String {
        let normalized = normalized()
        if normalized.end == nil && normalized.dateFormat == .long {
            return normalized.start
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(normalized),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return normalized.start
    }

    public var sortKey: String {
        // Fast path: if start is already canonical, skip normalization
        if Self.isCanonicalDate(start) { return start }
        return normalized().start
    }

    public var startDayKey: String {
        Self.dayKey(from: start)
    }

    public var endDayKey: String? {
        end.map(Self.dayKey(from:))
    }

    public var startDate: Date? {
        Self.date(fromStoredString: start, includeTime: includeTime)
    }

    public var endDate: Date? {
        guard let end else { return nil }
        return Self.date(fromStoredString: end, includeTime: includeTime)
    }

    public func displayText(locale: Locale = .current, calendar: Calendar = .current, compact: Bool = false) -> String {
        guard let startDate else {
            return start
        }

        let effectiveFormat: DatabaseDateFormat
        if compact {
            switch dateFormat {
            case .full, .long: effectiveFormat = .medium
            case .medium, .short: effectiveFormat = dateFormat
            }
        } else {
            effectiveFormat = dateFormat
        }

        let formatter = Self.displayFormatter(
            style: effectiveFormat.formatterStyle,
            includeTime: includeTime,
            locale: locale,
            timeZone: calendar.timeZone
        )
        let startText = formatter.string(from: startDate)

        guard let endDate else {
            return startText
        }

        let endText = formatter.string(from: endDate)
        return "\(startText) → \(endText)"
    }

    private static let displayFormatterCache = NSCache<NSString, DateFormatter>()

    private static func displayFormatter(
        style: DateFormatter.Style,
        includeTime: Bool,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let key = "\(style.rawValue)-\(includeTime)-\(locale.identifier)-\(timeZone.identifier)" as NSString
        if let cached = displayFormatterCache.object(forKey: key) {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = style
        formatter.timeStyle = includeTime ? .short : .none
        displayFormatterCache.setObject(formatter, forKey: key)
        return formatter
    }

    public func contains(dayString: String, calendar: Calendar = .current) -> Bool {
        guard let targetDay = Self.date(fromStoredString: dayString, includeTime: false).map(calendar.startOfDay(for:)) else {
            return false
        }
        guard let startDay = startDate.map(calendar.startOfDay(for:)) else {
            return false
        }
        let endDay = endDate.map(calendar.startOfDay(for:)) ?? startDay
        return targetDay >= startDay && targetDay <= endDay
    }

    public func settingStart(_ date: Date, calendar: Calendar = .current) -> DatabaseDateValue {
        var copy = self
        copy.start = Self.canonicalString(from: date, includeTime: includeTime, calendar: calendar)
        return copy.normalized()
    }

    public func settingEnd(_ date: Date?, calendar: Calendar = .current) -> DatabaseDateValue {
        var copy = self
        copy.end = date.map { Self.canonicalString(from: $0, includeTime: includeTime, calendar: calendar) }
        return copy.normalized()
    }

    public func togglingEndDate(_ enabled: Bool, calendar: Calendar = .current) -> DatabaseDateValue {
        guard enabled else {
            return DatabaseDateValue(start: start, end: nil, includeTime: includeTime, dateFormat: dateFormat)
        }

        return DatabaseDateValue(
            start: start,
            end: end ?? start,
            includeTime: includeTime,
            dateFormat: dateFormat
        )
    }

    public func togglingIncludeTime(_ enabled: Bool, calendar: Calendar = .current, reference: Date = Date()) -> DatabaseDateValue {
        guard enabled != includeTime else { return self }

        var copy = self
        copy.includeTime = enabled

        if enabled {
            copy.start = Self.applyingTime(from: reference, toDayString: startDayKey, calendar: calendar)
            if let endDayKey = endDayKey {
                copy.end = Self.applyingTime(from: reference, toDayString: endDayKey, calendar: calendar)
            }
        } else {
            copy.start = startDayKey
            copy.end = endDayKey
        }

        return copy.normalized()
    }

    public func settingDateFormat(_ format: DatabaseDateFormat) -> DatabaseDateValue {
        var copy = self
        copy.dateFormat = format
        return copy.normalized()
    }

    public func movingStartDay(to dayString: String, calendar: Calendar = .current) -> DatabaseDateValue {
        guard let targetDay = Self.date(fromStoredString: dayString, includeTime: false) else {
            return self
        }

        let currentStart = startDate ?? targetDay
        let newStart: Date
        if includeTime {
            let time = calendar.dateComponents([.hour, .minute], from: currentStart)
            newStart = calendar.date(
                bySettingHour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0,
                of: targetDay
            ) ?? targetDay
        } else {
            newStart = targetDay
        }

        var copy = settingStart(newStart, calendar: calendar)
        if let currentEnd = endDate {
            copy = copy.settingEnd(newStart.addingTimeInterval(currentEnd.timeIntervalSince(currentStart)), calendar: calendar)
        }
        return copy.normalized()
    }

    public func dateForPicker(_ usesEndDate: Bool) -> Date {
        if usesEndDate, let endDate {
            return endDate
        }
        return startDate ?? Date()
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    public func timeLabel(usesEndDate: Bool = false, locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard includeTime else { return "Set time" }
        let formatter = Self.shortTimeFormatter
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: dateForPicker(usesEndDate))
    }

    public static func canonicalDayString(from date: Date, calendar: Calendar = .current) -> String {
        canonicalString(from: date, includeTime: false, calendar: calendar)
    }

    public static func canonicalDateTimeString(from date: Date, calendar: Calendar = .current) -> String {
        canonicalString(from: date, includeTime: true, calendar: calendar)
    }

    private func normalized() -> DatabaseDateValue {
        var copy = self
        copy.start = Self.normalizedString(from: copy.start, includeTime: copy.includeTime) ?? copy.start
        if let end = copy.end {
            copy.end = Self.normalizedString(from: end, includeTime: copy.includeTime) ?? end
        }

        if let endDate = copy.endDate, let startDate = copy.startDate, endDate < startDate {
            copy.end = copy.start
        }

        if copy.end?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            copy.end = nil
        }

        return copy
    }

    private static let posixDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let posixDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private static let posixDateTimeSpaceFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func canonicalString(from date: Date, includeTime: Bool, calendar: Calendar) -> String {
        let formatter = includeTime ? posixDateTimeFormatter : posixDayFormatter
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }

    private static func normalizedString(from raw: String, includeTime: Bool) -> String? {
        guard let parsed = date(fromStoredString: raw, includeTime: includeTime) else {
            return nil
        }
        return canonicalString(from: parsed, includeTime: includeTime, calendar: .current)
    }

    private static func date(fromStoredString raw: String, includeTime: Bool) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if includeTime {
            if let date = posixDateTimeFormatter.date(from: trimmed) {
                return date
            }
            if let date = posixDateTimeSpaceFormatter.date(from: trimmed) {
                return date
            }
        }

        return posixDayFormatter.date(from: String(trimmed.prefix(10)))
    }

    private static func looksLikeDateTime(_ raw: String) -> Bool {
        raw.contains("T") || raw.contains(":")
    }

    private static func dayKey(from raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
    }

    private static func applyingTime(from reference: Date, toDayString dayString: String, calendar: Calendar) -> String {
        guard let day = date(fromStoredString: dayString, includeTime: false) else {
            return dayString
        }
        let components = calendar.dateComponents([.hour, .minute], from: reference)
        let merged = calendar.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
        return canonicalString(from: merged, includeTime: true, calendar: calendar)
    }
}
