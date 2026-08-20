import Foundation

/// A compact, privacy-preserving summary of a captured screen frame.
///
/// Every luminance value is expressed in the `0...1` range after conversion
/// from RGB by the frame analyser. No pixels or screenshots are retained by
/// this model.
struct ScreenStatistics: Sendable, Equatable, Codable {
    let meanLuminance: Double
    let medianLuminance: Double
    let minimumLuminance: Double
    let maximumLuminance: Double
    let p90Luminance: Double
    let p95Luminance: Double
    let p99Luminance: Double
    let darkPixelFraction: Double
    let brightPixelFraction: Double
    let luminanceVariance: Double
    let darkPixelThreshold: Double
    let brightPixelThreshold: Double

    init(
        meanLuminance: Double,
        medianLuminance: Double,
        minimumLuminance: Double,
        maximumLuminance: Double,
        p90Luminance: Double,
        p95Luminance: Double,
        p99Luminance: Double,
        darkPixelFraction: Double,
        brightPixelFraction: Double,
        luminanceVariance: Double,
        darkPixelThreshold: Double = 0.15,
        brightPixelThreshold: Double = 0.85
    ) {
        let safeMinimum = unitInterval(minimumLuminance)
        let safeMaximum = max(safeMinimum, unitInterval(maximumLuminance))
        let range = safeMinimum...safeMaximum
        let safeMedian = constrained(unitInterval(medianLuminance), to: range)
        let safeP90 = constrained(max(safeMedian, unitInterval(p90Luminance)), to: range)
        let safeP95 = constrained(max(safeP90, unitInterval(p95Luminance)), to: range)
        let safeP99 = constrained(max(safeP95, unitInterval(p99Luminance)), to: range)

        self.minimumLuminance = safeMinimum
        self.maximumLuminance = safeMaximum
        self.meanLuminance = constrained(unitInterval(meanLuminance), to: range)
        self.medianLuminance = safeMedian
        self.p90Luminance = safeP90
        self.p95Luminance = safeP95
        self.p99Luminance = safeP99
        self.darkPixelFraction = unitInterval(darkPixelFraction)
        self.brightPixelFraction = unitInterval(brightPixelFraction)
        self.luminanceVariance = max(0, finiteOr(luminanceVariance, fallback: 0))

        let safeDarkThreshold = unitInterval(darkPixelThreshold)
        self.darkPixelThreshold = safeDarkThreshold
        self.brightPixelThreshold = max(safeDarkThreshold, unitInterval(brightPixelThreshold))
    }

    /// Convenience statistics for a frame whose pixels all have one luminance.
    static func uniform(
        _ luminance: Double,
        darkPixelThreshold: Double = 0.15,
        brightPixelThreshold: Double = 0.85
    ) -> ScreenStatistics {
        let value = unitInterval(luminance)
        let darkThreshold = unitInterval(darkPixelThreshold)
        let brightThreshold = max(darkThreshold, unitInterval(brightPixelThreshold))

        return ScreenStatistics(
            meanLuminance: value,
            medianLuminance: value,
            minimumLuminance: value,
            maximumLuminance: value,
            p90Luminance: value,
            p95Luminance: value,
            p99Luminance: value,
            darkPixelFraction: value <= darkThreshold ? 1 : 0,
            brightPixelFraction: value >= brightThreshold ? 1 : 0,
            luminanceVariance: 0,
            darkPixelThreshold: darkThreshold,
            brightPixelThreshold: brightThreshold
        )
    }

    var darkPixelPercentage: Double { darkPixelFraction * 100 }
    var brightPixelPercentage: Double { brightPixelFraction * 100 }

    /// Computes a robust content brightness score. Percentiles and the bright
    /// pixel fraction carry more weight than the raw maximum, so a small white
    /// cursor or highlight cannot dominate the result.
    func contentBrightnessScore(using weights: ContentScoreWeights = .standard) -> Double {
        let weights = weights.sanitized()
        let percentileWeight = weights.median
            + weights.p90
            + weights.p95
            + weights.p99

        guard percentileWeight > 0 else { return 0 }

        let percentileScore = (
            (medianLuminance * weights.median)
                + (p90Luminance * weights.p90)
                + (p95Luminance * weights.p95)
                + (p99Luminance * weights.p99)
        ) / percentileWeight
        let highlightAdjustment = brightPixelFraction * weights.brightPixelFraction

        return unitInterval(percentileScore + highlightAdjustment - (darkPixelFraction * weights.darkPixelPenalty))
    }
}

/// Tunable weights for the screen-content score. They intentionally omit raw
/// maximum luminance because a single bright pixel is not a useful signal.
struct ContentScoreWeights: Sendable, Equatable, Codable {
    var median: Double
    var p90: Double
    var p95: Double
    var p99: Double
    var brightPixelFraction: Double
    var darkPixelPenalty: Double

    init(
        median: Double = 0.50,
        p90: Double = 0.20,
        p95: Double = 0.15,
        p99: Double = 0.05,
        brightPixelFraction: Double = 0.10,
        darkPixelPenalty: Double = 0.10
    ) {
        self.median = max(0, finiteOr(median, fallback: 0))
        self.p90 = max(0, finiteOr(p90, fallback: 0))
        self.p95 = max(0, finiteOr(p95, fallback: 0))
        self.p99 = max(0, finiteOr(p99, fallback: 0))
        self.brightPixelFraction = max(0, finiteOr(brightPixelFraction, fallback: 0))
        self.darkPixelPenalty = max(0, finiteOr(darkPixelPenalty, fallback: 0))
    }

    static let standard = ContentScoreWeights()

    func sanitized() -> ContentScoreWeights {
        ContentScoreWeights(
            median: median,
            p90: p90,
            p95: p95,
            p99: p99,
            brightPixelFraction: brightPixelFraction,
            darkPixelPenalty: darkPixelPenalty
        )
    }
}

/// A source-neutral ambient-light value. `lux` is converted with a logarithmic
/// curve so equal multiplicative changes in light have a similar influence.
enum AmbientLightReading: Sendable, Equatable, Codable {
    case unavailable
    case normalized(Double)
    case lux(Double)

    var normalizedValue: Double? {
        switch self {
        case .unavailable:
            return nil
        case let .normalized(value):
            guard value.isFinite else { return nil }
            return unitInterval(value)
        case let .lux(value):
            guard value.isFinite else { return nil }
            let cappedLux = max(0, min(value, 10_000))
            return log(1 + cappedLux) / log(10_001)
        }
    }
}

enum AdaptiveSensitivity: String, CaseIterable, Sendable, Codable {
    case low
    case medium
    case high

    var multiplier: Double {
        switch self {
        case .low: 0.65
        case .medium: 1.0
        case .high: 1.35
        }
    }
}

enum BrightnessTransitionSpeed: String, CaseIterable, Sendable, Codable {
    case slow
    case normal
    case fast

    /// EMA time constant in seconds. Smaller values respond faster.
    var smoothingTimeConstant: TimeInterval {
        switch self {
        case .slow: 0.9
        case .normal: 0.4
        case .fast: 0.18
        }
    }

    /// Hardware brightness change allowed per second after smoothing.
    var maximumChangePerSecond: Double {
        switch self {
        case .slow: 0.10
        case .normal: 0.25
        case .fast: 0.45
        }
    }
}

/// User-controlled inputs to the deterministic adaptation model.
struct AdaptiveBrightnessPreferences: Sendable, Equatable, Codable {
    var isEnabled: Bool
    var preferredBrightness: Double
    var minimumBrightness: Double
    var maximumBrightness: Double
    var contentSensitivity: AdaptiveSensitivity
    var ambientSensitivity: AdaptiveSensitivity
    var transitionSpeed: BrightnessTransitionSpeed
    var darkRoomBias: Double
    var hysteresisThreshold: Double
    var manualOverrideDuration: TimeInterval

    init(
        isEnabled: Bool = true,
        preferredBrightness: Double = 0.60,
        minimumBrightness: Double = 0.10,
        maximumBrightness: Double = 1.0,
        contentSensitivity: AdaptiveSensitivity = .medium,
        ambientSensitivity: AdaptiveSensitivity = .medium,
        transitionSpeed: BrightnessTransitionSpeed = .normal,
        darkRoomBias: Double = 0,
        hysteresisThreshold: Double = 0.015,
        manualOverrideDuration: TimeInterval = 90
    ) {
        let bounds = AdaptiveBrightnessPreferences.validBrightnessBounds(
            minimum: minimumBrightness,
            maximum: maximumBrightness
        )

        self.isEnabled = isEnabled
        self.preferredBrightness = constrained(unitInterval(preferredBrightness), to: bounds)
        self.minimumBrightness = bounds.lowerBound
        self.maximumBrightness = bounds.upperBound
        self.contentSensitivity = contentSensitivity
        self.ambientSensitivity = ambientSensitivity
        self.transitionSpeed = transitionSpeed
        self.darkRoomBias = unitInterval(darkRoomBias)
        self.hysteresisThreshold = unitInterval(hysteresisThreshold)
        self.manualOverrideDuration = max(0, finiteOr(manualOverrideDuration, fallback: 0))
    }

    var brightnessBounds: ClosedRange<Double> {
        AdaptiveBrightnessPreferences.validBrightnessBounds(
            minimum: minimumBrightness,
            maximum: maximumBrightness
        )
    }

    func sanitized() -> AdaptiveBrightnessPreferences {
        AdaptiveBrightnessPreferences(
            isEnabled: isEnabled,
            preferredBrightness: preferredBrightness,
            minimumBrightness: minimumBrightness,
            maximumBrightness: maximumBrightness,
            contentSensitivity: contentSensitivity,
            ambientSensitivity: ambientSensitivity,
            transitionSpeed: transitionSpeed,
            darkRoomBias: darkRoomBias,
            hysteresisThreshold: hysteresisThreshold,
            manualOverrideDuration: manualOverrideDuration
        )
    }

    private static func validBrightnessBounds(minimum: Double, maximum: Double) -> ClosedRange<Double> {
        let safeMinimum = unitInterval(minimum)
        let safeMaximum = max(safeMinimum, unitInterval(maximum))
        return safeMinimum...safeMaximum
    }
}

/// Inputs captured at one point in time. Passing an explicit timestamp keeps
/// the engine deterministic and makes its transition behavior easy to test.
struct AdaptiveBrightnessInput: Sendable, Equatable, Codable {
    let screenStatistics: ScreenStatistics
    let ambientLight: AmbientLightReading
    /// The current output level in the active controller's effective-brightness
    /// model. With the overlay fallback this is relative attenuation, not a
    /// hardware-backlight measurement.
    let currentEffectiveBrightness: Double
    let timestamp: Date

    init(
        screenStatistics: ScreenStatistics,
        ambientLight: AmbientLightReading = .unavailable,
        currentEffectiveBrightness: Double,
        timestamp: Date = .now
    ) {
        self.screenStatistics = screenStatistics
        self.ambientLight = ambientLight
        self.currentEffectiveBrightness = unitInterval(currentEffectiveBrightness)
        self.timestamp = timestamp
    }
}

/// Model constants separated from preferences so a future personalized model
/// can change the target calculation without changing the UI-facing settings.
struct AdaptiveBrightnessTuning: Sendable, Equatable, Codable {
    var contentScoreWeights: ContentScoreWeights
    var contentAdjustmentRange: Double
    var ambientAdjustmentRange: Double
    var darkRoomBiasRange: Double
    var ambientCurveExponent: Double

    init(
        contentScoreWeights: ContentScoreWeights = .standard,
        contentAdjustmentRange: Double = 0.36,
        ambientAdjustmentRange: Double = 0.30,
        darkRoomBiasRange: Double = 0.12,
        ambientCurveExponent: Double = 0.55
    ) {
        self.contentScoreWeights = contentScoreWeights
        self.contentAdjustmentRange = max(0, finiteOr(contentAdjustmentRange, fallback: 0))
        self.ambientAdjustmentRange = max(0, finiteOr(ambientAdjustmentRange, fallback: 0))
        self.darkRoomBiasRange = max(0, finiteOr(darkRoomBiasRange, fallback: 0))
        self.ambientCurveExponent = max(0.01, finiteOr(ambientCurveExponent, fallback: 0.55))
    }

    static let standard = AdaptiveBrightnessTuning()

    func sanitized() -> AdaptiveBrightnessTuning {
        AdaptiveBrightnessTuning(
            contentScoreWeights: contentScoreWeights.sanitized(),
            contentAdjustmentRange: contentAdjustmentRange,
            ambientAdjustmentRange: ambientAdjustmentRange,
            darkRoomBiasRange: darkRoomBiasRange,
            ambientCurveExponent: ambientCurveExponent
        )
    }
}

enum AdaptiveBrightnessMode: String, Sendable, Equatable, Codable {
    case adaptive
    case manualOverride
    case disabled
}

enum AdaptiveTransitionState: String, Sendable, Equatable, Codable {
    case initializing
    case steady
    case increasing
    case decreasing
    case manualOverride
    case disabled
}

/// Extra fields intended for the debug menu, not for persistent screen data.
struct AdaptiveBrightnessDebugInfo: Sendable, Equatable, Codable {
    let contentBrightnessScore: Double
    let ambientLightNormalized: Double?
    let contentAdjustment: Double
    let ambientAdjustment: Double
    let darkRoomAdjustment: Double
    let unconstrainedBrightness: Double
    let didClampToBrightnessBounds: Bool
    let smoothingAlpha: Double
    let elapsedTime: TimeInterval
    let hysteresisHeldTarget: Bool
    let wasRateLimited: Bool
    let manualOverrideRemaining: TimeInterval?
    let transitionState: AdaptiveTransitionState
}

/// The result of one engine evaluation. `calculatedBrightness` is the raw
/// model output, while `targetBrightness` is the next safe effective target
/// after hysteresis, smoothing, and rate limiting. It is physical brightness
/// only when the active controller explicitly supports hardware control.
struct AdaptiveBrightnessDecision: Sendable, Equatable, Codable {
    let mode: AdaptiveBrightnessMode
    let calculatedBrightness: Double
    let acceptedBrightness: Double
    let filteredBrightness: Double
    let targetBrightness: Double
    let shouldApplyBrightness: Bool
    let debugInfo: AdaptiveBrightnessDebugInfo
}

/// Output from a target calculator before temporal processing.
struct RawBrightnessCalculation: Sendable, Equatable, Codable {
    let contentBrightnessScore: Double
    let ambientLightNormalized: Double?
    let contentAdjustment: Double
    let ambientAdjustment: Double
    let darkRoomAdjustment: Double
    let unconstrainedBrightness: Double
    let calculatedBrightness: Double
    let didClampToBrightnessBounds: Bool
}

/// A seam for a future learned or personalized target model. The default
/// implementation remains fully deterministic and needs no user data.
protocol AdaptiveBrightnessTargetCalculating: Sendable {
    func calculate(
        for input: AdaptiveBrightnessInput,
        preferences: AdaptiveBrightnessPreferences,
        tuning: AdaptiveBrightnessTuning
    ) -> RawBrightnessCalculation
}

struct DefaultAdaptiveBrightnessTargetCalculator: AdaptiveBrightnessTargetCalculating {
    init() {}

    func calculate(
        for input: AdaptiveBrightnessInput,
        preferences: AdaptiveBrightnessPreferences,
        tuning: AdaptiveBrightnessTuning
    ) -> RawBrightnessCalculation {
        let contentScore = input.screenStatistics.contentBrightnessScore(using: tuning.contentScoreWeights)
        let contentAdjustment = (0.5 - contentScore)
            * tuning.contentAdjustmentRange
            * preferences.contentSensitivity.multiplier

        let ambientNormalized = input.ambientLight.normalizedValue
        let curvedAmbient = ambientNormalized.map { pow($0, tuning.ambientCurveExponent) }
        let ambientAdjustment = curvedAmbient.map {
            ($0 - 0.5) * tuning.ambientAdjustmentRange * preferences.ambientSensitivity.multiplier
        } ?? 0
        // When no public sensor reading exists, darkRoomBias remains an
        // explicit user preference rather than a fabricated ambient estimate.
        // Its default is zero, so content-only mode stays neutral until the
        // person deliberately asks for a darker-room bias.
        let darkRoomAdjustment = curvedAmbient.map {
            -(1 - $0) * preferences.darkRoomBias * tuning.darkRoomBiasRange
        } ?? (-preferences.darkRoomBias * tuning.darkRoomBiasRange)

        let unconstrained = preferences.preferredBrightness
            + contentAdjustment
            + ambientAdjustment
            + darkRoomAdjustment
        let calculated = constrained(unconstrained, to: preferences.brightnessBounds)

        return RawBrightnessCalculation(
            contentBrightnessScore: contentScore,
            ambientLightNormalized: ambientNormalized,
            contentAdjustment: contentAdjustment,
            ambientAdjustment: ambientAdjustment,
            darkRoomAdjustment: darkRoomAdjustment,
            unconstrainedBrightness: unconstrained,
            calculatedBrightness: calculated,
            didClampToBrightnessBounds: abs(calculated - unconstrained) > 0.000_001
        )
    }
}

@inline(__always)
func unitInterval(_ value: Double) -> Double {
    constrained(finiteOr(value, fallback: 0), to: 0...1)
}

@inline(__always)
func constrained(_ value: Double, to bounds: ClosedRange<Double>) -> Double {
    min(max(value, bounds.lowerBound), bounds.upperBound)
}

@inline(__always)
func finiteOr(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? value : fallback
}
