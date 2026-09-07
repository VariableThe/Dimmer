import AppKit
import SwiftUI

final class DimmerAppDelegate: NSObject, NSApplicationDelegate {
    var onApplyOnce: (() -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: {
            $0.scheme?.lowercased() == "dimmer" && $0.host?.lowercased() == "apply-once"
        }) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onApplyOnce?()
        }
    }
}

@main
struct DimmerApp: App {
    @NSApplicationDelegateAdaptor(DimmerAppDelegate.self) private var appDelegate
    @StateObject private var model: DimmerAppModel

    init() {
        let appModel = DimmerAppModel()
        _model = StateObject(wrappedValue: appModel)
        appDelegate.onApplyOnce = { [weak appModel] in
            appModel?.applyOnce()
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            appModel.start()
        }
    }

    var body: some Scene {
        MenuBarExtra("Dimmer", systemImage: model.preferences.isEnabled ? "sun.max.fill" : "sun.max") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
