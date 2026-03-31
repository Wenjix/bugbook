import Foundation
import GhosttyKit
import AppKit
import os

private let log = Logger(subsystem: "com.bugbook.app", category: "Terminal")

/// Manages a single terminal instance backed by a libghostty surface.
/// The surface handles its own PTY/shell process internally and renders
/// via Metal into the host NSView.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let workingDirectory: String

    private(set) var title: String = "Terminal"
    private(set) var isAlive: Bool = false

    /// The NSView hosting the ghostty Metal surface. Embed this via NSViewRepresentable.
    private(set) var surfaceView: GhosttySurfaceHostView?

    init(
        id: UUID = UUID(),
        workingDirectory: String
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func start(app: ghostty_app_t) {
        let hostView = GhosttySurfaceHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        hostView.wantsLayer = true
        hostView.layer?.isOpaque = true

        // Build the surface config. The surface needs the NSView pointer for Metal rendering.
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

        // Set working directory
        workingDirectory.withCString { cStr in
            surfaceCfg.working_directory = cStr

            // Create the surface — this spawns the shell process and starts rendering
            guard let surface = ghostty_surface_new(app, &surfaceCfg) else {
                log.error("ghostty_surface_new failed for session \(self.id)")
                return
            }
            hostView.surface = surface
            self.surfaceView = hostView
            self.isAlive = true
            log.info("Started ghostty terminal session \(self.id) in \(self.workingDirectory)")
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

// MARK: - Host NSView

/// A minimal NSView that hosts the ghostty Metal surface. Ghostty renders
/// directly into this view's backing layer. This view also handles first
/// responder status so keyboard input reaches the surface.
class GhosttySurfaceHostView: NSView {
    var surface: ghostty_surface_t?

    override var acceptsFirstResponder: Bool { true }

    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        // Use a CAMetalLayer for GPU rendering
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

    // Forward key events to the surface
    override func keyDown(with event: NSEvent) {
        guard surface != nil else { super.keyDown(with: event); return }
        // TODO: Forward key events to ghostty_surface_key() once Input types are bridged.
        // For now, let the surface handle it through its internal input handling.
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard surface != nil else { super.keyUp(with: event); return }
        super.keyUp(with: event)
    }

    // Forward mouse events
    override func mouseDown(with event: NSEvent) {
        guard surface != nil else { super.mouseDown(with: event); return }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard surface != nil else { super.mouseUp(with: event); return }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard surface != nil else { super.scrollWheel(with: event); return }
        super.scrollWheel(with: event)
    }
}
