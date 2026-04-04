import SwiftUI

/// Reusable pane launcher: search + direction toggle + results list.
/// Used by chrome bar split button, Cmd+K modal, and /split slash command.
struct PaneLauncher: View {
    enum Variant { case compact, wide }
    enum Direction: Equatable { case right, down, newTab }

    let variant: Variant
    let fileTree: [FileEntry]
    let onSelect: (PaneContent, Direction) -> Void
    let onDismiss: () -> Void
    var onNavigateInPlace: ((PaneContent) -> Void)? = nil

    @State private var search = ""
    @State private var direction: Direction = .right
    @State private var highlightIndex = 0
    @State private var pendingContent: PaneContent? = nil  // step 2: pick direction
    @State private var directionHighlight: Int = 0  // highlighted option in step 2
    @FocusState private var searchFocused: Bool

    private var width: CGFloat { variant == .wide ? 400 : 260 }
    private var maxResultsHeight: CGFloat { variant == .wide ? 340 : 280 }
    private var fontSize: CGFloat { variant == .wide ? 14 : 12 }
    private var itemFontSize: CGFloat { variant == .wide ? 13 : 12 }
    private var itemPadV: CGFloat { variant == .wide ? 7 : 5 }
    private var itemPadH: CGFloat { variant == .wide ? 12 : 10 }
    private var sectionFontSize: CGFloat { variant == .wide ? 10 : 9 }

    /// Wide variant uses two steps: 1) search+select, 2) pick direction.
    /// Compact variant shows direction toggle upfront (one step).
    private var isTwoStep: Bool { variant == .wide }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pending = pendingContent, isTwoStep {
                // Step 2: direction picker after selecting content
                directionStep(for: pending)
            } else {
                // Step 1: search + results (compact shows direction toggle too)
                searchField
                if !isTwoStep { directionToggle }
                scrollableResults
                footer
            }
        }
        .frame(width: width)
        .background(launcherKeyHandler)
        .onChange(of: search) { _, _ in highlightIndex = 0 }
        .onAppear {
            search = ""
            highlightIndex = 0
            pendingContent = nil
            // Delay focus to ensure the view hierarchy is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }

    // MARK: - Search Field (pinned)

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize == 14 ? 13 : 11))
                .foregroundStyle(.tertiary)
            TextField("Search panes and pages...", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .focused($searchFocused)
                .onSubmit { confirmSelection() }
        }
        .padding(.horizontal, itemPadH)
        .padding(.vertical, 8)
        .background(Color.clear) // ensure hit area
    }

    // MARK: - Direction Toggle (pinned)

    private var directionToggle: some View {
        HStack(spacing: 4) {
            directionPill(.right, label: "Right", icon: .right)
            directionPill(.down, label: "Down", icon: .down)

            // Visual separator before New Tab
            Rectangle()
                .fill(Color.fallbackDividerColor)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            // New Tab pill
            Button { direction = .newTab } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 10))
                    Text(variant == .compact ? "Tab" : "New Tab")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(direction == .newTab ? Color.accentColor.opacity(Opacity.light) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(direction == .newTab ? Color.accentColor.opacity(Opacity.strong) : Color.primary.opacity(Opacity.light), lineWidth: 1)
                        )
                )
                .foregroundStyle(direction == .newTab ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Scrollable Results

    private var scrollableResults: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let (panes, pages) = computedResults

                        if !panes.isEmpty {
                            sectionHeader("New Pane")
                            ForEach(Array(panes.enumerated()), id: \.element.id) { offset, result in
                                resultRow(result, index: offset, proxy: proxy)
                            }
                        }

                        if !pages.isEmpty {
                            sectionHeader("Pages")
                            ForEach(Array(pages.enumerated()), id: \.element.id) { offset, result in
                                resultRow(result, index: panes.count + offset, proxy: proxy)
                            }
                        }

                        if panes.isEmpty && pages.isEmpty {
                            Text("No matching panes or pages")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, itemPadH)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: maxResultsHeight)
            }
        }
    }

    // MARK: - Footer (pinned)

    private var footer: some View {
        HStack(spacing: 0) {
            Divider().frame(height: 0) // force border
            kbdHint("Enter", "split")
            if let _ = onNavigateInPlace {
                footerSep
                kbdHint("Cmd+Shift+Enter", "navigate in place")
            }
            footerSep
            kbdHint("Esc", "close")
        }
        .padding(.horizontal, itemPadH)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Data

    static let builtInPanes: [(label: String, icon: String, content: PaneContent)] = [
        ("Terminal", "terminal", .terminal),
        ("Empty Page", "doc", .emptyDocument()),
        ("Mail", "envelope", .mailDocument()),
        ("Calendar", "calendar", .calendarDocument()),
        ("Meetings", "person.2", .meetingsDocument()),
        ("Chat", "bubble.left.and.bubble.right", .chatDocument()),
        ("Home", "house", .gatewayDocument()),
    ]

    enum Result: Identifiable {
        case pane(label: String, icon: String, content: PaneContent)
        case page(entry: FileEntry)

        var id: String {
            switch self {
            case .pane(let label, _, _): return "pane:\(label)"
            case .page(let entry): return "page:\(entry.path)"
            }
        }

        var label: String {
            switch self {
            case .pane(let label, _, _): return label
            case .page(let entry):
                let name = entry.name
                return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
            }
        }

        var icon: String {
            switch self {
            case .pane(_, let icon, _): return icon
            case .page(let entry): return entry.icon ?? (entry.isDatabase ? "tablecells" : "doc.text")
            }
        }

        /// Parent path context for pages.
        var context: String? {
            switch self {
            case .pane: return nil
            case .page(let entry):
                let parent = (entry.path as NSString).deletingLastPathComponent
                let folder = (parent as NSString).lastPathComponent
                return folder.isEmpty ? nil : folder + "/"
            }
        }

        func content() -> PaneContent {
            switch self {
            case .pane(_, _, let c): return c
            case .page(let entry):
                let id = UUID()
                return .document(openFile: OpenFile(
                    id: id, path: entry.path, content: "", isDirty: false, isEmptyTab: false,
                    kind: entry.kind,
                    displayName: entry.name.hasSuffix(".md") ? String(entry.name.dropLast(3)) : entry.name,
                    icon: entry.icon
                ))
            }
        }
    }

    private var flatPages: [FileEntry] {
        Self.flattenTree(fileTree)
    }

    private var computedResults: (panes: [Result], pages: [Result]) {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matchingPanes = Self.builtInPanes
            .filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
            .map { Result.pane(label: $0.label, icon: $0.icon, content: $0.content) }
        let matchingPages: [Result] = query.isEmpty ? [] : flatPages
            .filter { $0.name.localizedStandardContains(query) }
            .prefix(20)
            .map { .page(entry: $0) }
        return (matchingPanes, matchingPages)
    }

    private var allResults: [Result] {
        let (panes, pages) = computedResults
        return panes + pages
    }

    static func flattenTree(_ entries: [FileEntry]) -> [FileEntry] {
        var result: [FileEntry] = []
        for entry in entries {
            if !entry.isDirectory || entry.isDatabase {
                result.append(entry)
            }
            if let children = entry.children {
                result.append(contentsOf: flattenTree(children))
            }
        }
        return result
    }

    // MARK: - Direction Step (wide variant step 2)

    /// Options in step 2. "Open Here" is first (default on Enter).
    private var directionOptions: [(label: String, icon: String, key: String)] {
        var opts: [(String, String, String)] = [
            ("Open Here", "arrow.right.square", "1"),
            ("Split Right", "rectangle.split.2x1", "2"),
            ("Split Down", "rectangle.split.1x2", "3"),
            ("New Tab", "plus.square", "4"),
        ]
        if onNavigateInPlace == nil {
            // Remove "Open Here" if no navigate-in-place handler
            opts.removeFirst()
        }
        return opts
    }

    private func directionStep(for content: PaneContent) -> some View {
        let opts = directionOptions
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    pendingContent = nil
                    searchFocused = true
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("Open where?")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, itemPadH)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            // Options with highlight
            VStack(spacing: 0) {
                ForEach(Array(opts.enumerated()), id: \.offset) { index, opt in
                    let isHi = index == directionHighlight
                    Button {
                        executeDirectionOption(index: index, content: content)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: opt.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(isHi ? Color.accentColor : .secondary)
                                .frame(width: 16)
                            Text(opt.label)
                                .font(.system(size: itemFontSize))
                            Spacer()
                            Text(opt.key)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04)))
                        }
                        .padding(.horizontal, itemPadH)
                        .padding(.vertical, itemPadV)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(isHi ? Color.accentColor.opacity(0.1) : Color.clear)
                                .padding(.horizontal, 4)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { directionHighlight = index }
                    }
                }
            }
            .padding(.vertical, 6)

            // Footer
            HStack(spacing: 0) {
                kbdHint("↑↓", "select")
                footerSep
                kbdHint("Enter", "confirm")
                footerSep
                kbdHint("Esc", "back")
            }
            .padding(.horizontal, itemPadH)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func executeDirectionOption(index: Int, content: PaneContent) {
        let hasNav = onNavigateInPlace != nil
        if hasNav {
            switch index {
            case 0: onNavigateInPlace?(content)
            case 1: onSelect(content, .right)
            case 2: onSelect(content, .down)
            case 3: onSelect(content, .newTab)
            default: break
            }
        } else {
            switch index {
            case 0: onSelect(content, .right)
            case 1: onSelect(content, .down)
            case 2: onSelect(content, .newTab)
            default: break
            }
        }
    }

    // MARK: - Selection

    private func confirmSelection() {
        let results = allResults
        guard highlightIndex < results.count else { return }
        let result = results[highlightIndex]

        if isTwoStep {
            // Wide variant: go to step 2 (direction picker)
            directionHighlight = 0  // "Open Here" highlighted by default
            pendingContent = result.content()
        } else {
            // Compact variant: execute immediately with current direction
            onSelect(result.content(), direction)
        }
    }

    // MARK: - Subviews

    private func directionPill(_ dir: Direction, label: String, icon: SplitIcon.Direction) -> some View {
        Button { direction = dir } label: {
            HStack(spacing: 4) {
                SplitIcon(direction: icon)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(direction == dir ? Color.accentColor.opacity(Opacity.light) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(direction == dir ? Color.accentColor.opacity(Opacity.strong) : Color.primary.opacity(Opacity.light), lineWidth: 1)
                    )
            )
            .foregroundStyle(direction == dir ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: sectionFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, itemPadH)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func resultRow(_ result: Result, index: Int, proxy: ScrollViewProxy) -> some View {
        let isHighlighted = index == highlightIndex
        return Button {
            highlightIndex = index
            confirmSelection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: result.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(result.label)
                    .font(.system(size: itemFontSize))
                    .lineLimit(1)
                if let ctx = result.context {
                    Spacer()
                    Text(ctx)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, itemPadH)
            .padding(.vertical, itemPadV)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.1) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(result.id)
        .onHover { hovering in
            if hovering { highlightIndex = index }
        }
    }

    private func kbdHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                )
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private var footerSep: some View {
        Text("·")
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 4)
    }

    // MARK: - Keyboard Handler

    private var launcherKeyHandler: some View {
        PaneLauncherKeyListener(
            onUp: {
                if pendingContent != nil {
                    let count = directionOptions.count
                    guard count > 0 else { return }
                    directionHighlight = (directionHighlight - 1 + count) % count
                } else {
                    let count = allResults.count
                    guard count > 0 else { return }
                    highlightIndex = (highlightIndex - 1 + count) % count
                }
            },
            onDown: {
                if pendingContent != nil {
                    let count = directionOptions.count
                    guard count > 0 else { return }
                    directionHighlight = (directionHighlight + 1) % count
                } else {
                    let count = allResults.count
                    guard count > 0 else { return }
                    highlightIndex = (highlightIndex + 1) % count
                }
            },
            onEnter: {
                if let content = pendingContent {
                    // Step 2: confirm highlighted direction
                    executeDirectionOption(index: directionHighlight, content: content)
                } else {
                    confirmSelection()
                }
            },
            onTab: {
                guard pendingContent == nil else { return }
                if !isTwoStep {
                    switch direction {
                    case .right: direction = .down
                    case .down: direction = .newTab
                    case .newTab: direction = .right
                    }
                }
            },
            onEscape: {
                if pendingContent != nil {
                    pendingContent = nil
                    directionHighlight = 0
                    searchFocused = true
                } else {
                    onDismiss()
                }
            },
            onDigit: { digit in
                guard let content = pendingContent else { return }
                let index = digit - 1
                if index >= 0 && index < directionOptions.count {
                    executeDirectionOption(index: index, content: content)
                }
            }
        )
        .frame(width: 0, height: 0)
    }
}

// MARK: - Key Listener

/// Global key event monitor for the launcher. Uses NSEvent.addLocalMonitorForEvents
/// so it works regardless of first responder status (critical for step 2 where there's no text field).
struct PaneLauncherKeyListener: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void
    let onTab: () -> Void
    let onEscape: () -> Void
    var onDigit: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(
            onUp: onUp, onDown: onDown, onEnter: onEnter,
            onTab: onTab, onEscape: onEscape, onDigit: onDigit
        )
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(
            onUp: onUp, onDown: onDown, onEnter: onEnter,
            onTab: onTab, onEscape: onEscape, onDigit: onDigit
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        private var monitor: Any?
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEnter: (() -> Void)?
        var onTab: (() -> Void)?
        var onEscape: (() -> Void)?
        var onDigit: ((Int) -> Void)?

        private let digitKeyCodes: [UInt16: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5
        ]

        func install(onUp: @escaping () -> Void, onDown: @escaping () -> Void,
                     onEnter: @escaping () -> Void, onTab: @escaping () -> Void,
                     onEscape: @escaping () -> Void, onDigit: ((Int) -> Void)?) {
            update(onUp: onUp, onDown: onDown, onEnter: onEnter, onTab: onTab, onEscape: onEscape, onDigit: onDigit)
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 126: self.onUp?(); return nil      // Up
                case 125: self.onDown?(); return nil     // Down
                case 36: self.onEnter?(); return nil     // Return
                case 48: self.onTab?(); return nil       // Tab
                case 53: self.onEscape?(); return nil    // Escape
                default:
                    if let digit = self.digitKeyCodes[event.keyCode], self.onDigit != nil {
                        self.onDigit?(digit)
                        return nil
                    }
                    return event
                }
            }
        }

        func update(onUp: @escaping () -> Void, onDown: @escaping () -> Void,
                    onEnter: @escaping () -> Void, onTab: @escaping () -> Void,
                    onEscape: @escaping () -> Void, onDigit: ((Int) -> Void)?) {
            self.onUp = onUp
            self.onDown = onDown
            self.onEnter = onEnter
            self.onTab = onTab
            self.onEscape = onEscape
            self.onDigit = onDigit
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
