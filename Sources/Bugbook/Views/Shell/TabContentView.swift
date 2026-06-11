import AppKit
import SwiftUI

private enum TabFindMatch: Equatable {
    case block(BlockFindSelection)
    case databaseRow(String)
}

/// Renders the active tab's document: optional find-in-page bar + content.
struct TabContentView: View {
    let content: PaneContent
    let documentContentBuilder: (OpenFile) -> AnyView
    var blockDocumentLookup: ((UUID) -> BlockDocument?)? = nil

    @Environment(\.editorTypingFocusFullBleed) private var editorTypingFocusFullBleed

    // Find-in-page state
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrentIndex: Int?
    @State private var findMatchCache: [TabFindMatch] = []
    @State private var findAutoExpandedToggleIds: Set<UUID> = []
    @State private var databaseFindState: DatabaseViewState?
    @FocusState private var findFieldFocused: Bool

    private var activeBlockDocument: BlockDocument? {
        blockDocumentLookup?(content.id)
    }

    private var activeDatabaseFindState: DatabaseViewState? {
        guard case .document(let file) = content,
              file.isDatabase else { return nil }
        return databaseFindState
    }

    private var activeDatabaseFindContextRevision: UInt64 {
        activeDatabaseFindState?.findContextRevision ?? 0
    }

    private func recomputeFindMatches() {
        guard !findQuery.isEmpty else {
            findMatchCache = []
            activeDatabaseFindState?.clearFindHighlights()
            return
        }

        if let doc = activeBlockDocument {
            recomputeBlockFindMatches(in: doc)
            activeDatabaseFindState?.clearFindHighlights()
            return
        }

        if let databaseState = activeDatabaseFindState {
            let rowIds = databaseState.matches(for: findQuery)
            let results = rowIds.map(TabFindMatch.databaseRow)
            findMatchCache = results
            if let findCurrentIndex, findCurrentIndex < results.count {
                selectFindMatch(at: findCurrentIndex, in: results, shouldScroll: false)
            } else {
                databaseState.updateFindHighlights(
                    matchingRowIds: rowIds,
                    selectedRowId: nil,
                    shouldScroll: false
                )
            }
            return
        }

        findMatchCache = []
    }

    private func recomputeBlockFindMatches(in doc: BlockDocument) {
        var results: [BlockFindSelection] = []
        func searchBlocks(_ blocks: [Block]) {
            for block in blocks {
                let visibleText = AttributedStringConverter.plainText(from: block.text) as NSString
                var searchRange = NSRange(location: 0, length: visibleText.length)
                while searchRange.location < visibleText.length {
                    let range = visibleText.range(
                        of: findQuery,
                        options: [.caseInsensitive, .diacriticInsensitive],
                        range: searchRange
                    )
                    guard range.location != NSNotFound else { break }
                    results.append(BlockFindSelection(blockId: block.id, range: range))
                    let nextLocation = range.location + max(range.length, 1)
                    guard nextLocation < visibleText.length else { break }
                    searchRange = NSRange(location: nextLocation, length: visibleText.length - nextLocation)
                }
                if !block.children.isEmpty {
                    searchBlocks(block.children)
                }
            }
        }
        searchBlocks(doc.blocks)
        findMatchCache = results.map(TabFindMatch.block)
        if let findCurrentIndex, findCurrentIndex < results.count {
            selectFindMatch(
                at: findCurrentIndex,
                in: results.map(TabFindMatch.block),
                shouldScroll: false
            )
        } else {
            doc.findSelectedMatch = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showFindBar {
                editorFindBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(editorTypingFocusFullBleed ? Color.fallbackEditorBg : Container.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: editorTypingFocusFullBleed ? 0 : Container.cardRadius))
        .onReceive(NotificationCenter.default.publisher(for: .findInPane)) { _ in
            guard supportsInlineFindBar else { return }
            if showFindBar {
                focusFindField()
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showFindBar = true
                }
                focusFindField()
            }
        }
        .onChange(of: findQuery) { _, newValue in
            activeBlockDocument?.findHighlightQuery = newValue
            activeBlockDocument?.findSelectedMatch = nil
            activeDatabaseFindState?.clearFindHighlights()
            findCurrentIndex = nil
            recomputeFindMatches()
        }
        .onChange(of: activeBlockDocument?.contentVersion ?? 0) { _, _ in
            guard showFindBar else { return }
            recomputeFindMatches()
        }
        .onPreferenceChange(DatabaseViewStatePreferenceKey.self) { newValue in
            databaseFindState = newValue.state
            guard showFindBar else { return }
            recomputeFindMatches()
        }
        .onChange(of: activeDatabaseFindContextRevision) { _, _ in
            guard showFindBar else { return }
            recomputeFindMatches()
        }
    }

    private var supportsInlineFindBar: Bool {
        guard case .document(let file) = content else { return false }
        return isPlainDocumentPage(file)
    }

    private func isPlainDocumentPage(_ file: OpenFile) -> Bool {
        !file.isEmptyTab
            && !file.isMail
            && !file.isCalendar
            && !file.isMeetings
            && !file.isGateway
            && !file.isChat
            && !file.isGraphView
    }

    @ViewBuilder
    private var tabContent: some View {
        switch content {
        case .document(let file):
            documentContentBuilder(file)
        }
    }

    private var editorFindBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find on page", text: $findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($findFieldFocused)
                .onSubmit {
                    let isReverse = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                    advanceFind(forward: !isReverse)
                }
                .onExitCommand {
                    closeFindBar()
                }

            if !findQuery.isEmpty {
                Text(findMatchStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                advanceFind(forward: false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(findMatchCache.isEmpty)

            Button {
                advanceFind(forward: true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(findMatchCache.isEmpty)

            Button {
                closeFindBar()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.fallbackTabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.fallbackChromeBorder)
                .frame(height: 1)
        }
    }

    private var findMatchStatus: String {
        guard !findMatchCache.isEmpty else { return "No results" }
        guard let findCurrentIndex else { return "\(findMatchCache.count) results" }
        return "\(findCurrentIndex + 1) of \(findMatchCache.count)"
    }

    private func advanceFind(forward: Bool) {
        let matches = findMatchCache
        guard !matches.isEmpty else { return }
        let nextIndex: Int
        if let findCurrentIndex {
            if forward {
                nextIndex = (findCurrentIndex + 1) % matches.count
            } else {
                nextIndex = (findCurrentIndex - 1 + matches.count) % matches.count
            }
        } else {
            nextIndex = forward ? 0 : (matches.count - 1)
        }
        selectFindMatch(at: nextIndex, in: matches)
    }

    private func selectFindMatch(
        at index: Int,
        in matches: [TabFindMatch]? = nil,
        shouldScroll: Bool = true
    ) {
        let resolvedMatches = matches ?? findMatchCache
        guard resolvedMatches.indices.contains(index) else { return }
        let match = resolvedMatches[index]
        findCurrentIndex = index

        switch match {
        case .block(let selection):
            guard let doc = activeBlockDocument else { return }
            findAutoExpandedToggleIds.formUnion(doc.expandAncestorToggles(of: selection.blockId))
            doc.findSelectedMatch = selection
            activeDatabaseFindState?.clearFindHighlights()
            if shouldScroll {
                doc.scrollToBlockId = selection.blockId
            }
        case .databaseRow(let rowId):
            activeBlockDocument?.findSelectedMatch = nil
            activeDatabaseFindState?.updateFindHighlights(
                matchingRowIds: databaseRowIds(in: resolvedMatches),
                selectedRowId: rowId,
                shouldScroll: shouldScroll
            )
        }
    }

    private func databaseRowIds(in matches: [TabFindMatch]) -> [String] {
        matches.compactMap {
            guard case .databaseRow(let rowId) = $0 else { return nil }
            return rowId
        }
    }

    private func closeFindBar() {
        let doc = activeBlockDocument
        let databaseState = activeDatabaseFindState
        let autoExpandedToggleIds = findAutoExpandedToggleIds
        withAnimation(.easeInOut(duration: 0.15)) {
            showFindBar = false
        }
        doc?.findHighlightQuery = ""
        doc?.findSelectedMatch = nil
        databaseState?.clearFindHighlights()
        for toggleId in autoExpandedToggleIds {
            doc?.setToggleExpanded(id: toggleId, to: false)
        }
        findQuery = ""
        findCurrentIndex = nil
        findMatchCache = []
        findAutoExpandedToggleIds = []
        findFieldFocused = false
    }

    private func focusFindField() {
        DispatchQueue.main.async {
            findFieldFocused = true
        }
    }
}
