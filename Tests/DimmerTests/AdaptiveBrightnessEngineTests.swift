import Foundation
import Testing
@testable import Dimmer

@Suite
struct AdaptiveBrightnessEngineTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test
    func blackContentTargetsHigherBrightnessThanWhiteContent() {
        let black = calculate(ScreenStatistics.uniform(0), preferredBrightness: 0.60)
        let white = calculate(ScreenStatistics.uniform(1), preferredBrightness: 0.60)

        #expect(black.calculatedBrightness > 0.60)
        #expect(white.calculatedBrightness < 0.60)
        #expect(black.calculatedBrightness > white.calculatedBrightness)
    }

    @Test
    func midGrayIsBetweenBlackAndWhite() {
        let black = calculate(ScreenStatistics.uniform(0))
        let gray = calculate(ScreenStatistics.uniform(0.5))
        let white = calculate(ScreenStatistics.uniform(1))

        #expect(black.calculatedBrightness > gray.calculatedBrightness)
        #expect(gray.calculatedBrightness > white.calculatedBrightness)
    }

    @Test
    func tinyWhiteElementDoesNotLookLikeWhiteScreen() {
        let black = calculate(ScreenStatistics.uniform(0))
        let tinyHighlight = calculate(statistics(
            mean: 0.02, median: 0.01, p90: 0.02, p95: 0.03, p99: 0.04,
            dark: 0.99, bright: 0.001
        ))
        let white = calculate(ScreenStatistics.uniform(1))

        #expect(tinyHighlight.calculatedBrightness > white.calculatedBrightness + 0.20)
        #expect(abs(tinyHighlight.calculatedBrightness - black.calculatedBrightness) < 0.04)
    }

    @Test
    func tinyBlackElementDoesNotLookLikeDarkScreen() {
        let white = calculate(ScreenStatistics.uniform(1))
        let tinyShadow = calculate(statistics(
            mean: 0.98, median: 0.99, p90: 1, p95: 1, p99: 1,
            dark: 0.001, bright: 0.99,
            minimum: 0
        ))
        let black = calculate(ScreenStatistics.uniform(0))

        #expect(tinyShadow.calculatedBrightness < black.calculatedBrightness - 0.20)
        #expect(abs(tinyShadow.calculatedBrightness - white.calculatedBrightness) < 0.04)
    }

    @Test
    func darkUIWithBrightTextAndBrightWebpageAreOrderedSensibly() {
        let darkUI = calculate(statistics(
            mean: 0.16, median: 0.08, p90: 0.40, p95: 0.85, p99: 1,
            dark: 0.70, bright: 0.06
        ))
        let brightWebpage = calculate(statistics(
            mean: 0.90, median: 0.96, p90: 0.99, p95: 1, p99: 1,
            dark: 0.01, bright: 0.89
        ))

        #expect(darkUI.calculatedBrightness > brightWebpage.calculatedBrightness)
        #expect(darkUI.debugInfo.contentBrightnessScore < brightWebpage.debugInfo.contentBrightnessScore)
    }

    @Test
    func movieLikeHighlightsDoNotOverridePredominantlyDarkContent() {
        let movie = calculate(statistics(
            mean: 0.26, median: 0.16, p90: 0.65, p95: 0.90, p99: 1,
            dark: 0.53, bright: 0.04
        ))
        let brightWebpage = calculate(statistics(
            mean: 0.90, median: 0.96, p90: 0.99, p95: 1, p99: 1,
            dark: 0.01, bright: 0.89
        ))

        #expect(movie.calculatedBrightness > brightWebpage.calculatedBrightness)
        #expect(movie.debugInfo.contentBrightnessScore < 0.5)
    }

    @Test
    func highAmbientLightRaisesTargetNonlinearly() {
        let screen = ScreenStatistics.uniform(0.5)
        let low = calculate(screen, ambient: .lux(1))
        let high = calculate(screen, ambient: .lux(2_000))

        #expect(high.calculatedBrightness > low.calculatedBrightness)
        #expect(high.debugInfo.ambientLightNormalized != nil)
    }

    @Test
    func unavailableAmbientLightDoesNotInventAnAmbientAdjustment() {
        let decision = calculate(ScreenStatistics.uniform(0.5), ambient: .unavailable)

        #expect(abs(decision.debugInfo.ambientAdjustment) < 0.000_001)
        #expect(abs(decision.debugInfo.darkRoomAdjustment) < 0.000_001)
        #expect(decision.debugInfo.ambientLightNormalized == nil)
    }

    @Test
    func explicitDarkRoomBiasWorksWithoutFabricatingASensorReading() {
        var darkRoomPreferences = preferences()
        darkRoomPreferences.darkRoomBias = 1

        let neutral = evaluate(ScreenStatistics.uniform(0.5), preferences: preferences())
        let biased = evaluate(ScreenStatistics.uniform(0.5), preferences: darkRoomPreferences)

        #expect(biased.calculatedBrightness < neutral.calculatedBrightness)
        #expect(biased.debugInfo.darkRoomAdjustment < 0)
        #expect(biased.debugInfo.ambientLightNormalized == nil)
    }

    @Test
    func minimumAndMaximumBrightnessConstraintsAreRespected() {
        let minimumPreferences = preferences(preferredBrightness: 0, minimum: 0.42, maximum: 1)
        let maximumPreferences = preferences(preferredBrightness: 1, minimum: 0, maximum: 0.58)

        let minDecision = evaluate(ScreenStatistics.uniform(1), preferences: minimumPreferences)
        let maxDecision = evaluate(ScreenStatistics.uniform(0), preferences: maximumPreferences)

        #expect(abs(minDecision.calculatedBrightness - 0.42) < 0.000_001)
        #expect(abs(maxDecision.calculatedBrightness - 0.58) < 0.000_001)
    }

    @Test
    func tightenedBoundsRequestAnApplyWhenCurrentOutputIsOutsideThem() {
        var engine = AdaptiveBrightnessEngine()
        let settings = preferences(preferredBrightness: 0.60, minimum: 0.10, maximum: 0.50)
        let decision = engine.evaluate(
            input(
                ScreenStatistics.uniform(0.5),
                currentEffectiveBrightness: 0.80,
                at: start
            ),
            preferences: settings
        )

        #expect(abs(decision.targetBrightness - 0.50) < 0.000_001)
        #expect(decision.shouldApplyBrightness)
    }

    @Test
    func hysteresisIgnoresSmallContentChanges() {
        var engine = AdaptiveBrightnessEngine()
        var setting = preferences(preferredBrightness: 0.60, hysteresis: 0.04)
        setting.transitionSpeed = .fast

        _ = engine.evaluate(input(ScreenStatistics.uniform(0.5), at: start), preferences: setting)
        let result = engine.evaluate(input(ScreenStatistics.uniform(0.52), at: start.addingTimeInterval(1)), preferences: setting)

        #expect(result.debugInfo.hysteresisHeldTarget)
        #expect(abs(result.acceptedBrightness - 0.60) < 0.000_001)
    }

    @Test
    func suddenTransitionsAreRateLimitedInBothDirections() {
        var engine = AdaptiveBrightnessEngine()
        var setting = preferences(preferredBrightness: 0.60)
        setting.transitionSpeed = .normal

        _ = engine.evaluate(input(ScreenStatistics.uniform(1), at: start), preferences: setting)
        let towardDark = engine.evaluate(input(ScreenStatistics.uniform(0), at: start.addingTimeInterval(0.2)), preferences: setting)
        let towardBright = engine.evaluate(input(ScreenStatistics.uniform(1), at: start.addingTimeInterval(0.4)), preferences: setting)

        #expect(abs(towardDark.targetBrightness - 0.60) <= 0.050_001)
        #expect(abs(towardBright.targetBrightness - towardDark.targetBrightness) <= 0.050_001)
        #expect(towardDark.debugInfo.wasRateLimited)
    }

    @Test
    func manualOverrideTemporarilyPausesAdaptiveChanges() {
        var engine = AdaptiveBrightnessEngine()
        let setting = preferences(manualOverrideDuration: 10)
        engine.recordManualBrightness(0.30, using: setting, at: start)

        let paused = engine.evaluate(input(ScreenStatistics.uniform(0), at: start.addingTimeInterval(5)), preferences: setting)
        let resumed = engine.evaluate(input(ScreenStatistics.uniform(0), at: start.addingTimeInterval(10)), preferences: setting)

        #expect(paused.mode == .manualOverride)
        #expect(abs(paused.targetBrightness - 0.30) < 0.000_001)
        #expect(!paused.shouldApplyBrightness)
        #expect(resumed.mode == .adaptive)
        #expect(resumed.calculatedBrightness > 0.30)
    }

    @Test
    func disabledPreferencesLeaveHardwareBrightnessAlone() {
        var engine = AdaptiveBrightnessEngine()
        var setting = preferences()
        setting.isEnabled = false

        let result = engine.evaluate(input(ScreenStatistics.uniform(0), currentEffectiveBrightness: 0.47, at: start), preferences: setting)

        #expect(result.mode == .disabled)
        #expect(abs(result.targetBrightness - 0.47) < 0.000_001)
        #expect(!result.shouldApplyBrightness)
    }

    private func calculate(
        _ screen: ScreenStatistics,
        preferredBrightness: Double = 0.60,
        ambient: AmbientLightReading = .unavailable
    ) -> AdaptiveBrightnessDecision {
        evaluate(screen, preferences: preferences(preferredBrightness: preferredBrightness), ambient: ambient)
    }

    private func evaluate(
        _ screen: ScreenStatistics,
        preferences: AdaptiveBrightnessPreferences,
        ambient: AmbientLightReading = .unavailable
    ) -> AdaptiveBrightnessDecision {
        var engine = AdaptiveBrightnessEngine()
        return engine.evaluate(input(screen, ambient: ambient, at: start), preferences: preferences)
    }

    private func input(
        _ screen: ScreenStatistics,
        ambient: AmbientLightReading = .unavailable,
        currentEffectiveBrightness: Double = 0.60,
        at timestamp: Date
    ) -> AdaptiveBrightnessInput {
        AdaptiveBrightnessInput(
            screenStatistics: screen,
            ambientLight: ambient,
            currentEffectiveBrightness: currentEffectiveBrightness,
            timestamp: timestamp
        )
    }

    private func preferences(
        preferredBrightness: Double = 0.60,
        minimum: Double = 0.10,
        maximum: Double = 1,
        hysteresis: Double = 0.015,
        manualOverrideDuration: TimeInterval = 90
    ) -> AdaptiveBrightnessPreferences {
        AdaptiveBrightnessPreferences(
            preferredBrightness: preferredBrightness,
            minimumBrightness: minimum,
            maximumBrightness: maximum,
            hysteresisThreshold: hysteresis,
            manualOverrideDuration: manualOverrideDuration
        )
    }

    private func statistics(
        mean: Double,
        median: Double,
        p90: Double,
        p95: Double,
        p99: Double,
        dark: Double,
        bright: Double,
        minimum: Double = 0,
        maximum: Double = 1
    ) -> ScreenStatistics {
        ScreenStatistics(
            meanLuminance: mean,
            medianLuminance: median,
            minimumLuminance: minimum,
            maximumLuminance: maximum,
            p90Luminance: p90,
            p95Luminance: p95,
            p99Luminance: p99,
            darkPixelFraction: dark,
            brightPixelFraction: bright,
            luminanceVariance: 0.1
        )
    }
}
