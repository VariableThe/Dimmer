import Testing
@testable import Dimmer

@Suite
struct FrameAnalyzerTests {
    private let analyzer = FrameAnalyzer(darkPixelThreshold: 0.15, brightPixelThreshold: 0.85)

    @Test
    func calculatesDistributionStatisticsFromLinearLuminance() throws {
        let analysis = try #require(analyzer.analyze(
            luminances: [0, 0.25, 0.50, 0.75, 1],
            width: 5,
            height: 1
        ))
        let statistics = analysis.statistics

        #expect(analysis.sampledPixelCount == 5)
        #expect(abs(statistics.meanLuminance - 0.50) < 0.000_001)
        #expect(abs(statistics.medianLuminance - 0.50) < 0.000_001)
        #expect(abs(statistics.p90Luminance - 0.90) < 0.000_001)
        #expect(abs(statistics.p95Luminance - 0.95) < 0.000_001)
        #expect(abs(statistics.p99Luminance - 0.99) < 0.000_001)
        #expect(abs(statistics.darkPixelFraction - 0.20) < 0.000_001)
        #expect(abs(statistics.brightPixelFraction - 0.20) < 0.000_001)
    }

    @Test
    func highlightFractionDoesNotDominateRobustContentScore() throws {
        var darkWithOneHighlight = Array(repeating: 0.02, count: 999)
        darkWithOneHighlight.append(1)
        let mostlyDark = try #require(analyzer.analyze(
            luminances: darkWithOneHighlight,
            width: 100,
            height: 10
        ))
        let bright = try #require(analyzer.analyze(
            luminances: Array(repeating: 0.95, count: 1_000),
            width: 100,
            height: 10
        ))

        #expect(mostlyDark.statistics.contentBrightnessScore() < 0.08)
        #expect(bright.statistics.contentBrightnessScore() > 0.85)
        #expect(mostlyDark.statistics.maximumLuminance == 1)
    }

    @Test
    func rejectsInvalidDimensionsAndNormalizesInputValues() {
        #expect(analyzer.analyze(luminances: [0.5], width: 0, height: 1) == nil)

        let analysis = analyzer.analyze(luminances: [-1, 2], width: 2, height: 1)
        #expect(analysis?.statistics.minimumLuminance == 0)
        #expect(analysis?.statistics.maximumLuminance == 1)
    }
}
