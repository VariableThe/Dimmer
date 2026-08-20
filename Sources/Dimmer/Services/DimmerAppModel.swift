import AppKit
import Combine
import Foundation
import SwiftUI

struct DebugHistorySample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let contentScore: Double
    let calculatedBrightness: Double
    let targetBrightness: Double
    let appliedBrightness: Double
}

/// Main-actor coordinator for the capture, deterministic engine, controller,
/// permissions, and menu-bar UI. It retains only numerical analysis results.
@MainActor
final class DimmerAppModel: ObservableObject {
    @Published private(set) var preferences: AdaptiveBrightnessPreferences
    @Published private(set) var builtInDisplay: DisplayInfo?
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var hasScreenRecordingPermission: Bool
    @Published private(set) var captureStatus: ScreenCaptureStatus = .idle
    @Published private(set) var latestAnalysis: FrameAnalysis?
    @Published private(set) var latestDecision: AdaptiveBrightnessDecision?
    @Published private(set) var appliedBrightness: Double?
    @Published private(set) var lastError: String?
    @Published private(set) var debugHistory: [DebugHistorySample] = []
    @Published var isShowingDebugPanel = false

    let ambientLightManager = AmbientLightManager()

    private let permissionManager: PermissionManager
    private let displayManager: DisplayManager
    private let captureManager: ScreenCaptureManager
    private let brightnessController: FallbackBrightnessController
    private var engine = AdaptiveBrightnessEngine()
    private var hasStarted = false
    private var workspaceObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    init() {
        let permissionManager = PermissionManager()
        let displayManager = DisplayManager()
        let captureManager = ScreenCaptureManager()

        self.permissionManager = permissionManager
        self.displayManager = displayManager
        self.captureManager = captureManager
        self.brightnessController = FallbackBrightnessController()
        self.preferences = BrightnessSettingsStore.load()
        self.builtInDisplay = displayManager.builtInDisplay
        self.displays = displayManager.displays
        self.hasScreenRecordingPermission = permissionManager.hasScreenRecordingPermission

        displayManager.onConfigurationChanged = { [weak self] display in
            self?.handleDisplayConfigurationChanged(display)
        }
        captureManager.onStatusChanged = { [weak self] status in
            self?.handleCaptureStatusChanged(status)
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureManager.requestImmediateAnalysis()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.shutdown()
            }
        }
    }

    var brightnessCapabilities: BrightnessControllerCapabilities {
        brightnessController.capabilities
    }

    var effectiveBrightness: Double? {
        appliedBrightness ?? brightnessController.currentEffectiveBrightness()
    }

    var contentScore: Double? {
        latestDecision?.debugInfo.contentBrightnessScore
            ?? latestAnalysis?.statistics.contentBrightnessScore()
    }

    var targetBrightness: Double? {
        latestDecision?.targetBrightness
    }

    var hardwareBrightnessDescription: String {
        brightnessCapabilities.canReadHardwareBrightness
            ? "Available"
            : "Unavailable (public API)"
    }

    var ambientDescription: String {
        switch ambientLightManager.reading {
        case .unavailable:
            ambientLightManager.statusDescription
        case let .normalized(value):
            "\(Int(unitInterval(value) * 100))%"
        case let .lux(value):
            "\(Int(max(0, value))) lux"
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        displayManager.refresh(notify: false)
        builtInDisplay = displayManager.builtInDisplay
        displays = displayManager.displays
        refreshPermissions()
    }

    func refreshPermissions() {
        let previouslyGranted = hasScreenRecordingPermission
        permissionManager.refresh()
        hasScreenRecordingPermission = permissionManager.hasScreenRecordingPermission
        if hasScreenRecordingPermission, preferences.isEnabled {
            let captureIsRunning = captureStatus == .capturing || captureStatus == .starting
            if !previouslyGranted || !captureIsRunning {
                startCaptureIfPossible()
            }
        } else if !hasScreenRecordingPermission, preferences.isEnabled {
            captureManager.stop()
            restoreNormalDisplay()
            captureStatus = .needsScreenRecordingPermission
        }
    }

    func requestScreenRecordingAccess() {
        _ = permissionManager.requestScreenRecordingAccess()
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        permissionManager.openScreenRecordingSettings()
    }

    func retryCapture() {
        guard preferences.isEnabled else { return }
        permissionManager.refresh()
        hasScreenRecordingPermission = permissionManager.hasScreenRecordingPermission
        guard hasScreenRecordingPermission else {
            captureStatus = .needsScreenRecordingPermission
            return
        }
        startCaptureIfPossible()
    }

    func updatePreferences(_ update: (inout AdaptiveBrightnessPreferences) -> Void) {
        let wasEnabled = preferences.isEnabled
        var candidate = preferences
        update(&candidate)
        preferences = normalized(candidate)
        BrightnessSettingsStore.save(preferences)

        if wasEnabled != preferences.isEnabled {
            if preferences.isEnabled {
                startCaptureIfPossible()
            } else {
                captureManager.stop()
                restoreNormalDisplay()
            }
        }

        enforceEffectiveBrightnessBounds()
        evaluateLatestFrameIfPossible()
    }

    func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<AdaptiveBrightnessPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { [weak self] value in
                self?.updatePreferences { settings in
                    settings[keyPath: keyPath] = value
                }
            }
        )
    }

    func setManualBrightness(_ brightness: Double) {
        guard preferences.isEnabled else { return }
        guard let display = builtInDisplay else {
            lastError = "No built-in display is available."
            return
        }

        let requested = constrained(brightness, to: preferences.brightnessBounds)
        do {
            try brightnessController.prepare(for: display)
            try brightnessController.setEffectiveBrightness(requested)
            engine.recordManualBrightness(requested, using: preferences)
            appliedBrightness = requested
            lastError = nil
            appendDebugSample(
                contentScore: contentScore ?? 0,
                calculated: requested,
                target: requested,
                applied: requested
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearManualOverride() {
        engine.clearManualOverride()
        evaluateLatestFrameIfPossible()
    }

    func quit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    func shutdown() {
        brightnessController.deactivate()
        captureManager.stop()
        displayManager.shutdown()
    }

    private func startCaptureIfPossible(preservingEffectiveBrightness: Bool = false) {
        guard hasStarted, preferences.isEnabled else { return }
        guard hasScreenRecordingPermission else {
            captureStatus = .needsScreenRecordingPermission
            restoreNormalDisplay()
            return
        }
        guard let display = builtInDisplay else {
            captureStatus = .failed("No built-in display is currently available; external displays are intentionally unsupported.")
            restoreNormalDisplay()
            return
        }

        do {
            let preservedBrightness = preservingEffectiveBrightness ? effectiveBrightness : nil
            try brightnessController.prepare(for: display)
            if let preservedBrightness {
                try brightnessController.setEffectiveBrightness(preservedBrightness)
                appliedBrightness = preservedBrightness
            }
            lastError = nil
            startCapture(for: display)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startCapture(for display: DisplayInfo) {
        captureManager.start(display: display) { [weak self] analysis in
            self?.receive(analysis)
        }
    }

    private func receive(_ analysis: FrameAnalysis) {
        latestAnalysis = analysis
        evaluateLatestFrameIfPossible()
    }

    private func evaluateLatestFrameIfPossible() {
        guard preferences.isEnabled, let analysis = latestAnalysis else { return }
        let currentEffectiveBrightness = brightnessController.currentEffectiveBrightness() ?? appliedBrightness ?? 1
        let input = AdaptiveBrightnessInput(
            screenStatistics: analysis.statistics,
            ambientLight: ambientLightManager.reading,
            currentEffectiveBrightness: currentEffectiveBrightness
        )
        let decision = engine.evaluate(input, preferences: preferences)
        latestDecision = decision

        var applied = currentEffectiveBrightness
        if decision.shouldApplyBrightness {
            do {
                try brightnessController.setEffectiveBrightness(decision.targetBrightness)
                applied = decision.targetBrightness
                appliedBrightness = applied
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
        appendDebugSample(
            contentScore: decision.debugInfo.contentBrightnessScore,
            calculated: decision.calculatedBrightness,
            target: decision.targetBrightness,
            applied: applied
        )
    }

    private func handleDisplayConfigurationChanged(_ display: DisplayInfo?) {
        let previousDisplay = builtInDisplay
        builtInDisplay = display
        displays = displayManager.displays

        // Reconfigure the stream and overlay in place when this remains the
        // same physical panel. This avoids a visible full-brightness flash
        // while, for example, an external monitor is connected or the display
        // arrangement changes.
        if previousDisplay?.id == display?.id, display != nil {
            startCaptureIfPossible(preservingEffectiveBrightness: true)
            return
        }

        latestAnalysis = nil
        captureManager.stop()
        restoreNormalDisplay()
        startCaptureIfPossible()
    }

    private func handleCaptureStatusChanged(_ status: ScreenCaptureStatus) {
        if !hasScreenRecordingPermission, preferences.isEnabled {
            captureStatus = .needsScreenRecordingPermission
            return
        }
        captureStatus = status
        guard case let .failed(message) = status else { return }
        lastError = message
        // A capture failure must not strand the person behind an automatic
        // fallback overlay. They can explicitly retry from the menu panel.
        restoreNormalDisplay()
    }

    private func restoreNormalDisplay() {
        brightnessController.deactivate()
        engine.reset()
        latestDecision = nil
        appliedBrightness = nil
    }

    private func enforceEffectiveBrightnessBounds() {
        guard preferences.isEnabled,
              let current = brightnessController.currentEffectiveBrightness() else {
            return
        }
        let bounded = constrained(current, to: preferences.brightnessBounds)
        guard abs(bounded - current) > 0.000_5 else { return }
        do {
            try brightnessController.setEffectiveBrightness(bounded)
            appliedBrightness = bounded
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func appendDebugSample(
        contentScore: Double,
        calculated: Double,
        target: Double,
        applied: Double
    ) {
        let now = Date()
        debugHistory.append(DebugHistorySample(
            timestamp: now,
            contentScore: unitInterval(contentScore),
            calculatedBrightness: unitInterval(calculated),
            targetBrightness: unitInterval(target),
            appliedBrightness: unitInterval(applied)
        ))
        let cutoff = now.addingTimeInterval(-60)
        debugHistory.removeAll { $0.timestamp < cutoff }
    }

    private func normalized(_ candidate: AdaptiveBrightnessPreferences) -> AdaptiveBrightnessPreferences {
        AdaptiveBrightnessPreferences(
            isEnabled: candidate.isEnabled,
            preferredBrightness: candidate.preferredBrightness,
            minimumBrightness: candidate.minimumBrightness,
            maximumBrightness: candidate.maximumBrightness,
            contentSensitivity: candidate.contentSensitivity,
            ambientSensitivity: candidate.ambientSensitivity,
            transitionSpeed: candidate.transitionSpeed,
            darkRoomBias: candidate.darkRoomBias,
            hysteresisThreshold: candidate.hysteresisThreshold,
            manualOverrideDuration: candidate.manualOverrideDuration
        )
    }
}

private enum BrightnessSettingsStore {
    private static let key = "adaptiveBrightnessPreferences"

    static func load() -> AdaptiveBrightnessPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let preferences = try? JSONDecoder().decode(AdaptiveBrightnessPreferences.self, from: data) else {
            return AdaptiveBrightnessPreferences()
        }
        return preferences
    }

    static func save(_ preferences: AdaptiveBrightnessPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
