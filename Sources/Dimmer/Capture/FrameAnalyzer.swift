import CoreVideo
import Foundation

/// Numerical output of one downsampled frame. It contains no image or pixel
/// buffer reference, which keeps the capture pipeline privacy-preserving.
struct FrameAnalysis: Sendable, Equatable {
    let statistics: ScreenStatistics
    let width: Int
    let height: Int
    let sampledPixelCount: Int
}

/// Converts a small SDR BGRA frame into robust luminance statistics. The
/// caller supplies a downsampled `CVPixelBuffer`; this type never retains it.
struct FrameAnalyzer: Sendable {
    let darkPixelThreshold: Double
    let brightPixelThreshold: Double

    init(darkPixelThreshold: Double = 0.15, brightPixelThreshold: Double = 0.85) {
        let dark = unitInterval(darkPixelThreshold)
        self.darkPixelThreshold = dark
        self.brightPixelThreshold = max(dark, unitInterval(brightPixelThreshold))
    }

    func analyze(pixelBuffer: CVPixelBuffer) -> FrameAnalysis? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        var luminances: [Double] = []
        luminances.reserveCapacity(width * height)

        for row in 0..<height {
            let rowStart = pixels.advanced(by: row * bytesPerRow)
            for column in 0..<width {
                let pixel = rowStart.advanced(by: column * 4)
                // ScreenCaptureKit emits BGRA as requested by
                // ScreenCaptureManager. Convert sRGB to linear light before
                // applying Rec. 709 relative-luminance coefficients.
                let blue = srgbToLinear(Double(pixel[0]) / 255)
                let green = srgbToLinear(Double(pixel[1]) / 255)
                let red = srgbToLinear(Double(pixel[2]) / 255)
                luminances.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
            }
        }

        return analyze(luminances: luminances, width: width, height: height)
    }

    /// Public to the package for deterministic tests and future GPU analyzers.
    /// Values are expected to be linear-light luminance values in `0...1`.
    func analyze(luminances: [Double], width: Int, height: Int) -> FrameAnalysis? {
        guard !luminances.isEmpty, width > 0, height > 0 else { return nil }

        let values = luminances.map(unitInterval)
        let count = Double(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / count
        let sorted = values.sorted()
        let darkFraction = Double(values.lazy.filter { $0 <= darkPixelThreshold }.count) / count
        let brightFraction = Double(values.lazy.filter { $0 >= brightPixelThreshold }.count) / count

        let statistics = ScreenStatistics(
            meanLuminance: mean,
            medianLuminance: percentile(0.5, in: sorted),
            minimumLuminance: sorted[0],
            maximumLuminance: sorted[sorted.count - 1],
            p90Luminance: percentile(0.90, in: sorted),
            p95Luminance: percentile(0.95, in: sorted),
            p99Luminance: percentile(0.99, in: sorted),
            darkPixelFraction: darkFraction,
            brightPixelFraction: brightFraction,
            luminanceVariance: variance,
            darkPixelThreshold: darkPixelThreshold,
            brightPixelThreshold: brightPixelThreshold
        )

        return FrameAnalysis(
            statistics: statistics,
            width: width,
            height: height,
            sampledPixelCount: values.count
        )
    }

    private func percentile(_ fraction: Double, in sortedValues: [Double]) -> Double {
        guard sortedValues.count > 1 else { return sortedValues[0] }
        let position = unitInterval(fraction) * Double(sortedValues.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        let interpolation = position - Double(lowerIndex)
        return sortedValues[lowerIndex] + ((sortedValues[upperIndex] - sortedValues[lowerIndex]) * interpolation)
    }

    private func srgbToLinear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}
