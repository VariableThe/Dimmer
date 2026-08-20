import AppKit
import SwiftUI

@main
struct DimmerApp: App {
    @StateObject private var model: DimmerAppModel

    init() {
        let appModel = DimmerAppModel()
        _model = StateObject(wrappedValue: appModel)
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
