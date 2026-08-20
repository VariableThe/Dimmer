import Combine
import Foundation

/// A future supported sensor source can conform to this protocol. The current
/// MacBook implementation deliberately reports unavailable: SensorKit's
/// ambient-light APIs are unavailable on macOS and private SMC/IOKit probes are
/// outside this app's public-API policy.
@MainActor
protocol AmbientLightProviding: AnyObject {
    var reading: AmbientLightReading { get }
    var statusDescription: String { get }
}

@MainActor
final class AmbientLightManager: ObservableObject, AmbientLightProviding {
    @Published private(set) var reading: AmbientLightReading = .unavailable

    let statusDescription = "Unavailable — macOS has no documented public MacBook ambient-light reading API."
}
