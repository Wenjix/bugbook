import SwiftUI

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

    func triggerFocusMode() {
        guard focusModeEnabled else { return }
        guard !focusModeSuppress else { return }
        if !focusModeActive {
            withAnimation(.easeInOut(duration: 0.6)) {
                focusModeActive = true
            }
        }
        focusModeTask?.cancel()
        focusModeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                focusModeActive = false
            }
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
