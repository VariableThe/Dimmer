import AppKit
import CoreGraphics
import Foundation

/// A reliable, noninteractive virtual-dimming fallback. It is intentionally
/// scoped to the selected built-in display, not to a Space or every screen.
@MainActor
final class OverlayBrightnessController: BrightnessController {
    let capabilities = BrightnessControllerCapabilities(
        kind: .overlay,
        canReadHardwareBrightness: false,
        canSetHardwareBrightness: false,
        description: "Using a local overlay fallback; hardware brightness is unavailable through supported public APIs."
    )

    private(set) var activeDisplayID: CGDirectDisplayID?
    private var panel: DimmingPanel?
    private var effectiveBrightness: Double = 1

    func prepare(for display: DisplayInfo) throws {
        guard display.isBuiltIn else {
            throw BrightnessControllerError.noBuiltInDisplay
        }
        guard let targetScreen = screen(for: display.id) else {
            throw BrightnessControllerError.unavailable("The built-in display is not currently available to AppKit.")
        }

        if activeDisplayID != display.id {
            deactivate()
            panel = DimmingPanel(screen: targetScreen)
            activeDisplayID = display.id
        } else {
            panel?.setFrame(targetScreen.frame, display: true)
        }

        try setEffectiveBrightness(effectiveBrightness)
    }

    /// This is the requested effective overlay brightness, never a claim about
    /// the hardware backlight value.
    func currentEffectiveBrightness() -> Double? {
        activeDisplayID == nil ? nil : effectiveBrightness
    }

    func setEffectiveBrightness(_ brightness: Double) throws {
        guard let panel else {
            throw BrightnessControllerError.unavailable("The fallback overlay has not been prepared for a display.")
        }

        let normalized = unitInterval(brightness)
        effectiveBrightness = normalized
        panel.dimmingView.opacity = CGFloat(1 - normalized)

        // Hiding a fully transparent panel minimizes WindowServer work. When
        // dimming resumes, join all Spaces again before ordering it forward.
        if normalized >= 0.999_9 {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func deactivate() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        activeDisplayID = nil
        effectiveBrightness = 1
    }
}

@MainActor
private final class DimmingPanel: NSPanel {
    let dimmingView = DimmingView(frame: .zero)

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Stay above ordinary app windows but below the menu/status-bar levels
        // so the menu-bar control remains usable even at maximum dimming.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        dimmingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        dimmingView.autoresizingMask = [.width, .height]
        contentView = dimmingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DimmingView: NSView {
    var opacity: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(opacity).setFill()
        dirtyRect.fill()
    }
}
