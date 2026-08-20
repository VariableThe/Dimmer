import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenCaptureStatus: Equatable {
    case idle
    case starting
    case capturing
    case needsScreenRecordingPermission
    case failed(String)

    var description: String {
        switch self {
        case .idle: "Stopped"
        case .starting: "Starting capture…"
        case .capturing: "Analyzing locally"
        case .needsScreenRecordingPermission: "Screen Recording permission is required"
        case let .failed(message): message
        }
    }
}

/// Owns a display-wide ScreenCaptureKit stream. It requests a low-resolution
/// stream at the source and passes only numeric frame summaries to the app
/// model. Audio capture is always disabled.
@MainActor
final class ScreenCaptureManager: ObservableObject {
    @Published private(set) var status: ScreenCaptureStatus = .idle {
        didSet { onStatusChanged?(status) }
    }
    @Published private(set) var lastAnalysis: FrameAnalysis?

    var onStatusChanged: ((ScreenCaptureStatus) -> Void)?

    private let analyzer = FrameAnalyzer()
    private var stream: SCStream?
    private var output: ScreenCaptureOutput?
    private var analysisHandler: ((FrameAnalysis) -> Void)?
    private var captureGeneration = UUID()

    func start(
        display: DisplayInfo,
        onAnalysis: @escaping (FrameAnalysis) -> Void
    ) {
        analysisHandler = onAnalysis
        let generation = UUID()
        captureGeneration = generation

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stopCurrentStream(updateStatus: false, onlyIfGeneration: generation)
            guard self.captureGeneration == generation else { return }
            await self.startStream(for: display, generation: generation)
        }
    }

    func stop() {
        let generation = UUID()
        captureGeneration = generation
        Task { @MainActor [weak self] in
            await self?.stopCurrentStream(updateStatus: true, onlyIfGeneration: generation)
        }
    }

    /// A Space transition does not change the selected display. It merely
    /// makes the next screen sample eligible immediately.
    func requestImmediateAnalysis() {
        output?.requestImmediateAnalysis()
    }

    private func startStream(for displayInfo: DisplayInfo, generation: UUID) async {
        guard CGPreflightScreenCaptureAccess() else {
            status = .needsScreenRecordingPermission
            return
        }

        status = .starting
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard captureGeneration == generation else { return }
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayInfo.id }) else {
                status = .failed("The selected built-in display is not available to ScreenCaptureKit.")
                return
            }

            // This keeps Dimmer's fallback overlay and its menu panel out of
            // its own analysis. It does not promise invisibility in every
            // other app's screenshot mechanism.
            let ownProcessID = ProcessInfo.processInfo.processIdentifier
            let ownApplication = shareableContent.applications.filter { app in
                app.processID == ownProcessID
            }
            guard !ownApplication.isEmpty else {
                // Starting without this exclusion would allow the fallback
                // overlay to influence its own luminance measurements. Fail
                // closed and let the model restore normal display output.
                status = .failed("Dimmer could not exclude its own windows from screen analysis. Try reopening the app.")
                return
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplication,
                exceptingWindows: []
            )

            let configuration = streamConfiguration(for: display)
            let output = ScreenCaptureOutput(analyzer: analyzer)
            output.onAnalysis = { [weak self] analysis in
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == generation else { return }
                    self.lastAnalysis = analysis
                    self.analysisHandler?(analysis)
                }
            }
            output.onFailure = { [weak self] errorDescription in
                Task { @MainActor [weak self] in
                    guard let self, self.captureGeneration == generation else { return }
                    self.status = .failed(errorDescription)
                }
            }

            let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
            try stream.addStreamOutput(
                output,
                type: .screen,
                sampleHandlerQueue: output.processingQueue
            )
            self.output = output
            self.stream = stream
            try await stream.startCapture()

            guard captureGeneration == generation else {
                try? await stream.stopCapture()
                return
            }
            status = .capturing
        } catch {
            guard captureGeneration == generation else { return }
            status = .failed(captureErrorDescription(error))
            self.stream = nil
            self.output = nil
        }
    }

    private func stopCurrentStream(
        updateStatus: Bool,
        onlyIfGeneration generation: UUID? = nil
    ) async {
        guard generation == nil || captureGeneration == generation else { return }
        let previousStream = stream
        stream = nil
        output = nil
        if let previousStream {
            try? await previousStream.stopCapture()
        }
        guard generation == nil || captureGeneration == generation else { return }
        if updateStatus {
            status = .idle
            lastAnalysis = nil
        }
    }

    private func streamConfiguration(for display: SCDisplay) -> SCStreamConfiguration {
        let maximumWidth = 360
        let width = max(1, min(maximumWidth, display.width))
        let aspectRatio = Double(display.height) / Double(max(display.width, 1))
        let height = max(1, Int((Double(width) * aspectRatio).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Ask for a known sRGB transfer function so FrameAnalyzer's sRGB →
        // linear-light conversion is well-defined instead of inheriting an
        // HDR/wide-gamut display's color space.
        configuration.colorSpaceName = CGColorSpace.sRGB
        if #available(macOS 15.0, *), let sdr = SCCaptureDynamicRange(rawValue: 0) {
            // `SCCaptureDynamicRangeSDR` is imported as raw value 0 by the
            // current macOS SDK rather than as a Swift enum case.
            configuration.captureDynamicRange = sdr
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 4)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    private func captureErrorDescription(_ error: Error) -> String {
        return "Screen capture failed: \(error.localizedDescription)"
    }
}

/// ScreenCaptureKit invokes this object on `processingQueue`, so all adaptive
/// sampling state remains queue-confined. The stream remains at 4 fps to notice
/// major content changes quickly; fully analyzing it backs off to 1.5 seconds
/// after several stable samples.
private final class ScreenCaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let processingQueue = DispatchQueue(label: "com.dimmer.capture-analysis", qos: .utility)
    var onAnalysis: (@Sendable (FrameAnalysis) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?

    private let analyzer: FrameAnalyzer
    private let immediateAnalysisLock = NSLock()
    private var immediateAnalysisRequested = false
    private var lastAnalysisDate = Date.distantPast
    private var lastContentScore: Double?
    private var stableSampleCount = 0
    private var analysisInterval: TimeInterval = 0.35

    init(analyzer: FrameAnalyzer) {
        self.analyzer = analyzer
    }

    func requestImmediateAnalysis() {
        immediateAnalysisLock.lock()
        immediateAnalysisRequested = true
        immediateAnalysisLock.unlock()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        guard isCompleteFrame(sampleBuffer) else { return }

        let now = Date()
        immediateAnalysisLock.lock()
        let shouldForce = immediateAnalysisRequested
        immediateAnalysisRequested = false
        immediateAnalysisLock.unlock()

        guard shouldForce || now.timeIntervalSince(lastAnalysisDate) >= analysisInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let analysis = analyzer.analyze(pixelBuffer: pixelBuffer) else {
            return
        }

        updateSamplingRate(for: analysis)
        lastAnalysisDate = now
        onAnalysis?(analysis)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?("Screen capture stopped: \(error.localizedDescription)")
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
        let attachment = attachmentArray.first,
        let rawStatus = attachment[.status] as? Int,
        let status = SCFrameStatus(rawValue: rawStatus) else {
            // Some buffers lack the optional attachment dictionary. The
            // stream's screen-output contract still guarantees a valid frame.
            return true
        }
        return status == .complete
    }

    private func updateSamplingRate(for analysis: FrameAnalysis) {
        let score = analysis.statistics.contentBrightnessScore()
        if let lastContentScore, abs(score - lastContentScore) < 0.012 {
            stableSampleCount += 1
        } else {
            stableSampleCount = 0
        }
        lastContentScore = score
        analysisInterval = stableSampleCount >= 5 ? 1.5 : 0.35
    }
}
