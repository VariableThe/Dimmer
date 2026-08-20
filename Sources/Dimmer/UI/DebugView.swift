import SwiftUI

struct DebugView: View {
    @EnvironmentObject private var model: DimmerAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dimmer Debug")
                        .font(.title2.bold())
                    Text("Local numeric telemetry only — no screen images are retained.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { model.isShowingDebugPanel = false }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DebugSection("Screen") {
                        MetricRow(title: "Display", value: model.builtInDisplay?.name ?? "None")
                        MetricRow(title: "Resolution", value: model.builtInDisplay?.pixelSizeDescription ?? "—")
                        MetricRow(title: "Refresh rate", value: model.builtInDisplay?.refreshRateDescription ?? "—")
                        MetricRow(title: "Capture sample", value: model.latestAnalysis.map { "\($0.width) × \($0.height), \($0.sampledPixelCount) pixels" } ?? "—")
                    }

                    DebugSection("Content") {
                        let stats = model.latestAnalysis?.statistics
                        MetricRow(title: "Mean", value: luminanceValue(stats?.meanLuminance), monospaced: true)
                        MetricRow(title: "Median", value: luminanceValue(stats?.medianLuminance), monospaced: true)
                        MetricRow(title: "P90 / P95 / P99", value: "\(luminanceValue(stats?.p90Luminance)) / \(luminanceValue(stats?.p95Luminance)) / \(luminanceValue(stats?.p99Luminance))", monospaced: true)
                        MetricRow(title: "Dark / bright", value: "\(brightnessPercent(stats?.darkPixelFraction)) / \(brightnessPercent(stats?.brightPixelFraction))")
                        MetricRow(title: "Content score", value: brightnessPercent(model.contentScore))
                    }

                    DebugSection("Environment") {
                        MetricRow(title: "Ambient light", value: model.ambientDescription)
                    }

                    DebugSection("Brightness") {
                        MetricRow(title: "Current physical", value: model.hardwareBrightnessDescription)
                        MetricRow(title: "Calculated", value: brightnessPercent(model.latestDecision?.calculatedBrightness))
                        MetricRow(title: "Effective target", value: brightnessPercent(model.targetBrightness))
                        MetricRow(title: "Effective overlay", value: brightnessPercent(model.effectiveBrightness))
                    }

                    DebugSection("Engine") {
                        let info = model.latestDecision?.debugInfo
                        MetricRow(title: "Smoothing α", value: info.map { String(format: "%.3f", $0.smoothingAlpha) } ?? "—", monospaced: true)
                        MetricRow(title: "Sensitivity", value: "\(model.preferences.contentSensitivity.rawValue) / \(model.preferences.ambientSensitivity.rawValue)")
                        MetricRow(title: "Transition", value: info?.transitionState.rawValue ?? "—")
                        MetricRow(title: "Hysteresis", value: info?.hysteresisHeldTarget == true ? "Holding" : "Tracking")
                        MetricRow(title: "Rate limited", value: info?.wasRateLimited == true ? "Yes" : "No")
                        MetricRow(title: "Manual override", value: info?.manualOverrideRemaining.map { "\(Int($0.rounded(.up))) s" } ?? "Inactive")
                    }

                    DebugSection("Previous 60 seconds") {
                        HistoryGraph(samples: model.debugHistory)
                            .frame(height: 150)
                        HStack(spacing: 12) {
                            Legend(color: .blue, title: "Content")
                            Legend(color: .orange, title: "Target")
                            Legend(color: .green, title: "Applied")
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 640)
    }
}

private struct DebugSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Legend: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }
}

private struct HistoryGraph: View {
    let samples: [DebugHistorySample]

    var body: some View {
        Canvas { context, size in
            let graphSamples = Array(samples.suffix(180))
            guard graphSamples.count > 1 else {
                let message = Text("Waiting for numerical samples")
                    .font(.caption)
                context.draw(message, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            for fraction in [0.25, 0.5, 0.75] {
                var guide = Path()
                let y = size.height * fraction
                guide.move(to: CGPoint(x: 0, y: y))
                guide.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(guide, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }

            drawSeries(graphSamples.map(\.contentScore), color: .blue, in: context, size: size)
            drawSeries(graphSamples.map(\.targetBrightness), color: .orange, in: context, size: size)
            drawSeries(graphSamples.map(\.appliedBrightness), color: .green, in: context, size: size)
        }
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func drawSeries(
        _ values: [Double],
        color: Color,
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard values.count > 1 else { return }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * CGFloat(1 - unitInterval(value))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 2)
    }
}
