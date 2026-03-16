import AppKit
import Combine
import Foundation

@MainActor
final class KnockEngine: ObservableObject {
    @Published private(set) var lastTriggeredPattern: KnockPattern?
    @Published private(set) var lastTriggeredAt: Date?
    @Published private(set) var lastActionSummary = "Waiting for knocks"
    /// Reflects the actual monitoring state from MotionMonitor.
    @Published private(set) var isMonitoring = false

    /// When true, knock events are detected but actions are not executed (e.g. during calibration).
    var suppressActions = false

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

        motionMonitor.$isMonitoring
            .sink { [weak self] value in
                self?.isMonitoring = value
            }
            .store(in: &cancellables)

        settingsStore.$settings
            .map(\.monitoringEnabled)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.motionMonitor.syncMonitoringState()
            }
            .store(in: &cancellables)
    }

    func toggleMonitoring() {
        settingsStore.update { settings in
            settings.monitoringEnabled.toggle()
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    private func handle(event: KnockEvent) {
        lastTriggeredPattern = event.pattern
        lastTriggeredAt = event.timestamp

        guard !suppressActions else { return }

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
                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    completion(.failure(ActionRunnerError.executionFailed(status: process.terminationStatus, stderr: stderrText)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

private enum ActionRunnerError: LocalizedError {
    case executionFailed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let status, let stderr):
            stderr.isEmpty ? "Command exited with status \(status)" : stderr
        }
    }
}
