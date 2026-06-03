import SwiftUI

enum EditorFocusModeAnimation {
    static let duration: TimeInterval = 0.45
    static let animation: Animation = .easeInOut(duration: duration)
}

@MainActor
@Observable
final class EditorUIState {
    var focusModeActive = false
    var focusModeSuppress = false
    var zoomHudVisible = false
    var zoomHudHovered = false

    @ObservationIgnored private var focusModeTask: Task<Void, Never>?
    @ObservationIgnored private var zoomHudTask: Task<Void, Never>?

    /// Whether focus mode is enabled in user settings. Set by ContentView.
    @ObservationIgnored var focusModeEnabled = false

    func setFocusModeEnabled(_ enabled: Bool) {
        focusModeEnabled = enabled
        if !enabled {
            endFocusMode()
        }
    }

    func triggerFocusMode() {
        guard focusModeEnabled else { return }
        guard !focusModeSuppress else { return }
        focusModeTask?.cancel()
        focusModeTask = nil
        if !focusModeActive {
            withAnimation(EditorFocusModeAnimation.animation) {
                focusModeActive = true
            }
        }
    }

    func handlePointerMovement() {
        guard focusModeActive else { return }
        endFocusMode()
    }

    private func endFocusMode() {
        focusModeTask?.cancel()
        focusModeTask = nil
        guard focusModeActive else { return }
        withAnimation(EditorFocusModeAnimation.animation) {
            focusModeActive = false
        }
    }

    func showZoomHud() {
        zoomHudTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            zoomHudVisible = true
        }
        scheduleZoomHudHide()
    }

    func scheduleZoomHudHide() {
        zoomHudTask?.cancel()
        zoomHudTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, !zoomHudHovered else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                zoomHudVisible = false
            }
        }
    }

    func cleanUp() {
        focusModeTask?.cancel()
        focusModeTask = nil
        zoomHudTask?.cancel()
        zoomHudTask = nil
    }
}

private struct EditorTypingFocusActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct EditorTypingFocusFullBleedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var editorTypingFocusActive: Bool {
        get { self[EditorTypingFocusActiveKey.self] }
        set { self[EditorTypingFocusActiveKey.self] = newValue }
    }

    var editorTypingFocusFullBleed: Bool {
        get { self[EditorTypingFocusFullBleedKey.self] }
        set { self[EditorTypingFocusFullBleedKey.self] = newValue }
    }
}
