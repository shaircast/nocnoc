import SwiftUI

@main
struct KnockApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("nocnoc") {
            DashboardView()
                .environmentObject(appModel.settingsStore)
                .environmentObject(appModel.motionMonitor)
                .environmentObject(appModel.engine)
                .frame(minWidth: 700, minHeight: 560)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("nocnoc", systemImage: appModel.engine.isMonitoring ? "waveform.path.ecg" : "pause.circle") {
            MenuBarView()
                .environmentObject(appModel.settingsStore)
                .environmentObject(appModel.motionMonitor)
                .environmentObject(appModel.engine)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settingsStore: SettingsStore
    let motionMonitor: MotionMonitor
    let engine: KnockEngine

    init() {
        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore
        self.motionMonitor = MotionMonitor(settingsStore: settingsStore)
        self.engine = KnockEngine(settingsStore: settingsStore, motionMonitor: motionMonitor)
        motionMonitor.start()
    }
}
