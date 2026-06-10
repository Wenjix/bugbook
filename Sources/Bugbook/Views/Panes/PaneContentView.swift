import AppKit
import SwiftUI

private enum PaneFindMatch: Equatable {
    case block(BlockFindSelection)
    case databaseRow(String)
}

/// Renders a single pane leaf: chrome bar (30px) + content below.
///
/// Focus state is observed by PaneChromeBar and PaneFocusOverlay internally —
/// the document content is NOT re-rendered when focus changes.
struct PaneContentView: View {
    let leaf: PaneNode.Leaf
    let workspaceManager: WorkspaceManager
    let showFocusBorder: Bool
    var fileTree: [FileEntry] = []

    let documentContentBuilder: (PaneNode.Leaf, OpenFile) -> AnyView
    var breadcrumbProvider: ((OpenFile) -> [BreadcrumbItem])? = nil
    var onBreadcrumbNavigate: ((BreadcrumbItem, UUID) -> Void)? = nil
    var blockDocumentLookup: ((UUID) -> BlockDocument?)? = nil
    let paneActions: PaneActions

    @Environment(\.editorTypingFocusActive) private var editorTypingFocusActive
    @Environment(\.editorTypingFocusFullBleed) private var editorTypingFocusFullBleed
    @State private var isDropTarget = false

    // Find-in-page state (per-pane)
    @State private var showFindBar = false
    @State private var findQuery = ""
    @State private var findCurrentIndex: Int?
    @State private var findMatchCache: [PaneFindMatch] = []
    @State private var findAutoExpandedToggleIds: Set<UUID> = []
    @State private var databaseFindState: DatabaseViewState?
    @FocusState private var findFieldFocused: Bool

    private var isFocusedPane: Bool {
        workspaceManager.activeWorkspace?.focusedPaneId == leaf.id
    }

    private var activeBlockDocument: BlockDocument? {
        guard case .document = leaf.content else { return nil }
        return blockDocumentLookup?(leaf.activeTabID)
    }

    private var activeDatabaseFindState: DatabaseViewState? {
        guard case .document(let file) = leaf.content,
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
            let results = rowIds.map(PaneFindMatch.databaseRow)
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
        findMatchCache = results.map(PaneFindMatch.block)
        if let findCurrentIndex, findCurrentIndex < results.count {
            selectFindMatch(
                at: findCurrentIndex,
                in: results.map(PaneFindMatch.block),
                shouldScroll: false
            )
        } else {
            doc.findSelectedMatch = nil
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if shouldShowChromeBar {
                    PaneChromeBar(
                        leaf: leaf,
                        workspaceManager: workspaceManager,
                        isOnlyPane: !showFocusBorder,
                        fileTree: fileTree,
                        breadcrumbs: chromeBreadcrumbs,
                        onBreadcrumbNavigate: onBreadcrumbNavigate,
                        paneActions: paneActions
                    )
                }

                if showFindBar {
                    editorFindBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                contentForLeaf
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PaneFocusOverlay(
                paneId: leaf.id,
                workspaceManager: workspaceManager
            )

            // Drop target highlight for pane swap
            if isDropTarget {
                RoundedRectangle(cornerRadius: Container.cardRadius)
                    .strokeBorder(Color.fallbackAccent.opacity(Opacity.strong), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .background(editorTypingFocusFullBleed ? Color.fallbackEditorBg : Container.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: editorTypingFocusFullBleed ? 0 : Container.cardRadius))
        .onDrop(of: [.text], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let idString = item as? String,
                      let sourceId = UUID(uuidString: idString),
                      sourceId != leaf.id else { return }
                DispatchQueue.main.async {
                    workspaceManager.swapPaneContents(paneA: sourceId, paneB: leaf.id)
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInPane)) { _ in
            guard isFocusedPane, supportsInlineFindBar else { return }
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
        .contextMenu {
            Menu("Split Right") {
                paneTypeMenu { content in
                    splitPane(axis: .horizontal, content: content)
                }
            }
            Menu("Split Down") {
                paneTypeMenu { content in
                    splitPane(axis: .vertical, content: content)
                }
            }
            Divider()
            Menu("Replace With") {
                paneTypeMenu { content in
                    workspaceManager.updatePaneContent(paneId: leaf.id, content: content)
                }
            }
            if leaf.activeContent.defaultNewPaneTab() != nil {
                Button("New Pane Item") {
                    paneActions.createPaneTab(leaf)
                }
            }
            if showFocusBorder {
                Button("Unsplit") {
                    paneActions.closeOtherPanes(leaf)
                }
                Button("Close Other Panes") {
                    paneActions.closeOtherPanes(leaf)
                }
                Button("Pop Out to Tab") {
                    workspaceManager.popOutPane(id: leaf.id)
                }
            }
            Divider()
            Button("Close Pane") {
                paneActions.closePane(leaf)
            }
        }
    }

    private func splitPane(axis: PaneNode.Split.Axis, content: PaneContent) {
        guard BugbookFeatureGate.allowsPaneContent(content) else { return }
        workspaceManager.setFocusedPane(id: leaf.id)
        _ = workspaceManager.splitFocusedPane(axis: axis, newContent: content)
    }

    @ViewBuilder
    private func paneTypeMenu(action: @escaping (PaneContent) -> Void) -> some View {
        ForEach(Array(BugbookFeatureGate.paneLauncherBuiltInPanes.enumerated()), id: \.offset) { _, pane in
            Button(pane.label) { action(pane.content) }
        }
        if BugbookFeatureGate.legacyPanesEnabled {
            Button("Graph View") { action(.graphDocument()) }
        }
    }

    private var chromeBreadcrumbs: [BreadcrumbItem] {
        guard let provider = breadcrumbProvider,
              case .document(let file) = leaf.content,
              isPlainDocumentPage(file) else {
            return []
        }
        return provider(file)
    }

    private var shouldShowChromeBar: Bool {
        showFocusBorder || leaf.hasMultipleTabs
    }

    private var supportsInlineFindBar: Bool {
        guard case .document(let file) = leaf.content else { return false }
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
    private var contentForLeaf: some View {
        switch leaf.content {
        case .document(let file):
            documentContentBuilder(leaf, file)
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
        in matches: [PaneFindMatch]? = nil,
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

    private func databaseRowIds(in matches: [PaneFindMatch]) -> [String] {
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

// MARK: - Split Direction Icon

/// Correctly oriented split icon: a rectangle with a divider line.
/// `.right` = vertical divider (splits left|right). `.down` = horizontal divider (splits top/bottom).
struct SplitIcon: View {
    enum Direction { case right, down }
    let direction: Direction

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: 12, height: 10)

            if direction == .right {
                // Vertical line = split left|right
                Rectangle().fill(Color.secondary).frame(width: 1.5, height: 10)
            } else {
                // Horizontal line = split top/bottom
                Rectangle().fill(Color.secondary).frame(width: 12, height: 1.5)
            }
        }
    }
}

// MARK: - Button Style

struct PaneActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(backgroundColor(configuration.isPressed))
            )
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        if isPressed {
            return isDestructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.08)
        }
        return .clear
    }
}

// MARK: - Focus Overlay

private struct PaneFocusOverlay: View {
    let paneId: UUID
    let workspaceManager: WorkspaceManager

    var body: some View {
        // Focus tracking only — chrome bar handles focus visual indication.
        #if os(macOS)
        PaneFocusTracker(paneId: paneId) { id in
            workspaceManager.setFocusedPane(id: id)
        }
        #else
        EmptyView()
        #endif
    }
}
