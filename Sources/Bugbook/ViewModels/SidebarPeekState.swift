import SwiftUI

@MainActor
@Observable
final class SidebarPeekState {
    var isVisible = false
    var toggleHovering = false
    var edgeHovering = false
    var overlayHovering = false
    var trashPopoverPresented = false

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?

    var interactionActive: Bool {
        toggleHovering || edgeHovering || overlayHovering || trashPopoverPresented
    }

    func setToggleHovering(_ hovering: Bool, eligible: Bool, reduceMotion: Bool) {
        guard toggleHovering != hovering else { return }
        toggleHovering = hovering
        sync(eligible: eligible, reduceMotion: reduceMotion)
    }

    func setEdgeHovering(_ hovering: Bool, eligible: Bool, reduceMotion: Bool) {
        guard edgeHovering != hovering else { return }
        edgeHovering = hovering
        sync(eligible: eligible, reduceMotion: reduceMotion)
    }

    func setOverlayHovering(_ hovering: Bool, eligible: Bool, reduceMotion: Bool) {
        guard overlayHovering != hovering else { return }
        overlayHovering = hovering
        sync(eligible: eligible, reduceMotion: reduceMotion)
    }

    func dismiss(immediately: Bool, reduceMotion: Bool) {
        cancelDismissTask()
        trashPopoverPresented = false
        resetHoverState()
        guard isVisible else { return }
        if immediately {
            isVisible = false
        } else {
            withAnimation(animation(reduceMotion: reduceMotion)) {
                isVisible = false
            }
        }
    }

    func sync(eligible: Bool, reduceMotion: Bool) {
        cancelDismissTask()

        guard eligible else {
            cancelDwellTask()
            dismiss(immediately: true, reduceMotion: reduceMotion)
            return
        }

        let anim = animation(reduceMotion: reduceMotion)

        if interactionActive {
            if isVisible { return }

            if toggleHovering || overlayHovering {
                cancelDwellTask()
                withAnimation(anim) { isVisible = true }
                return
            }

            if edgeHovering && dwellTask == nil {
                dwellTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    guard edgeHovering else { return }
                    withAnimation(anim) { isVisible = true }
                }
            }
            return
        }

        // No interaction — schedule dismiss
        cancelDwellTask()
        guard isVisible else { return }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            guard !interactionActive else { return }
            withAnimation(anim) { isVisible = false }
        }
    }

    func cancelDwellTask() {
        dwellTask?.cancel()
        dwellTask = nil
    }

    func cleanUp() {
        dismissTask?.cancel()
        dismissTask = nil
        dwellTask?.cancel()
        dwellTask = nil
    }

    // MARK: - Private

    private func cancelDismissTask() {
        dismissTask?.cancel()
        guard dismissTask != nil else { return }
        dismissTask = nil
    }

    private func resetHoverState() {
        guard toggleHovering || edgeHovering || overlayHovering else { return }
        toggleHovering = false
        edgeHovering = false
        overlayHovering = false
    }

    private func animation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.1 : 0.18)
    }
}
