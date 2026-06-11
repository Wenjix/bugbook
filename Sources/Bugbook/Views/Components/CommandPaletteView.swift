import SwiftUI
import AppKit

enum CommandPaletteDestination {
    case inPlace
    case newWorkspaceTab
}

enum CommandPaletteCreateKind: String, CaseIterable, Identifiable {
    case page
    case mail
    case calendar
    case meetings
    case home

    var id: String { rawValue }

    static var availableCases: [CommandPaletteCreateKind] {
        allCases.filter(\.isAvailableInCurrentMode)
    }

    var isAvailableInCurrentMode: Bool {
        guard let content else { return true }
        return BugbookFeatureGate.allowsPaneContent(content)
    }

    var noun: String {
        switch self {
        case .page: return "Page"
        case .mail: return "Mail"
        case .calendar: return "Calendar"
        case .meetings: return "Meetings"
        case .home: return "Home"
        }
    }

    var newLabel: String {
        switch self {
        case .mail: return "New Mail Tab"
        default: return "New \(noun)"
        }
    }

    var icon: String {
        switch self {
        case .page: return "doc.text"
        case .mail: return "envelope"
        case .calendar: return "calendar"
        case .meetings: return "person.2"
        case .home: return "house"
        }
    }

    var isSingleton: Bool {
        switch self {
        case .mail, .calendar, .meetings, .home:
            return true
        case .page:
            return false
        }
    }

    var content: PaneContent? {
        switch self {
        case .page: return nil
        case .mail: return .mailDocument()
        case .calendar: return .calendarDocument()
        case .meetings: return .meetingsDocument()
        case .home: return .gatewayDocument()
        }
    }

    var searchAliases: [String] {
        switch self {
        case .page: return ["page", "pages", "note", "notes"]
        case .mail: return ["mail", "email", "inbox"]
        case .calendar: return ["calendar", "schedule"]
        case .meetings: return ["meeting", "meetings"]
        case .home: return ["home", "gateway"]
        }
    }

    func matchesToolQuery(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return false }
        return searchAliases.contains { alias in
            alias.hasPrefix(normalizedQuery) || normalizedQuery.hasPrefix(alias)
        }
    }

    func matchesCreateQuery(_ query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        guard !query.isEmpty else { return true }
        return newLabel.localizedStandardContains(query)
            || noun.localizedStandardContains(query)
            || searchAliases.contains { $0.localizedStandardContains(lowercasedQuery) }
    }
}

struct CommandPaletteOpenPaneReference: Identifiable, Equatable {
    let workspaceIndex: Int
    let workspaceID: UUID
    let content: PaneContent
    let title: String
    let icon: String

    var id: String {
        "open:\(workspaceID.uuidString):\(content.id.uuidString)"
    }
}

fileprivate struct CommandPalettePageSearchQuery: Sendable {
    let value: String
    let tokens: [String]
    let bytes: [UInt8]
    let tokenBytes: [[UInt8]]
    let allowsFuzzy: Bool

    init(_ rawValue: String) {
        value = CommandPalettePageEntry.normalizedQuery(rawValue)
        tokens = value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        bytes = Array(value.utf8)
        tokenBytes = tokens.map { Array($0.utf8) }
        allowsFuzzy = tokenBytes.count == 1 && bytes.count <= 8
    }
}

struct CommandPalettePageEntry: Identifiable, Sendable {
    let fileEntry: FileEntry
    let displayName: String
    let relativePath: String
    let modificationDate: Date
    private let searchableNameBytes: [UInt8]
    private let searchablePathBytes: [UInt8]
    fileprivate let indexTokens: [String]

    var id: String { fileEntry.id }

    static func build(
        from entries: [FileEntry],
        workspacePath: String?,
        includeModificationDates: Bool
    ) -> [CommandPalettePageEntry] {
        var result: [CommandPalettePageEntry] = []
        flatten(entries, workspacePath: workspacePath, includeModificationDates: includeModificationDates, into: &result)

        if includeModificationDates {
            result.sort { lhs, rhs in
                lhs.modificationDate > rhs.modificationDate
            }
        }

        return result
    }

    func matches(_ query: String) -> Bool {
        let query = CommandPalettePageSearchQuery(query)
        guard !query.value.isEmpty else { return false }
        return matchScore(query: query) != nil
    }

    static func rankedMatches(
        in entries: [CommandPalettePageEntry],
        query: String,
        limit: Int
    ) -> [CommandPalettePageEntry] {
        let query = CommandPalettePageSearchQuery(query)
        guard !query.value.isEmpty else {
            return Array(entries.prefix(limit))
        }
        return rankedMatches(in: entries, query: query, limit: limit)
    }

    fileprivate static func rankedMatches(
        in entries: [CommandPalettePageEntry],
        query: CommandPalettePageSearchQuery,
        limit: Int
    ) -> [CommandPalettePageEntry] {
        var bestMatches: [(entry: CommandPalettePageEntry, score: Int)] = []
        bestMatches.reserveCapacity(limit + 1)

        for entry in entries {
            guard let score = entry.matchScore(query: query) else { continue }
            let candidate = (entry: entry, score: score)

            if let insertionIndex = bestMatches.firstIndex(where: { isBetter(candidate, than: $0) }) {
                bestMatches.insert(candidate, at: insertionIndex)
            } else if bestMatches.count < limit {
                bestMatches.append(candidate)
            }

            if bestMatches.count > limit {
                bestMatches.removeLast()
            }
        }

        return bestMatches.map(\.entry)
    }

    fileprivate func matchScore(query: CommandPalettePageSearchQuery) -> Int? {
        guard !query.value.isEmpty else { return 0 }
        if let name = Self.matchScore(in: searchableNameBytes, query: query) {
            return name
        }
        return Self.matchScore(in: searchablePathBytes, query: query).map { $0 - 350 }
    }

    static func normalizedQuery(_ value: String) -> String {
        normalize(value)
    }

    private static func flatten(
        _ entries: [FileEntry],
        workspacePath: String?,
        includeModificationDates: Bool,
        into result: inout [CommandPalettePageEntry]
    ) {
        for entry in entries {
            if isPalettePage(entry) {
                result.append(
                    CommandPalettePageEntry(
                        fileEntry: entry,
                        displayName: displayName(for: entry),
                        relativePath: relativePath(for: entry, workspacePath: workspacePath),
                        modificationDate: includeModificationDates ? modificationDate(for: entry) : .distantPast
                    )
                )
            }

            if let children = entry.children {
                flatten(
                    children,
                    workspacePath: workspacePath,
                    includeModificationDates: includeModificationDates,
                    into: &result
                )
            }
        }
    }

    private init(fileEntry: FileEntry, displayName: String, relativePath: String, modificationDate: Date) {
        self.fileEntry = fileEntry
        self.displayName = displayName
        self.relativePath = relativePath
        self.modificationDate = modificationDate
        let normalizedName = Self.normalize(displayName)
        let normalizedPath = Self.normalize(relativePath)
        self.searchableNameBytes = Array(normalizedName.utf8)
        self.searchablePathBytes = Array(normalizedPath.utf8)
        self.indexTokens = Self.indexTokens(in: [normalizedPath])
    }

    private static func isPalettePage(_ entry: FileEntry) -> Bool {
        !entry.isDirectory && entry.kind == .page && entry.path.hasSuffix(".md")
    }

    private static func displayName(for entry: FileEntry) -> String {
        entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name
    }

    private static func relativePath(for entry: FileEntry, workspacePath: String?) -> String {
        guard let workspacePath else { return entry.name }
        let relative = entry.path.replacingOccurrences(of: workspacePath + "/", with: "")
        return relative == entry.path ? entry.name : relative
    }

    private static func modificationDate(for entry: FileEntry) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: entry.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private static func isBetter(
        _ lhs: (entry: CommandPalettePageEntry, score: Int),
        than rhs: (entry: CommandPalettePageEntry, score: Int)
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.entry.modificationDate != rhs.entry.modificationDate {
            return lhs.entry.modificationDate > rhs.entry.modificationDate
        }
        // Preserve cache order for exact ties. Broad queries can produce thousands
        // of equal-score matches, so avoid localized title comparison in this hot path.
        return false
    }

    private static func matchScore(in normalizedValue: [UInt8], query: CommandPalettePageSearchQuery) -> Int? {
        guard !normalizedValue.isEmpty else { return nil }

        if normalizedValue == query.bytes { return 3_000 }
        if hasPrefix(query.bytes, in: normalizedValue) { return 2_500 - normalizedValue.count }
        if let index = firstIndex(of: query.bytes, in: normalizedValue) {
            return 2_000 - index
        }

        if let tokenScore = tokenScore(in: normalizedValue, query: query) {
            return tokenScore
        }

        guard query.allowsFuzzy else { return nil }
        return subsequenceScore(in: normalizedValue, query: query.bytes)
    }

    private static func tokenScore(in normalizedValue: [UInt8], query: CommandPalettePageSearchQuery) -> Int? {
        guard query.tokenBytes.count > 1 else { return nil }

        var score = 1_700
        var searchStart = 0

        for token in query.tokenBytes {
            guard let index = firstIndex(of: token, in: normalizedValue, from: searchStart) else {
                return nil
            }

            score -= index - searchStart

            if index == 0 {
                score += 120
            } else if isTokenBoundary(normalizedValue[index - 1]) {
                score += 60
            }

            searchStart = index + token.count
        }

        return score
    }

    private static func subsequenceScore(in normalizedValue: [UInt8], query: [UInt8]) -> Int? {
        var score = 1_000
        var searchStart = 0
        var previousMatch: Int?

        for byte in query {
            guard let match = firstIndex(of: byte, in: normalizedValue, from: searchStart) else {
                return nil
            }

            if let previousMatch, previousMatch + 1 == match {
                score += 8
            }

            score -= match - searchStart
            previousMatch = match
            searchStart = match + 1
        }

        return score
    }

    private static func hasPrefix(_ prefix: [UInt8], in value: [UInt8]) -> Bool {
        guard !prefix.isEmpty, prefix.count <= value.count else { return false }
        for index in prefix.indices where value[index] != prefix[index] {
            return false
        }
        return true
    }

    private static func firstIndex(of byte: UInt8, in value: [UInt8], from start: Int) -> Int? {
        guard start < value.count else { return nil }
        var index = start
        while index < value.count {
            if value[index] == byte { return index }
            index += 1
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in value: [UInt8], from start: Int = 0) -> Int? {
        guard !needle.isEmpty, needle.count <= value.count else { return nil }
        let limit = value.count - needle.count
        guard start <= limit else { return nil }

        let firstByte = needle[0]
        var index = start
        while index <= limit {
            if value[index] == firstByte {
                var offset = 1
                while offset < needle.count, value[index + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
    }

    private static func isTokenBoundary(_ byte: UInt8) -> Bool {
        byte <= 32 || byte == 45 || byte == 46 || byte == 47 || byte == 95
    }

    private static func indexTokens(in values: [String]) -> [String] {
        var tokens = Set<String>()
        for value in values {
            for token in value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let token = String(token)
                if token != "md" {
                    tokens.insert(token)
                }
            }
        }
        return Array(tokens)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CommandPalettePageSearchIndex: Sendable {
    static let empty = CommandPalettePageSearchIndex(entries: [])

    let entries: [CommandPalettePageEntry]
    private let tokenIndex: [String: [Int]]

    var count: Int { entries.count }

    init(entries: [CommandPalettePageEntry]) {
        self.entries = entries

        var tokenIndex: [String: [Int]] = [:]

        for (entryIndex, entry) in entries.enumerated() {
            for token in entry.indexTokens {
                tokenIndex[token, default: []].append(entryIndex)
            }
        }

        self.tokenIndex = tokenIndex
    }

    func rankedMatches(query rawQuery: String, limit: Int) -> [CommandPalettePageEntry] {
        let query = CommandPalettePageSearchQuery(rawQuery)
        guard !query.value.isEmpty else {
            return Array(entries.prefix(limit))
        }

        if let candidateIndices = candidateIndices(for: query) {
            guard !candidateIndices.isEmpty else { return [] }

            if query.tokens.count == 1, candidateIndices.count > 500 {
                return candidateIndices.prefix(limit).map { entries[$0] }
            }

            let candidates = candidateIndices.map { entries[$0] }
            return CommandPalettePageEntry.rankedMatches(in: candidates, query: query, limit: limit)
        }

        guard query.allowsFuzzy else { return [] }
        return CommandPalettePageEntry.rankedMatches(in: entries, query: query, limit: limit)
    }

    private func candidateIndices(for query: CommandPalettePageSearchQuery) -> [Int]? {
        guard !query.tokens.isEmpty else { return nil }

        if query.tokens.count == 1 {
            let token = query.tokens[0]
            return tokenIndex[token] ?? prefixCandidateIndices(for: token)
        }

        var lists: [[Int]] = []
        lists.reserveCapacity(query.tokens.count)

        for token in query.tokens {
            guard let list = tokenIndex[token] ?? prefixCandidateIndices(for: token) else { return [] }
            lists.append(list)
        }

        return Self.intersection(lists)
    }

    private func prefixCandidateIndices(for token: String) -> [Int]? {
        var seen = Set<Int>()
        var candidates: [Int] = []

        for (indexedToken, indices) in tokenIndex where indexedToken.hasPrefix(token) {
            for index in indices where seen.insert(index).inserted {
                candidates.append(index)
            }
        }

        guard !candidates.isEmpty else { return nil }
        candidates.sort()
        return candidates
    }

    private static func intersection(_ lists: [[Int]]) -> [Int] {
        guard let smallestIndex = lists.indices.min(by: { lists[$0].count < lists[$1].count }) else { return [] }
        var result = lists[smallestIndex]
        let otherSets = lists
            .enumerated()
            .filter { $0.offset != smallestIndex }
            .map(\.element)
            .map(Set.init)

        guard !otherSets.isEmpty else { return result }
        result.removeAll { index in
            otherSets.contains { !$0.contains(index) }
        }
        result.sort()
        return result
    }

}

// MARK: - Result Types

private enum PaletteItem: Identifiable {
    case recent(CommandPalettePageEntry, isOpen: Bool)
    case openPane(CommandPaletteOpenPaneReference)
    case create(PaletteCreateAction)
    case askAI(String)

    var id: String {
        switch self {
        case .recent(let page, _):
            return "recent:\(page.fileEntry.path)"
        case .openPane(let ref):
            return ref.id
        case .create(let action):
            return "create:\(action.kind.id)"
        case .askAI(let query):
            return "ask:\(query)"
        }
    }

    var isAskAI: Bool {
        if case .askAI = self { return true }
        return false
    }
}

private struct PaletteCreateAction {
    let kind: CommandPaletteCreateKind
    let existingReference: CommandPaletteOpenPaneReference?

    var label: String {
        if opensExisting {
            return kind.noun
        }
        return kind.newLabel
    }

    var icon: String {
        if opensExisting {
            return kind.icon
        }
        return "plus.circle"
    }

    var opensExisting: Bool {
        kind.isSingleton && existingReference != nil
    }
}

private struct PaletteSection: Identifiable {
    let title: String
    let items: [PaletteItem]

    var id: String { title }
}

private enum CommandPaletteSubmitVariant {
    case primary
    case flip
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

// MARK: - CommandPaletteView

struct CommandPaletteView: View {
    var appState: AppState
    var workspaceManager: WorkspaceManager

    @Binding var isPresented: Bool

    var onSelectFile: (FileEntry, CommandPaletteDestination) -> Void
    var onCreate: (CommandPaletteCreateKind, CommandPaletteDestination) -> Void
    var onOpenPane: (CommandPaletteOpenPaneReference, CommandPaletteDestination) -> Void
    var onAskAI: (String) -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var pageSearchIndex = CommandPalettePageSearchIndex.empty
    @State private var pageCacheTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        let sections = paletteSections
        let items = sections.flatMap(\.items)
        let indexMap = Dictionary(items.enumerated().map { ($0.element.id, $0.offset) },
                                  uniquingKeysWith: { first, _ in first })

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isNewTabMode ? "plus.square" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(placeholderText, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isSearchFieldFocused)
                    .onSubmit { submitCurrent(.primary) }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if sections.isEmpty {
                            Text("No results")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }

                        ForEach(sections) { section in
                            SectionHeader(title: section.title)
                            ForEach(section.items) { item in
                                let idx = indexMap[item.id] ?? 0
                                paletteRow(item: item, index: idx)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 350)
                .onChange(of: selectedIndex) { _, newIndex in
                    guard newIndex >= 0, newIndex < items.count else { return }
                    proxy.scrollTo(items[newIndex].id, anchor: .center)
                }
            }

            hintRow(selectedItem: selectedItem(in: items))
        }
        .frame(width: 600)
        .popoverSurface(cornerRadius: Radius.xl)
        .background(keyHandler.frame(width: 0, height: 0))
        .onChange(of: searchText) { _, _ in
            resetSelection()
        }
        .onChange(of: appState.fileTree) { _, _ in
            refreshPageCache()
            resetSelection()
        }
        .onChange(of: appState.workspacePath) { _, _ in
            refreshPageCache()
            resetSelection()
        }
        .onAppear {
            // Resign any AppKit first responder (for example a block NSTextView) so the field gets focus.
            NSApp.keyWindow?.makeFirstResponder(nil)
            refreshPageCache()
            resetSelection()
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onDisappear {
            pageCacheTask?.cancel()
            pageCacheTask = nil
        }
    }

    private var isNewTabMode: Bool {
        appState.commandPaletteMode == .newTab
    }

    private var placeholderText: String {
        isNewTabMode ? "Open in new tab…" : "Go to…"
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sections

    private var paletteSections: [PaletteSection] {
        let openReferences = openPaneReferences()
        let tools = openToolItems(openReferences: openReferences)
        let create = createItems(openReferences: openReferences)
        let pages = pageItems
        var sections: [PaletteSection] = []

        if !tools.isEmpty {
            sections.append(PaletteSection(title: "Open Tool", items: tools))
        }

        if !create.isEmpty {
            sections.append(PaletteSection(title: "Create", items: create))
        }

        if !pages.isEmpty {
            sections.append(PaletteSection(title: "Pages", items: pages))
        }

        if shouldShowAskAI(tools: tools, pages: pages) {
            sections.append(PaletteSection(title: "Ask AI", items: [.askAI(query)]))
        }

        return sections
    }

    private var pageItems: [PaletteItem] {
        pageSearchIndex
            .rankedMatches(query: query, limit: 10)
            .map { .recent($0, isOpen: isOpenPage($0.fileEntry)) }
    }

    private func openPaneItems(openReferences: [CommandPaletteOpenPaneReference]) -> [PaletteItem] {
        guard !query.isEmpty else { return [] }
        return openReferences
            .filter { $0.title.localizedStandardContains(query) }
            .prefix(5)
            .map { .openPane($0) }
    }

    private func openToolItems(openReferences: [CommandPaletteOpenPaneReference]) -> [PaletteItem] {
        guard !query.isEmpty else { return [] }

        let toolCreateItems = CommandPaletteCreateKind.availableCases
            .filter { $0.matchesToolQuery(query) }
            .map { kind -> PaletteItem in
                let existing = kind.isSingleton ? existingSingletonReference(for: kind, in: openReferences) : nil
                return .create(PaletteCreateAction(kind: kind, existingReference: existing))
            }

        return toolCreateItems + openPaneItems(openReferences: openReferences)
    }

    private func createItems(openReferences: [CommandPaletteOpenPaneReference]) -> [PaletteItem] {
        let promotedKinds = Set(
            CommandPaletteCreateKind.availableCases
                .filter { $0.matchesToolQuery(query) }
                .map(\.id)
        )

        return CommandPaletteCreateKind.availableCases.compactMap { kind -> PaletteItem? in
            if promotedKinds.contains(kind.id) {
                return nil
            }
            let existing = kind.isSingleton ? existingSingletonReference(for: kind, in: openReferences) : nil
            let action = PaletteCreateAction(kind: kind, existingReference: existing)
            guard kind.matchesCreateQuery(query) || action.label.localizedStandardContains(query) else {
                return nil
            }
            return .create(action)
        }
    }

    private func shouldShowAskAI(tools: [PaletteItem], pages: [PaletteItem]) -> Bool {
        guard BugbookFeatureGate.allowsNotification(.askAI) else { return false }
        guard !query.isEmpty else { return false }
        return !tools.isEmpty || !pages.isEmpty || query.count >= 3
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func paletteRow(item: PaletteItem, index: Int) -> some View {
        Button {
            selectedIndex = index
            executeItem(item, variant: .primary)
        } label: {
            HStack(spacing: 9) {
                switch item {
                case .recent(let page, let isOpen):
                    fileIcon(for: page.fileEntry)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(page.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text(page.relativePath)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isOpen {
                        openBadge
                    }

                case .openPane(let ref):
                    Image(systemName: ref.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ref.title)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text("Workspace \(ref.workspaceIndex + 1)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                case .create(let action):
                    Image(systemName: action.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(action.opensExisting ? .secondary : Color.accentColor)
                        .frame(width: 18)
                    Text(action.label)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()

                case .askAI(let prompt):
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("Ask AI")
                        .font(.system(size: 15, weight: .medium))
                    Text(prompt)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(.rect(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var openBadge: some View {
        Text("open")
            .font(.system(size: Typography.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 3))
    }

    private func hintRow(selectedItem: PaletteItem?) -> some View {
        HStack(spacing: 6) {
            Text("↵ \(primaryActionLabel(for: selectedItem))")
            Text("·")
                .foregroundStyle(.quaternary)
            Text("⌘↵ \(flipActionLabel(for: selectedItem))")
        }
        .font(.system(size: Typography.caption, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Data

    private func refreshPageCache() {
        let fileTree = appState.fileTree
        let workspacePath = appState.workspacePath
        let entries = CommandPalettePageEntry.build(
            from: fileTree,
            workspacePath: workspacePath,
            includeModificationDates: false
        )
        pageSearchIndex = CommandPalettePageSearchIndex(entries: entries)

        pageCacheTask?.cancel()
        pageCacheTask = Task.detached(priority: .utility) {
            let datedEntries = CommandPalettePageEntry.build(
                from: fileTree,
                workspacePath: workspacePath,
                includeModificationDates: true
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pageSearchIndex = CommandPalettePageSearchIndex(entries: datedEntries)
            }
        }
    }

    private func openPaneReferences() -> [CommandPaletteOpenPaneReference] {
        let activeIndex = workspaceManager.activeWorkspaceIndex
        var refs: [(rank: Int, ref: CommandPaletteOpenPaneReference)] = []

        for (workspaceIndex, workspace) in workspaceManager.workspaces.enumerated() {
            let content = workspace.content
            guard BugbookFeatureGate.allowsPaneContent(content) else { continue }
            guard let descriptor = openPaneDescriptor(for: content) else { continue }

            let rank = workspaceIndex == activeIndex ? 0 : 10_000 + workspaceIndex * 100
            refs.append((
                rank,
                CommandPaletteOpenPaneReference(
                    workspaceIndex: workspaceIndex,
                    workspaceID: workspace.id,
                    content: content,
                    title: descriptor.title,
                    icon: descriptor.icon
                )
            ))
        }

        return refs
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.ref.title.localizedStandardCompare(rhs.ref.title) == .orderedAscending
            }
            .map(\.ref)
    }

    private func openPaneDescriptor(for content: PaneContent) -> (title: String, icon: String)? {
        switch content {
        case .document(let file):
            if file.isMail { return ("Mail", "envelope") }
            if file.isCalendar { return ("Calendar", "calendar") }
            if file.isMeetings { return ("Meetings", "person.2") }
            if file.isGateway { return ("Home", "house") }
            return nil
        }
    }

    private func existingSingletonReference(
        for kind: CommandPaletteCreateKind,
        in openReferences: [CommandPaletteOpenPaneReference]
    ) -> CommandPaletteOpenPaneReference? {
        openReferences.first { ref in
            switch (kind, ref.content) {
            case (.mail, .document(let file)):
                return file.isMail
            case (.calendar, .document(let file)):
                return file.isCalendar
            case (.meetings, .document(let file)):
                return file.isMeetings
            case (.home, .document(let file)):
                return file.isGateway
            default:
                return false
            }
        }
    }

    private func isOpenPage(_ entry: FileEntry) -> Bool {
        workspaceManager.allDocuments().contains { _, file in
            file.kind == .page && file.path == entry.path
        }
    }

    // MARK: - Selection

    private func resetSelection() {
        let items = paletteSections.flatMap(\.items)
        selectedIndex = items.firstIndex { !$0.isAskAI } ?? -1
    }

    private func selectedItem(in items: [PaletteItem]) -> PaletteItem? {
        guard selectedIndex >= 0, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    private func submitCurrent(_ variant: CommandPaletteSubmitVariant) {
        let items = paletteSections.flatMap(\.items)
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        executeItem(items[selectedIndex], variant: variant)
    }

    private func executeItem(_ item: PaletteItem, variant: CommandPaletteSubmitVariant) {
        switch item {
        case .recent(let page, _):
            onSelectFile(page.fileEntry, destination(for: variant))
        case .openPane(let ref):
            onOpenPane(ref, openPaneDestination(for: variant))
        case .create(let action):
            if let existing = action.existingReference {
                onOpenPane(existing, .inPlace)
            } else {
                onCreate(action.kind, destination(for: variant))
            }
        case .askAI(let prompt):
            onAskAI(prompt)
        }

        isPresented = false
    }

    private func destination(for variant: CommandPaletteSubmitVariant) -> CommandPaletteDestination {
        switch variant {
        case .primary:
            return isNewTabMode ? .newWorkspaceTab : .inPlace
        case .flip:
            return isNewTabMode ? .inPlace : .newWorkspaceTab
        }
    }

    private func openPaneDestination(for variant: CommandPaletteSubmitVariant) -> CommandPaletteDestination {
        .inPlace
    }

    private func primaryActionLabel(for item: PaletteItem?) -> String {
        guard let item else { return isNewTabMode ? "Open in New Tab" : "Navigate" }
        switch item {
        case .askAI:
            return "Ask AI"
        case .openPane:
            return "Focus"
        case .create(let action) where action.existingReference != nil:
            return "Focus"
        default:
            return isNewTabMode ? "Open in New Tab" : "Navigate"
        }
    }

    private func flipActionLabel(for item: PaletteItem?) -> String {
        guard let item else { return isNewTabMode ? "Navigate" : "Open in New Tab" }
        switch item {
        case .askAI:
            return "Ask AI"
        case .openPane:
            return "Focus"
        case .create(let action) where action.existingReference != nil:
            return "Focus"
        default:
            return isNewTabMode ? "Navigate" : "Open in New Tab"
        }
    }

    // MARK: - Keyboard

    private var keyHandler: some View {
        CommandPaletteKeyListener(
            onUp: {
                let count = paletteSections.flatMap(\.items).count
                guard count > 0, selectedIndex > 0 else { return }
                selectedIndex -= 1
            },
            onDown: {
                let count = paletteSections.flatMap(\.items).count
                guard count > 0 else { return }
                selectedIndex = min(count - 1, max(0, selectedIndex + 1))
            },
            onEnter: { flags in
                let modifiers = flags.intersection(.deviceIndependentFlagsMask)
                let hasCommand = modifiers.contains(.command)
                let hasOption = modifiers.contains(.option)
                let hasShift = modifiers.contains(.shift)
                let hasControl = modifiers.contains(.control)
                let commandOnly = hasCommand && !hasOption && !hasShift && !hasControl

                if commandOnly {
                    submitCurrent(.flip)
                } else {
                    submitCurrent(.primary)
                }
            },
            onEscape: {
                isPresented = false
            }
        )
    }

    // MARK: - Helpers

    private func displayName(for entry: FileEntry) -> String {
        entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name
    }

    private func relativePath(for entry: FileEntry) -> String {
        guard let workspace = appState.workspacePath else { return entry.name }
        let relative = entry.path.replacingOccurrences(of: workspace + "/", with: "")
        return relative == entry.path ? entry.name : relative
    }

    private func fileIcon(for entry: FileEntry) -> some View {
        PageIconView(
            icon: entry.icon,
            imageSize: 18,
            symbolFont: .system(size: 13),
            emojiFont: .system(size: 14),
            cornerRadius: 0
        ) {
            defaultFileIcon(for: entry)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func defaultFileIcon(for entry: FileEntry) -> some View {
        Image(systemName: entry.isDatabase ? "tablecells" : "doc.text")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Key Listener

private struct CommandPaletteKeyListener: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: (NSEvent.ModifierFlags) -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(
            onUp: onUp,
            onDown: onDown,
            onEnter: onEnter,
            onEscape: onEscape
        )
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            onUp: onUp,
            onDown: onDown,
            onEnter: onEnter,
            onEscape: onEscape
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var monitor: Any?
        private var onUp: (() -> Void)?
        private var onDown: (() -> Void)?
        private var onEnter: ((NSEvent.ModifierFlags) -> Void)?
        private var onEscape: (() -> Void)?

        func install(
            onUp: @escaping () -> Void,
            onDown: @escaping () -> Void,
            onEnter: @escaping (NSEvent.ModifierFlags) -> Void,
            onEscape: @escaping () -> Void
        ) {
            update(onUp: onUp, onDown: onDown, onEnter: onEnter, onEscape: onEscape)
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 126:
                    self.onUp?()
                    return nil
                case 125:
                    self.onDown?()
                    return nil
                case 36:
                    self.onEnter?(event.modifierFlags)
                    return nil
                case 53:
                    self.onEscape?()
                    return nil
                default:
                    return event
                }
            }
        }

        func update(
            onUp: @escaping () -> Void,
            onDown: @escaping () -> Void,
            onEnter: @escaping (NSEvent.ModifierFlags) -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.onUp = onUp
            self.onDown = onDown
            self.onEnter = onEnter
            self.onEscape = onEscape
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
