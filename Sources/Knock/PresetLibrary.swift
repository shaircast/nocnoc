import Foundation

// MARK: - Preset Data Model

enum PresetCategory: String, CaseIterable, Identifiable {
    case system
    case app
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Controls"
        case .app: "Apps & Shortcuts"
        case .advanced: "Advanced"
        }
    }
}

struct ParameterSpec: Equatable {
    let label: String
    let placeholder: String
}

enum CommandTemplate: Equatable {
    case fixed(executable: String, arguments: [String])
    case parameterized(executable: String, argumentTemplate: [String], parameter: ParameterSpec)
    case none
}

struct ActionPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let category: PresetCategory
    let template: CommandTemplate
}

struct SlotConfiguration: Codable, Equatable {
    var presetId: String
    var parameterValue: String

    static let empty = SlotConfiguration(presetId: "none", parameterValue: "")
}

// MARK: - Built-in Preset Library

enum PresetLibrary {
    static let all: [ActionPreset] = system + apps + advanced

    static func preset(for id: String) -> ActionPreset? {
        all.first { $0.id == id }
    }

    static func presets(in category: PresetCategory) -> [ActionPreset] {
        all.filter { $0.category == category }
    }

    /// Resolve a SlotConfiguration into an executable and arguments.
    /// Returns nil for "none" preset.
    static func resolve(_ slot: SlotConfiguration) -> (executable: String, arguments: [String], summary: String)? {
        guard let preset = preset(for: slot.presetId) else { return nil }
        switch preset.template {
        case .fixed(let executable, let arguments):
            return (executable, arguments, preset.name)
        case .parameterized(let executable, let argumentTemplate, _):
            let arguments = argumentTemplate.map { $0.replacingOccurrences(of: "{parameter}", with: slot.parameterValue) }
            let summary = slot.parameterValue.isEmpty ? preset.name : "\(preset.name): \(slot.parameterValue)"
            return (executable, arguments, summary)
        case .none:
            return nil
        }
    }

    // MARK: - System Controls

    private static let system: [ActionPreset] = [
        ActionPreset(
            id: "toggle-mute", name: "Toggle Mute", icon: "speaker.slash",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "set volume output muted (not (output muted of (get volume settings)))"]
            )
        ),
        ActionPreset(
            id: "lock-screen", name: "Lock Screen", icon: "lock",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
            )
        ),
        ActionPreset(
            id: "toggle-dnd", name: "Do Not Disturb", icon: "moon",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/shortcuts",
                arguments: ["run", "Toggle Do Not Disturb"]
            )
        ),
        ActionPreset(
            id: "brightness-up", name: "Brightness Up", icon: "sun.max",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 144"]
            )
        ),
        ActionPreset(
            id: "brightness-down", name: "Brightness Down", icon: "sun.min",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 145"]
            )
        ),
        ActionPreset(
            id: "volume-up", name: "Volume Up", icon: "speaker.plus",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "set volume output volume ((output volume of (get volume settings)) + 10)"]
            )
        ),
        ActionPreset(
            id: "volume-down", name: "Volume Down", icon: "speaker.minus",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "set volume output volume ((output volume of (get volume settings)) - 10)"]
            )
        ),
        ActionPreset(
            id: "screenshot", name: "Screenshot", icon: "camera.viewfinder",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/screencapture",
                arguments: [
                    "-i",
                    FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: "Desktop/screenshot.png").path(percentEncoded: false),
                ]
            )
        ),
        ActionPreset(
            id: "media-play-pause", name: "Play / Pause", icon: "playpause",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 101"]
            )
        ),
        ActionPreset(
            id: "media-next", name: "Next Track", icon: "forward",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 111"]
            )
        ),
        ActionPreset(
            id: "media-previous", name: "Previous Track", icon: "backward",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 100"]
            )
        ),
    ]

    // MARK: - Apps & Shortcuts

    private static let apps: [ActionPreset] = [
        ActionPreset(
            id: "launch-app", name: "Launch App", icon: "app",
            category: .app,
            template: .parameterized(
                executable: "/usr/bin/open",
                argumentTemplate: ["-a", "{parameter}"],
                parameter: ParameterSpec(label: "App name", placeholder: "e.g., Spotify")
            )
        ),
        ActionPreset(
            id: "run-shortcut", name: "Run Shortcut", icon: "bolt",
            category: .app,
            template: .parameterized(
                executable: "/usr/bin/shortcuts",
                argumentTemplate: ["run", "{parameter}"],
                parameter: ParameterSpec(label: "Shortcut name", placeholder: "e.g., Toggle Do Not Disturb")
            )
        ),
    ]

    // MARK: - Advanced

    private static let advanced: [ActionPreset] = [
        ActionPreset(
            id: "shell-command", name: "Terminal Command", icon: "terminal",
            category: .advanced,
            template: .parameterized(
                executable: "/bin/zsh",
                argumentTemplate: ["-lc", "{parameter}"],
                parameter: ParameterSpec(label: "Shell command", placeholder: "e.g., echo hello")
            )
        ),
        ActionPreset(
            id: "none", name: "Do Nothing", icon: "nosign",
            category: .advanced,
            template: .none
        ),
    ]
}
