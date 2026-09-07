import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: DimmerAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            permissionCallout
            controls
            currentReadings
            screenStatistics
            manualControl
            footer
        }
        .padding(14)
        .frame(width: 350)
        .sheet(isPresented: $model.isShowingDebugPanel) {
            DebugView()
                .environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: model.preferences.isEnabled ? "sun.max.fill" : "sun.max")
                .font(.title3)
                .foregroundStyle(model.preferences.isEnabled ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Adaptive Brightness")
                    .font(.headline)
                Text(model.captureStatus.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.preferences.isEnabled && model.hasScreenRecordingPermission {
                Image(systemName: model.captureStatus == .capturing ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.captureStatus == .capturing ? .green : .secondary)
            }
        }
    }

    @ViewBuilder
    private var permissionCallout: some View {
        if model.preferences.isEnabled && !model.hasScreenRecordingPermission {
            VStack(alignment: .leading, spacing: 7) {
                Label("Screen Recording is needed for local screen analysis.", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                Text("Dimmer analyzes a small frame locally. It never saves or uploads screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Grant Access") {
                        model.requestScreenRecordingAccess()
                    }
                    Button("Privacy Settings") {
                        model.openScreenRecordingSettings()
                    }
                }
                Text("macOS can require a relaunch after the first grant.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Toggle("Adaptive Brightness", isOn: model.preferenceBinding(\.isEnabled))
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var currentReadings: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            MetricRow(title: "Physical brightness", value: model.hardwareBrightnessDescription)
            MetricRow(title: "Effective overlay", value: brightnessPercent(model.effectiveBrightness))
            MetricRow(title: "Effective target", value: brightnessPercent(model.targetBrightness))
            MetricRow(title: "Content score", value: brightnessPercent(model.contentScore))
            MetricRow(title: "Ambient light", value: model.ambientDescription)
        }
    }

    @ViewBuilder
    private var screenStatistics: some View {
        DisclosureGroup("Current screen statistics") {
            if let statistics = model.latestAnalysis?.statistics {
                VStack(spacing: 4) {
                    MetricRow(title: "Mean / median", value: "\(luminanceValue(statistics.meanLuminance)) / \(luminanceValue(statistics.medianLuminance))", monospaced: true)
                    MetricRow(title: "P90 / P95 / P99", value: "\(luminanceValue(statistics.p90Luminance)) / \(luminanceValue(statistics.p95Luminance)) / \(luminanceValue(statistics.p99Luminance))", monospaced: true)
                    MetricRow(title: "Min / max", value: "\(luminanceValue(statistics.minimumLuminance)) / \(luminanceValue(statistics.maximumLuminance))", monospaced: true)
                    MetricRow(title: "Dark / bright", value: "\(brightnessPercent(statistics.darkPixelFraction)) / \(brightnessPercent(statistics.brightPixelFraction))")
                    MetricRow(title: "Variance", value: luminanceValue(statistics.luminanceVariance), monospaced: true)
                }
                .padding(.top, 4)
            } else {
                Text("Waiting for a captured frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .font(.caption)
    }

    private var manualControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            HStack {
                Text("Manual effective brightness")
                    .font(.caption.weight(.medium))
                Spacer()
                Text(brightnessPercent(model.effectiveBrightness))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { model.effectiveBrightness ?? model.preferences.preferredBrightness },
                    set: { model.setManualBrightness($0) }
                ),
                in: model.preferences.brightnessBounds
            )
            .disabled(!model.preferences.isEnabled)
            if !model.preferences.isEnabled {
                Text("Turn adaptive brightness on to use a manual override. Dimmer has restored the normal display.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Pauses adaptation for \(Int(model.preferences.manualOverrideDuration)) seconds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Resume") {
                    model.clearManualOverride()
                }
                .font(.caption)
                .disabled(!model.preferences.isEnabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("Settings")
            }
            Button("Apply Once") {
                model.applyOnce()
            }
            .disabled(!model.preferences.isEnabled)
            Button("Start Updates") {
                model.startContinuousUpdates()
            }
            .disabled(!model.preferences.isEnabled)
            Button("Debug") {
                model.isShowingDebugPanel = true
            }
            Spacer()
            Button("Quit") {
                model.quit()
            }
        }
        .font(.caption)
    }
}
