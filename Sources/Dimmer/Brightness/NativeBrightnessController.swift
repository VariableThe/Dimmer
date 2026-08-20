import CoreGraphics
import Foundation

/// Placeholder for a future Apple-supported physical backlight API.
///
/// IOKit's `IODisplaySetFloatParameter` exists, but the public
/// `CGDisplayIOServicePort` bridge it conventionally needs is deprecated with
/// no replacement. Calling it would violate this app's supported-API policy,
/// so this controller truthfully declines the capability.
@MainActor
final class NativeBrightnessController: BrightnessController {
    let capabilities = BrightnessControllerCapabilities.unavailable
    private(set) var activeDisplayID: CGDirectDisplayID?

    func prepare(for display: DisplayInfo) throws {
        activeDisplayID = display.id
        throw BrightnessControllerError.unavailable(capabilities.description)
    }

    func currentEffectiveBrightness() -> Double? { nil }

    func setEffectiveBrightness(_ brightness: Double) throws {
        throw BrightnessControllerError.unavailable(capabilities.description)
    }

    func deactivate() {
        activeDisplayID = nil
    }
}
