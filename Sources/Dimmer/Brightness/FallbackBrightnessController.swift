import CoreGraphics
import Foundation

/// Selects the hardware controller only when it advertises a supported,
/// usable implementation. The current native controller intentionally does
/// not, so the black overlay is the functional MVP fallback.
@MainActor
final class FallbackBrightnessController: BrightnessController {
    private let native: NativeBrightnessController
    private let overlay: OverlayBrightnessController
    private var activeController: any BrightnessController

    init() {
        let native = NativeBrightnessController()
        let overlay = OverlayBrightnessController()
        self.native = native
        self.overlay = overlay
        self.activeController = overlay
    }

    init(native: NativeBrightnessController, overlay: OverlayBrightnessController) {
        self.native = native
        self.overlay = overlay
        self.activeController = overlay
    }

    var capabilities: BrightnessControllerCapabilities {
        activeController.capabilities
    }

    var activeDisplayID: CGDirectDisplayID? {
        activeController.activeDisplayID
    }

    func prepare(for display: DisplayInfo) throws {
        native.deactivate()

        if native.capabilities.canSetHardwareBrightness {
            do {
                try native.prepare(for: display)
                overlay.deactivate()
                activeController = native
                return
            } catch {
                native.deactivate()
            }
        }

        try overlay.prepare(for: display)
        activeController = overlay
    }

    func currentEffectiveBrightness() -> Double? {
        activeController.currentEffectiveBrightness()
    }

    func setEffectiveBrightness(_ brightness: Double) throws {
        try activeController.setEffectiveBrightness(brightness)
    }

    func deactivate() {
        native.deactivate()
        overlay.deactivate()
    }
}
