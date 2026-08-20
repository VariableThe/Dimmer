import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasScreenRecordingPermission = false

    init() {
        refresh()
    }

    func refresh() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }

    /// Shows the system Screen Recording prompt. A successful grant can still
    /// require relaunching the app before ScreenCaptureKit begins streaming.
    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refresh()
        return granted || hasScreenRecordingPermission
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
