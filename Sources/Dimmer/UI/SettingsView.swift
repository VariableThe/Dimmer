import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DimmerAppModel

    var body: some View {
        Form {
            Section("Adaptive Brightness") {
                Toggle("Enable adaptive brightness", isOn: model.preferenceBinding(\.isEnabled))
                SliderRow(
                    title: "Comfort target",
                    value: model.preferenceBinding(\.preferredBrightness),
                    range: 0.10...1.00
                )
                SliderRow(
                    title: "Minimum effective brightness",
                    value: model.preferenceBinding(\.minimumBrightness),
                    range: 0.10...0.80
                )
                SliderRow(
                    title: "Maximum effective brightness",
                    value: model.preferenceBinding(\.maximumBrightness),
                    range: 0.20...1.00
                )
            }

            Section("Response") {
                Picker("Content sensitivity", selection: model.preferenceBinding(\.contentSensitivity)) {
                    ForEach(AdaptiveSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                Picker("Ambient sensitivity", selection: model.preferenceBinding(\.ambientSensitivity)) {
                    ForEach(AdaptiveSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                Picker("Transition speed", selection: model.preferenceBinding(\.transitionSpeed)) {
                    ForEach(BrightnessTransitionSpeed.allCases, id: \.self) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                SliderRow(
                    title: "Dark-room bias",
                    value: model.preferenceBinding(\.darkRoomBias),
                    range: 0...1
                )
                SliderRow(
                    title: "Hysteresis",
                    value: model.preferenceBinding(\.hysteresisThreshold),
                    range: 0...0.08,
                    valueFormat: { String(format: "%.3f", $0) }
                )
            }

            Section("Manual override") {
                Stepper(
                    "Resume after \(Int(model.preferences.manualOverrideDuration)) seconds",
                    value: model.preferenceBinding(\.manualOverrideDuration),
                    in: 0...900,
                    step: 15
                )
            }

            Section("Environment") {
                LabeledContent("Ambient light") {
                    Text(model.ambientDescription)
                        .foregroundStyle(.secondary)
                }
                Text("The built-in MacBook ambient-light sensor has no documented public macOS reading API. Dark-room bias is a user preference, not a sensor estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy & display") {
                LabeledContent("Screen Recording") {
                    Text(model.hasScreenRecordingPermission ? "Granted" : "Not granted")
                        .foregroundStyle(model.hasScreenRecordingPermission ? .green : .orange)
                }
                Button("Open Screen Recording Privacy Settings") {
                    model.openScreenRecordingSettings()
                }
                Text("Dimmer never stores screenshots or sends screen contents off this Mac. External displays are not adjusted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 510)
    }
}

private struct SliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var valueFormat: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(valueFormat(value.wrappedValue))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

private extension AdaptiveSensitivity {
    var title: String { rawValue.capitalized }
}

private extension BrightnessTransitionSpeed {
    var title: String { rawValue.capitalized }
}
