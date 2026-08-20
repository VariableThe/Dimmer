import AppKit
import CoreGraphics
import Foundation

/// Immutable information about a physical display. The app only selects an
/// instance whose `isBuiltIn` value is true; external displays remain visible
/// in diagnostics but are never adjusted.
struct DisplayInfo: Identifiable, Equatable, Sendable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    /// Global AppKit coordinates used to position the fallback overlay.
    let frame: CGRect
    let backingScaleFactor: Double

    var pixelSizeDescription: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var refreshRateDescription: String {
        refreshRate > 0 ? String(format: "%.0f Hz", refreshRate) : "Unknown"
    }
}

@MainActor
func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
}

@MainActor
func screen(for targetDisplayID: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { displayID(for: $0) == targetDisplayID }
}
