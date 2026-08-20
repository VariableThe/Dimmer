import SwiftUI

struct MetricRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
        .font(.caption)
    }
}

func brightnessPercent(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int((unitInterval(value) * 100).rounded()))%"
}

func luminanceValue(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.3f", unitInterval(value))
}
