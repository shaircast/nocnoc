import AppKit
import Combine
import Foundation

@MainActor
final class KnockEngine: ObservableObject {
    @Published private(set) var lastTriggeredPattern: KnockPattern?
    @Published private(set) var lastTriggeredAt: Date?
    @Published private(set) var lastActionSummary = "Waiting for knocks"
    @Published private(set) var isMonitoring = false

    private let settingsStore: SettingsStore
    private let motionMonitor: MotionMonitor
    private let runner = ActionRunner()

    init(settingsStore: SettingsStore, motionMonitor: MotionMonitor) {
        self.settingsStore = settingsStore
        self.motionMonitor = motionMonitor

        motionMonitor.$latestEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .sink { [weak self] settings in
                self?.isMonitoring = settings.monitoringEnabled
                self?.motionMonitor.reloadForSettingsChange()
            }
            .store(in: &cancellables)
    }

    func toggleMonitoring() {
        settingsStore.update { settings in
            settings.monitoringEnabled.toggle()
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private var cancellables: Set<AnyCancellable> = []

    private func handle(event: KnockEvent) {
        lastTriggeredPattern = event.pattern
        lastTriggeredAt = event.timestamp

        let slot = settingsStore.settings.slot(for: event.pattern)
        guard let resolved = PresetLibrary.resolve(slot) else {
            lastActionSummary = "\(event.pattern.title): no action"
            return
        }

        runner.run(executable: resolved.executable, arguments: resolved.arguments) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.lastActionSummary = "\(event.pattern.title): \(resolved.summary)"
                case .failure(let error):
                    self?.lastActionSummary = "\(event.pattern.title): \(error.localizedDescription)"
                }
            }
        }
    }
}

private final class ActionRunner {
    func run(executable: String, arguments: [String], completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(ActionRunnerError.executionFailed(status: process.terminationStatus)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

private enum ActionRunnerError: LocalizedError {
    case executionFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let status):
            "Command exited with status \(status)"
        }
    }
}
