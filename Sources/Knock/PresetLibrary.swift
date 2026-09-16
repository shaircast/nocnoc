import Foundation

// MARK: - Preset Data Model

struct HotkeyModifiers: OptionSet, Codable, Equatable {
    let rawValue: Int

    static let command = HotkeyModifiers(rawValue: 1 << 0)
    static let shift = HotkeyModifiers(rawValue: 1 << 1)
    static let option = HotkeyModifiers(rawValue: 1 << 2)
    static let control = HotkeyModifiers(rawValue: 1 << 3)

    private static let orderedOptions: [(flag: HotkeyModifiers, symbol: String, appleScript: String)] = [
        (.command, "⌘", "command down"),
        (.shift, "⇧", "shift down"),
        (.option, "⌥", "option down"),
        (.control, "⌃", "control down"),
    ]

    var displayPrefix: String {
        Self.orderedOptions
            .filter { contains($0.flag) }
            .map(\.symbol)
            .joined()
    }

    var appleScriptClause: String {
        Self.orderedOptions
            .filter { contains($0.flag) }
            .map(\.appleScript)
            .joined(separator: ", ")
    }
}

struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: Int?
    var keyDisplay: String
    var modifiers: HotkeyModifiers

    init(keyCode: Int? = nil, keyDisplay: String = "", modifiers: HotkeyModifiers = []) {
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.modifiers = modifiers
    }

    var isValid: Bool {
        keyCode != nil && !keyDisplay.isEmpty
    }

    var summary: String {
        guard isValid else { return "" }
        return modifiers.displayPrefix + keyDisplay
    }

    var appleScript: String? {
        guard let keyCode else { return nil }
        let base = "tell application \"System Events\" to key code \(keyCode)"
        let modifiersClause = modifiers.appleScriptClause
        return modifiersClause.isEmpty ? base : "\(base) using {\(modifiersClause)}"
    }
}

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
    case hotkey
    case none
}

struct ActionPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let category: PresetCategory
    let template: CommandTemplate
    let requiresAccessibility: Bool

    init(
        id: String,
        name: String,
        icon: String,
        category: PresetCategory,
        template: CommandTemplate,
        requiresAccessibility: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.category = category
        self.template = template
        self.requiresAccessibility = requiresAccessibility
    }
}

struct SlotConfiguration: Codable, Equatable {
    var presetId: String
    var parameterValue: String
    var hotkey: HotkeyConfiguration?

    init(
        presetId: String,
        parameterValue: String = "",
        hotkey: HotkeyConfiguration? = nil
    ) {
        self.presetId = presetId
        self.parameterValue = parameterValue
        self.hotkey = hotkey
    }

    var detailSummary: String? {
        if let hotkey, hotkey.isValid {
            return hotkey.summary
        }
        return parameterValue.isEmpty ? nil : parameterValue
    }

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
        case .hotkey:
            guard let hotkey = slot.hotkey, let appleScript = hotkey.appleScript else { return nil }
            return (
                executable: "/usr/bin/osascript",
                arguments: ["-e", appleScript],
                summary: "\(preset.name): \(hotkey.summary)"
            )
        case .none:
            return nil
        }
    }

    static func requiresAccessibility(for slot: SlotConfiguration) -> Bool {
        preset(for: slot.presetId)?.requiresAccessibility ?? false
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
                arguments: ["-e", "tell application \"System Events\" to key code 12 using {command down, control down}"]
            ),
            requiresAccessibility: true
        ),
        ActionPreset(
            id: "brightness-up", name: "Brightness Up", icon: "sun.max",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 144"]
            ),
            requiresAccessibility: true
        ),
        ActionPreset(
            id: "brightness-down", name: "Brightness Down", icon: "sun.min",
            category: .system,
            template: .fixed(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"System Events\" to key code 145"]
            ),
            requiresAccessibility: true
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
            id: "send-hotkey", name: "Keyboard Shortcut", icon: "command",
            category: .advanced,
            template: .hotkey,
            requiresAccessibility: true
        ),
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
