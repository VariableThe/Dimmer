import CoreGraphics
import Foundation

enum BrightnessControlKind: String, Sendable, Equatable {
    case hardware
    case overlay
    case unavailable
}

struct BrightnessControllerCapabilities: Sendable, Equatable {
    let kind: BrightnessControlKind
    let canReadHardwareBrightness: Bool
    let canSetHardwareBrightness: Bool
    let description: String

    static let unavailable = BrightnessControllerCapabilities(
        kind: .unavailable,
        canReadHardwareBrightness: false,
        canSetHardwareBrightness: false,
        description: "No supported public hardware-brightness API is available."
    )
}

enum BrightnessControllerError: LocalizedError {
    case noBuiltInDisplay
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .noBuiltInDisplay:
            "No built-in display is currently available."
        case let .unavailable(reason):
            reason
        }
    }
}

/// All values are normalized to `0...1`. `currentEffectiveBrightness` and
/// `setEffectiveBrightness` describe the app's output model: a native
/// controller may map it to hardware brightness, while the fallback maps it
/// to a relative black-overlay attenuation. Neither must be presented as a
/// physical-backlight reading unless the capability says it can read one.
@MainActor
protocol BrightnessController: AnyObject {
    var capabilities: BrightnessControllerCapabilities { get }
    var activeDisplayID: CGDirectDisplayID? { get }

    func prepare(for display: DisplayInfo) throws
    func currentEffectiveBrightness() -> Double?
    func setEffectiveBrightness(_ brightness: Double) throws
    func deactivate()
}
