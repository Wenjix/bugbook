import Foundation
import GhosttyKit
import AppKit
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "Terminal")

/// Tracks the most recently focused Ghostty surface for clipboard callbacks.
/// Set on the main thread in becomeFirstResponder; read in C callbacks that also run on main.
nonisolated(unsafe) var _activeSurface: ghostty_surface_t? = nil

/// Manages a single terminal instance backed by a libghostty surface.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let workingDirectory: String

    private(set) var title: String = "Terminal"
    private(set) var isAlive: Bool = false
    private(set) var surfaceView: GhosttySurfaceHostView?

    init(id: UUID = UUID(), workingDirectory: String) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func start(app: ghostty_app_t) {
        let hostView = GhosttySurfaceHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        hostView.wantsLayer = true
        hostView.layer?.isOpaque = true

        var surfaceCfg = ghostty_surface_config_new()
        surfaceCfg.userdata = Unmanaged.passUnretained(hostView).toOpaque()
        surfaceCfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceCfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(hostView).toOpaque()
        ))

        if let screen = NSScreen.main {
            surfaceCfg.scale_factor = screen.backingScaleFactor
        } else {
            surfaceCfg.scale_factor = 2.0
        }

        workingDirectory.withCString { cStr in
            surfaceCfg.working_directory = cStr

            guard let surface = ghostty_surface_new(app, &surfaceCfg) else {
                log.error("ghostty_surface_new failed for session \(self.id)")
                return
            }
            hostView.surface = surface
            self.surfaceView = hostView
            self.isAlive = true
            log.info("Started ghostty terminal session \(self.id)")
        }
    }

    func terminate() {
        if let view = surfaceView, let surface = view.surface {
            ghostty_surface_free(surface)
            view.surface = nil
        }
        surfaceView = nil
        isAlive = false
    }
}

// MARK: - Host NSView with Input Forwarding

class GhosttySurfaceHostView: NSView {
    var surface: ghostty_surface_t?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.isOpaque = true
        metalLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return metalLayer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            layer?.contentsScale = window.backingScaleFactor
        }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let surface {
            ghostty_surface_set_focus(surface, true)
            _activeSurface = surface
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if let surface {
            ghostty_surface_set_focus(surface, false)
            if _activeSurface == surface { _activeSurface = nil }
        }
        return result
    }

    // MARK: - Key Equivalents (Cmd+key)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else { return super.performKeyEquivalent(with: event) }

        // Forward key equivalents to ghostty before AppKit routes them
        // through the menu system. This ensures Cmd+V (paste), Cmd+C
        // (copy), and other ghostty bindings are handled by the terminal.
        let text = event.ghosttyCharacters
        var keyEv = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        if let text, !text.isEmpty, let codepoint = text.utf8.first, codepoint >= 0x20 {
            let handled = text.withCString { ptr -> Bool in
                keyEv.text = ptr
                return ghostty_surface_key(surface, keyEv)
            }
            if handled { return true }
        } else {
            if ghostty_surface_key(surface, keyEv) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Paste (fallback for Edit menu)

    @objc func paste(_ sender: Any?) {
        guard let surface else { return }
        _ = ghostty_surface_binding_action(surface, "paste_from_clipboard", 0)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else { super.keyDown(with: event); return }
        let text = event.ghosttyCharacters
        var keyEv = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        if let text, !text.isEmpty, let codepoint = text.utf8.first, codepoint >= 0x20 {
            text.withCString { ptr in
                keyEv.text = ptr
                _ = ghostty_surface_key(surface, keyEv)
            }
        } else {
            _ = ghostty_surface_key(surface, keyEv)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { super.keyUp(with: event); return }
        let keyEv = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, keyEv)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { super.flagsChanged(with: event); return }
        let keyEv = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        _ = ghostty_surface_key(surface, keyEv)
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { super.mouseDown(with: event); return }
        let mods = ghosttyMods(event.modifierFlags)
        let pt = convertToSurfacePoint(event)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { super.mouseUp(with: event); return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { super.mouseDragged(with: event); return }
        let pt = convertToSurfacePoint(event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { super.scrollWheel(with: event); return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, ghostty_input_scroll_mods_t(ghosttyMods(event.modifierFlags).rawValue))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pt = convertToSurfacePoint(event)
        ghostty_surface_mouse_pos(surface, pt.x, pt.y, ghosttyMods(event.modifierFlags))
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let surface {
            let scale = window?.backingScaleFactor ?? 2.0
            ghostty_surface_set_size(surface, UInt32(newSize.width * scale), UInt32(newSize.height * scale))
        }
    }

    // MARK: - Helpers

    private func convertToSurfacePoint(_ event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(mods)
    }
}

// MARK: - NSEvent → Ghostty Key Event Bridge

private extension NSEvent {
    func ghosttyKeyEvent(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var ev = ghostty_input_key_s()
        ev.action = action
        ev.keycode = UInt32(keyCode)
        ev.text = nil
        ev.composing = false
        ev.mods = ghosttyModsFromFlags(modifierFlags)
        ev.consumed_mods = ghosttyModsFromFlags(modifierFlags.subtracting([.control, .command]))

        ev.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            if let chars = characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                ev.unshifted_codepoint = codepoint.value
            }
        }
        return ev
    }

    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return characters
    }

    private func ghosttyModsFromFlags(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(mods)
    }
}
