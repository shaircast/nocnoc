import Foundation

enum KnockPattern: Int, CaseIterable, Codable, Identifiable {
    case single = 1
    case double = 2
    case triple = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .single: "Knock"
        case .double: "Double knock"
        case .triple: "Triple knock"
        }
    }

    var subtitle: String {
        switch self {
        case .single: "One tap on the chassis"
        case .double: "Two taps in quick succession"
        case .triple: "Three taps in quick succession"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var detectionThreshold: Double = 0.14
    var groupingWindow: Double = 0.40
    var cooldown: Double = 0.12
    var waveformGain: Double = 3.0
    var monitoringEnabled: Bool = true
    var hasCompletedCalibration: Bool = false

    var singleSlot: SlotConfiguration = .init(presetId: "toggle-mute", parameterValue: "")
    var doubleSlot: SlotConfiguration = .init(presetId: "lock-screen", parameterValue: "")
    var tripleSlot: SlotConfiguration = .init(presetId: "none", parameterValue: "")

    func slot(for pattern: KnockPattern) -> SlotConfiguration {
        switch pattern {
        case .single: singleSlot
        case .double: doubleSlot
        case .triple: tripleSlot
        }
    }

    mutating func setSlot(_ slot: SlotConfiguration, for pattern: KnockPattern) {
        switch pattern {
        case .single: singleSlot = slot
        case .double: doubleSlot = slot
        case .triple: tripleSlot = slot
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private let defaultsKey = "tryknock.settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        if
            let data = userDefaults.data(forKey: defaultsKey),
            let decoded = try? decoder.decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    func reset() {
        settings = AppSettings()
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
