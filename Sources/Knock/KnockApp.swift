import AppKit
import Combine
import SwiftUI

@main
struct KnockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        Window("nocnoc", id: "main") {
            DashboardView()
                .environmentObject(appModel.settingsStore)
                .environmentObject(appModel.motionMonitor)
                .environmentObject(appModel.engine)
                .environmentObject(appModel.updateChecker)
                .background(
                    WindowObserver { window in
                        appModel.mainWindow = window
                        appModel.activateMainWindow()
                    }
                )
                .frame(minWidth: 700, minHeight: 560)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("nocnoc", systemImage: appModel.menuBarIconName) {
            MenuBarView()
                .environmentObject(appModel)
                .environmentObject(appModel.settingsStore)
                .environmentObject(appModel.motionMonitor)
                .environmentObject(appModel.engine)
                .environmentObject(appModel.updateChecker)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settingsStore: SettingsStore
    let motionMonitor: MotionMonitor
    let engine: KnockEngine
    let updateChecker: UpdateChecker
    @Published private(set) var isMonitoring = false
    @Published private(set) var isSupported = true
    @Published private(set) var recentPattern: KnockPattern?
    weak var mainWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var iconResetWorkItem: DispatchWorkItem?

    var menuBarIconName: String {
        if !isSupported {
            return "exclamationmark.circle"
        }
        if !isMonitoring {
            return "circle.dotted"
        }
        if let recentPattern {
            switch recentPattern {
            case .single:
                return "circle.fill"
            case .double:
                return "circle.circle.fill"
            case .triple:
                return "target"
            }
        }
        return "circle"
    }

    init() {
        let settingsStore = SettingsStore()
        self.settingsStore = settingsStore
        self.motionMonitor = MotionMonitor(settingsStore: settingsStore)
        self.engine = KnockEngine(settingsStore: settingsStore, motionMonitor: motionMonitor)
        self.updateChecker = UpdateChecker()

        updateChecker.startPeriodicChecks()

        engine.$isMonitoring
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isMonitoring = value
                if !value {
                    self?.clearRecentPattern()
                }
            }
            .store(in: &cancellables)

        motionMonitor.$isSupported
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isSupported = value
            }
            .store(in: &cancellables)

        engine.$lastTriggeredPattern
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pattern in
                self?.showRecentPattern(pattern)
            }
            .store(in: &cancellables)

        motionMonitor.start()
    }

    func activateMainWindow() {
        guard let mainWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.collectionBehavior.insert(.moveToActiveSpace)
        mainWindow.orderFrontRegardless()
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func showRecentPattern(_ pattern: KnockPattern) {
        guard isMonitoring, isSupported else { return }
        recentPattern = pattern
        iconResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.recentPattern = nil
        }
        iconResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func clearRecentPattern() {
        iconResetWorkItem?.cancel()
        iconResetWorkItem = nil
        recentPattern = nil
    }
}
