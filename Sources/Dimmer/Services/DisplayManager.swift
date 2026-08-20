import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var builtInDisplay: DisplayInfo?

    var onConfigurationChanged: ((DisplayInfo?) -> Void)?
    private var screenParameterObserver: NSObjectProtocol?
    private var hasDisplayConfigurationCallback = false

    init() {
        screenParameterObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        hasDisplayConfigurationCallback = CGDisplayRegisterReconfigurationCallback(
            Self.displayConfigurationChanged,
            Unmanaged.passUnretained(self).toOpaque()
        ) == .success
        refresh(notify: false)
    }

    func shutdown() {
        if hasDisplayConfigurationCallback {
            CGDisplayRemoveReconfigurationCallback(
                Self.displayConfigurationChanged,
                Unmanaged.passUnretained(self).toOpaque()
            )
            hasDisplayConfigurationCallback = false
        }
        if let screenParameterObserver {
            NotificationCenter.default.removeObserver(screenParameterObserver)
            self.screenParameterObserver = nil
        }
    }

    func refresh(notify: Bool = true) {
        let currentDisplays = NSScreen.screens.compactMap(makeInfo(for:))
        let currentBuiltIn = currentDisplays.first(where: \.isBuiltIn)
        let changed = currentDisplays != displays || currentBuiltIn != builtInDisplay

        displays = currentDisplays
        builtInDisplay = currentBuiltIn

        if notify && changed {
            onConfigurationChanged?(currentBuiltIn)
        }
    }

    private func makeInfo(for screen: NSScreen) -> DisplayInfo? {
        guard let id = displayID(for: screen) else { return nil }
        let mode = CGDisplayCopyDisplayMode(id)
        let width = CGDisplayPixelsWide(id)
        let height = CGDisplayPixelsHigh(id)
        let builtIn = CGDisplayIsBuiltin(id) != 0
        return DisplayInfo(
            id: id,
            name: builtIn ? "Built-in Display" : "External Display",
            isBuiltIn: builtIn,
            pixelWidth: width,
            pixelHeight: height,
            refreshRate: mode?.refreshRate ?? 0,
            frame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    private static let displayConfigurationChanged: CGDisplayReconfigurationCallBack = { _, _, userInfo in
        guard let userInfo else { return }
        let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            manager.refresh()
        }
    }
}
