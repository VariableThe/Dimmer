import Foundation

/// Stateful temporal layer around an `AdaptiveBrightnessTargetCalculating`
/// model. Keep one instance per physical display; do not create one per Space.
struct AdaptiveBrightnessEngine: Sendable {
    private let calculator: any AdaptiveBrightnessTargetCalculating
    private let tuning: AdaptiveBrightnessTuning
    private var acceptedBrightness: Double?
    private var filteredBrightness: Double?
    private var lastTimestamp: Date?
    private var manualOverride: ManualOverride?

    init(tuning: AdaptiveBrightnessTuning = .standard) {
        self.init(calculator: DefaultAdaptiveBrightnessTargetCalculator(), tuning: tuning)
    }

    init(
        calculator: any AdaptiveBrightnessTargetCalculating,
        tuning: AdaptiveBrightnessTuning = .standard
    ) {
        self.calculator = calculator
        self.tuning = tuning.sanitized()
    }

    /// Records an explicit user brightness change. The caller should perform
    /// the actual hardware change; evaluations then refrain from fighting it
    /// until the configured pause interval ends.
    mutating func recordManualBrightness(
        _ brightness: Double,
        using preferences: AdaptiveBrightnessPreferences,
        at timestamp: Date = .now
    ) {
        let preferences = preferences.sanitized()
        let manualBrightness = constrained(unitInterval(brightness), to: preferences.brightnessBounds)
        guard preferences.manualOverrideDuration > 0 else {
            clearManualOverride()
            acceptedBrightness = manualBrightness
            filteredBrightness = manualBrightness
            lastTimestamp = timestamp
            return
        }

        manualOverride = ManualOverride(
            brightness: manualBrightness,
            expiresAt: timestamp.addingTimeInterval(preferences.manualOverrideDuration)
        )
        acceptedBrightness = manualBrightness
        filteredBrightness = manualBrightness
        lastTimestamp = timestamp
    }

    mutating func clearManualOverride() {
        manualOverride = nil
    }

    /// Clears temporal state, for example when the selected physical display
    /// changes. The next evaluation begins from its supplied current value.
    mutating func reset() {
        acceptedBrightness = nil
        filteredBrightness = nil
        lastTimestamp = nil
        manualOverride = nil
    }

    mutating func evaluate(
        _ input: AdaptiveBrightnessInput,
        preferences: AdaptiveBrightnessPreferences
    ) -> AdaptiveBrightnessDecision {
        let preferences = preferences.sanitized()
        let suppliedEffectiveBrightness = input.currentEffectiveBrightness
        let currentBrightness = constrained(suppliedEffectiveBrightness, to: preferences.brightnessBounds)

        guard preferences.isEnabled else {
            acceptedBrightness = currentBrightness
            filteredBrightness = currentBrightness
            lastTimestamp = input.timestamp
            manualOverride = nil
            return disabledDecision(currentBrightness: currentBrightness)
        }

        if let override = manualOverride {
            if input.timestamp < override.expiresAt {
                acceptedBrightness = override.brightness
                filteredBrightness = override.brightness
                lastTimestamp = input.timestamp
                return manualOverrideDecision(
                    override,
                    timestamp: input.timestamp,
                    currentBrightness: currentBrightness
                )
            }
            manualOverride = nil
        }

        let raw = calculator.calculate(for: input, preferences: preferences, tuning: tuning)
        // A custom future calculator is allowed, but it cannot bypass the
        // display safety bounds or inject a non-finite target into state.
        let calculatedBrightness = constrained(
            finiteOr(raw.calculatedBrightness, fallback: currentBrightness),
            to: preferences.brightnessBounds
        )
        let customCalculationWasClamped = !raw.calculatedBrightness.isFinite
            || abs(calculatedBrightness - raw.calculatedBrightness) > 0.000_001
        let previousAccepted = acceptedBrightness
        let hysteresisThreshold = preferences.hysteresisThreshold / preferences.contentSensitivity.multiplier
        let heldByHysteresis: Bool
        let nextAccepted: Double

        if let previousAccepted, abs(calculatedBrightness - previousAccepted) < hysteresisThreshold {
            nextAccepted = previousAccepted
            heldByHysteresis = true
        } else {
            nextAccepted = calculatedBrightness
            heldByHysteresis = false
        }

        let previousFiltered = filteredBrightness ?? currentBrightness
        let elapsed = lastTimestamp.map {
            max(0, input.timestamp.timeIntervalSince($0))
        } ?? 0
        let alpha = smoothingAlpha(
            elapsed: elapsed,
            timeConstant: preferences.transitionSpeed.smoothingTimeConstant
        )
        let candidate = previousFiltered + ((nextAccepted - previousFiltered) * alpha)
        let maximumDelta = preferences.transitionSpeed.maximumChangePerSecond * elapsed
        let target = rateLimited(
            candidate,
            from: previousFiltered,
            maximumDelta: maximumDelta,
            bounds: preferences.brightnessBounds
        )
        let wasRateLimited = abs(candidate - target) > 0.000_001

        acceptedBrightness = nextAccepted
        filteredBrightness = target
        lastTimestamp = input.timestamp

        return AdaptiveBrightnessDecision(
            mode: .adaptive,
            calculatedBrightness: calculatedBrightness,
            acceptedBrightness: nextAccepted,
            filteredBrightness: target,
            targetBrightness: target,
            // Compare to the controller's actual current output, not its
            // bounds-clamped proxy. Otherwise a newly tightened maximum (or
            // raised minimum) can appear satisfied while the display remains
            // outside the configured safety range.
            shouldApplyBrightness: abs(target - suppliedEffectiveBrightness) > 0.000_5,
            debugInfo: AdaptiveBrightnessDebugInfo(
                contentBrightnessScore: raw.contentBrightnessScore,
                ambientLightNormalized: raw.ambientLightNormalized,
                contentAdjustment: raw.contentAdjustment,
                ambientAdjustment: raw.ambientAdjustment,
                darkRoomAdjustment: raw.darkRoomAdjustment,
                unconstrainedBrightness: raw.unconstrainedBrightness,
                didClampToBrightnessBounds: raw.didClampToBrightnessBounds || customCalculationWasClamped,
                smoothingAlpha: alpha,
                elapsedTime: elapsed,
                hysteresisHeldTarget: heldByHysteresis,
                wasRateLimited: wasRateLimited,
                manualOverrideRemaining: nil,
                transitionState: transitionState(from: previousFiltered, to: target, elapsed: elapsed)
            )
        )
    }

    private func disabledDecision(currentBrightness: Double) -> AdaptiveBrightnessDecision {
        let debug = AdaptiveBrightnessDebugInfo(
            contentBrightnessScore: 0,
            ambientLightNormalized: nil,
            contentAdjustment: 0,
            ambientAdjustment: 0,
            darkRoomAdjustment: 0,
            unconstrainedBrightness: currentBrightness,
            didClampToBrightnessBounds: false,
            smoothingAlpha: 0,
            elapsedTime: 0,
            hysteresisHeldTarget: false,
            wasRateLimited: false,
            manualOverrideRemaining: nil,
            transitionState: .disabled
        )
        return AdaptiveBrightnessDecision(
            mode: .disabled,
            calculatedBrightness: currentBrightness,
            acceptedBrightness: currentBrightness,
            filteredBrightness: currentBrightness,
            targetBrightness: currentBrightness,
            shouldApplyBrightness: false,
            debugInfo: debug
        )
    }

    private func manualOverrideDecision(
        _ override: ManualOverride,
        timestamp: Date,
        currentBrightness: Double
    ) -> AdaptiveBrightnessDecision {
        let remaining = max(0, override.expiresAt.timeIntervalSince(timestamp))
        let debug = AdaptiveBrightnessDebugInfo(
            contentBrightnessScore: 0,
            ambientLightNormalized: nil,
            contentAdjustment: 0,
            ambientAdjustment: 0,
            darkRoomAdjustment: 0,
            unconstrainedBrightness: override.brightness,
            didClampToBrightnessBounds: false,
            smoothingAlpha: 0,
            elapsedTime: 0,
            hysteresisHeldTarget: true,
            wasRateLimited: false,
            manualOverrideRemaining: remaining,
            transitionState: .manualOverride
        )
        return AdaptiveBrightnessDecision(
            mode: .manualOverride,
            calculatedBrightness: override.brightness,
            acceptedBrightness: override.brightness,
            filteredBrightness: override.brightness,
            targetBrightness: override.brightness,
            shouldApplyBrightness: false,
            debugInfo: debug
        )
    }

    private func smoothingAlpha(elapsed: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard elapsed > 0, timeConstant > 0 else { return 0 }
        return unitInterval(1 - exp(-elapsed / timeConstant))
    }

    private func rateLimited(
        _ candidate: Double,
        from previous: Double,
        maximumDelta: Double,
        bounds: ClosedRange<Double>
    ) -> Double {
        let safeMaximumDelta = max(0, finiteOr(maximumDelta, fallback: 0))
        let delta = candidate - previous
        let limitedDelta = constrained(delta, to: -safeMaximumDelta...safeMaximumDelta)
        return constrained(previous + limitedDelta, to: bounds)
    }

    private func transitionState(
        from previous: Double,
        to current: Double,
        elapsed: TimeInterval
    ) -> AdaptiveTransitionState {
        guard elapsed > 0 else { return .initializing }
        if abs(current - previous) <= 0.000_5 { return .steady }
        return current > previous ? .increasing : .decreasing
    }
}

private struct ManualOverride: Sendable {
    let brightness: Double
    let expiresAt: Date
}
