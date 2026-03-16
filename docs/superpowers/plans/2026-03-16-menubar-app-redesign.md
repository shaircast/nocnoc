# nocnoc Menubar App Redesign — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform nocnoc from a landing-page-style app into a practical menubar app with a preset-based action system and auto-calibration wizard.

**Architecture:** Rewrite the UI layer (dashboard + preset picker + calibration wizard) while preserving the working core engine (SPUAccelerometerService, KnockDetector, WaveformView). The data model migrates from `ActionKind`/`KnockActionConfiguration` to a `PresetLibrary`/`SlotConfiguration` system. All changes are in a single Swift Package target.

**Tech Stack:** Swift 6.2, SwiftUI, macOS 15+, IOKit (existing)

**Spec:** `docs/superpowers/specs/2026-03-16-menubar-app-redesign-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Knock/PresetLibrary.swift` | Create | `ActionPreset`, `CommandTemplate`, `PresetCategory`, `ParameterSpec`, `SlotConfiguration` types + static preset registry |
| `Sources/Knock/AppSettings.swift` | Rewrite | `KnockPattern` (kept) + `AppSettings` with `SlotConfiguration` slots + `SettingsStore` (kept) — removes `ActionKind`, `KnockActionConfiguration` |
| `Sources/Knock/MotionMonitor.swift` | Modify | Add `overrideThreshold: Double?`, update `onSample` to use it |
| `Sources/Knock/KnockEngine.swift` | Rewrite | Preset-based `ActionRunner`, `openMainWindow()`, slot resolution |
| `Sources/Knock/DashboardView.swift` | Create | Main window: action slot cards, waveform monitor, advanced settings |
| `Sources/Knock/PresetPickerView.swift` | Create | Sheet: search, categorized grid, parameter input |
| `Sources/Knock/CalibrationWizard.swift` | Create | Sheet: 4-step calibration flow with data collection |
| `Sources/Knock/MenuBarView.swift` | Modify | "Open nocnoc", Quit button |
| `Sources/Knock/KnockApp.swift` | Modify | Remove Settings scene, swap ContentView → DashboardView |
| `Sources/Knock/ContentView.swift` | Delete | Replaced by DashboardView |
| `Sources/Knock/SettingsView.swift` | Delete | Merged into DashboardView |

**Note:** Since all files are in a single Swift target, the type-system changes (removing `ActionKind`/`KnockActionConfiguration`, adding `SlotConfiguration`) cascade to every file that references them. Tasks 1–5 must all be completed before the first successful `swift build`. Each task within that range is still an atomic unit of work — just not independently buildable.

---

## Chunk 1: Data Layer + Core Swap

### Task 1: Create PresetLibrary.swift

**Files:**
- Create: `Sources/Knock/PresetLibrary.swift`

- [ ] **Step 1: Create the preset data model and built-in library**

Write `Sources/Knock/PresetLibrary.swift` with the following content:

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Knock/PresetLibrary.swift
git commit -m "feat: add PresetLibrary with built-in action presets"
```

---

### Task 2: Rewrite AppSettings.swift

**Files:**
- Modify: `Sources/Knock/AppSettings.swift`

- [ ] **Step 1: Replace the file contents**

Rewrite `Sources/Knock/AppSettings.swift`. Keep `KnockPattern` (used by MotionMonitor and KnockEngine). Remove `ActionKind` and `KnockActionConfiguration`. Update `AppSettings` to use `SlotConfiguration`. Keep `SettingsStore` unchanged (its `try?` decode handles migration automatically).

```swift
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

    // Migration-safe defaults matching previous hardcoded behavior
    var singleSlot: SlotConfiguration = .init(presetId: "toggle-mute", parameterValue: "")
    var doubleSlot: SlotConfiguration = .init(presetId: "lock-screen", parameterValue: "")
    var tripleSlot: SlotConfiguration = .init(presetId: "run-shortcut", parameterValue: "Open Notes")

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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Knock/AppSettings.swift
git commit -m "feat: migrate AppSettings to SlotConfiguration model"
```

---

### Task 3: Update MotionMonitor.swift

**Files:**
- Modify: `Sources/Knock/MotionMonitor.swift`

- [ ] **Step 1: Add overrideThreshold property**

Add after line 114 (`@Published private(set) var isMonitoring = false`):

```swift
    /// Set by CalibrationWizard to bypass the normal threshold during calibration.
    var overrideThreshold: Double?
```

- [ ] **Step 2: Update onSample to capture overrideThreshold as local**

In the `init` method, change the `onSample` closure (lines 123–142). The `overrideThreshold` property is `@MainActor`-isolated, so it must be captured as a local constant before crossing the actor boundary — the same pattern already used for `settings`:

```swift
// Before (lines 124–128):
            guard let self else { return }
            let settings = self.settingsStore.settings
            let result = self.detector.process(
                sample: SIMD3<Double>(sample.x, sample.y, sample.z),
                threshold: settings.detectionThreshold,

// After:
            guard let self else { return }
            let settings = self.settingsStore.settings
            let threshold = self.overrideThreshold ?? settings.detectionThreshold
            let result = self.detector.process(
                sample: SIMD3<Double>(sample.x, sample.y, sample.z),
                threshold: threshold,
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Knock/MotionMonitor.swift
git commit -m "feat: add overrideThreshold to MotionMonitor for calibration"
```

---

### Task 4: Rewrite KnockEngine.swift

**Files:**
- Modify: `Sources/Knock/KnockEngine.swift`

- [ ] **Step 1: Replace the file contents**

Rewrite `Sources/Knock/KnockEngine.swift`. The `ActionRunner` now resolves `SlotConfiguration` via `PresetLibrary.resolve()`. `openSettings()` becomes `openMainWindow()`.

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Knock/KnockEngine.swift
git commit -m "feat: rewrite KnockEngine with preset-based ActionRunner"
```

---

### Task 5: Scaffold DashboardView + update KnockApp + update MenuBarView + delete old files

This task makes all the remaining changes needed for a successful build. The DashboardView is a minimal stub that will be fleshed out in Chunk 2.

**Files:**
- Create: `Sources/Knock/DashboardView.swift`
- Modify: `Sources/Knock/KnockApp.swift`
- Modify: `Sources/Knock/MenuBarView.swift`
- Delete: `Sources/Knock/ContentView.swift`
- Delete: `Sources/Knock/SettingsView.swift`

- [ ] **Step 1: Create stub DashboardView.swift**

```swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine

    @State private var selectedPattern: KnockPattern?
    @State private var showingCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("nocnoc")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Dashboard — coming next")
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(32)
        }
        .background(
            LinearGradient(
                colors: [Theme.pageTop, Theme.pageBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(Theme.primaryText)
        .sheet(isPresented: $showingCalibration) {
            Text("Calibration Wizard — coming soon")
                .frame(width: 500, height: 400)
        }
        .onAppear {
            if !settingsStore.settings.hasCompletedCalibration {
                showingCalibration = true
            }
        }
    }
}
```

- [ ] **Step 2: Update KnockApp.swift**

Replace `Sources/Knock/KnockApp.swift` with:

```swift
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
```

- [ ] **Step 3: Update MenuBarView.swift**

Replace `Sources/Knock/MenuBarView.swift` with:

```swift
import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("nocnoc")
                .font(.title2.weight(.bold))

            Text(engine.lastActionSummary)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            WaveformView(values: motionMonitor.waveform, threshold: settingsStore.settings.detectionThreshold * settingsStore.settings.waveformGain)
                .frame(height: 80)
                .padding(10)
                .background(Theme.darkPanel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Label(engine.isMonitoring ? "Monitoring" : "Paused", systemImage: engine.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                Spacer()
                Text("T \(settingsStore.settings.detectionThreshold.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(.body, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

            Divider()

            Button(engine.isMonitoring ? "Pause Monitoring" : "Resume Monitoring") {
                engine.toggleMonitoring()
            }

            Button("Open nocnoc") {
                engine.openMainWindow()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
    }
}
```

- [ ] **Step 4: Delete old files**

```bash
rm Sources/Knock/ContentView.swift Sources/Knock/SettingsView.swift
```

- [ ] **Step 5: Build check**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold DashboardView, update app structure, delete old UI"
```

---

## Chunk 2: Dashboard UI

### Task 6: Build full DashboardView

**Files:**
- Modify: `Sources/Knock/DashboardView.swift`

- [ ] **Step 1: Replace DashboardView.swift with full implementation**

Replace `Sources/Knock/DashboardView.swift` with the complete dashboard. Three sections: action slots (top), waveform (middle), calibration + advanced settings (bottom).

```swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine

    @State private var selectedPattern: KnockPattern?
    @State private var showingCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                actionSlotsSection
                waveformSection
                calibrationSection
            }
            .padding(32)
        }
        .background(
            LinearGradient(
                colors: [Theme.pageTop, Theme.pageBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(Theme.primaryText)
        .sheet(item: $selectedPattern) { pattern in
            PresetPickerView(pattern: pattern) { slot in
                settingsStore.update { settings in
                    settings.setSlot(slot, for: pattern)
                }
            }
        }
        .sheet(isPresented: $showingCalibration) {
            CalibrationWizard()
                .environmentObject(settingsStore)
                .environmentObject(motionMonitor)
        }
        .onAppear {
            if !settingsStore.settings.hasCompletedCalibration {
                showingCalibration = true
            }
        }
    }

    // MARK: - Action Slots

    private var actionSlotsSection: some View {
        HStack(spacing: 16) {
            ForEach(KnockPattern.allCases) { pattern in
                ActionSlotCard(
                    pattern: pattern,
                    slot: settingsStore.settings.slot(for: pattern)
                ) {
                    if !showingCalibration {
                        selectedPattern = pattern
                    }
                }
            }
        }
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            WaveformView(
                values: motionMonitor.waveform,
                threshold: settingsStore.settings.detectionThreshold * settingsStore.settings.waveformGain
            )
            .frame(height: 180)
            .padding(18)
            .background(Theme.darkPanel)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 16) {
                SensorMetric(title: "Filtered", value: motionMonitor.snapshot.filteredMagnitude)
                SensorMetric(title: "Peak", value: motionMonitor.snapshot.lastPeak)
                SensorMetric(title: "Hz", value: motionMonitor.snapshot.sampleRate)
                Spacer()
                Label(engine.isMonitoring ? "Monitoring" : "Paused",
                      systemImage: engine.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(28)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }

    // MARK: - Calibration & Advanced Settings

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Recalibrate") {
                    showingCalibration = true
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(engine.isMonitoring ? "Pause Monitoring" : "Resume Monitoring") {
                    engine.toggleMonitoring()
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup("Advanced Settings") {
                VStack(alignment: .leading, spacing: 18) {
                    SliderRow(
                        title: "Detection threshold",
                        value: binding(\.detectionThreshold),
                        range: 0.03...0.60,
                        step: 0.01,
                        format: .number.precision(.fractionLength(2))
                    )
                    SliderRow(
                        title: "Grouping window",
                        value: binding(\.groupingWindow),
                        range: 0.20...0.70,
                        step: 0.01,
                        suffix: "ms",
                        transform: { Int($0 * 1000) }
                    )
                    SliderRow(
                        title: "Knock cooldown",
                        value: binding(\.cooldown),
                        range: 0.05...0.30,
                        step: 0.01,
                        suffix: "ms",
                        transform: { Int($0 * 1000) }
                    )

                    Button("Reset Defaults") {
                        settingsStore.reset()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 12)
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

// MARK: - Action Slot Card

private struct ActionSlotCard: View {
    let pattern: KnockPattern
    let slot: SlotConfiguration
    let onTap: () -> Void

    private var preset: ActionPreset? {
        PresetLibrary.preset(for: slot.presetId)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(pattern.title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                if let preset {
                    Image(systemName: preset.icon)
                        .font(.title2)
                    Text(preset.name)
                        .font(.headline)
                    if !slot.parameterValue.isEmpty {
                        Text(slot.parameterValue)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "plus.circle.dashed")
                        .font(.title2)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Choose action")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(18)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Components

private struct SensorMetric: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(value.formatted(.number.precision(.fractionLength(3))))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
        }
    }
}

private struct SliderRow<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let step: V.Stride
    var format: FloatingPointFormatStyle<Double>? = nil
    var suffix: String? = nil
    var transform: ((V) -> any CustomStringConvertible)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if let transform {
                    Text("\(String(describing: transform(value))) \(suffix ?? "")")
                        .font(.system(.body, design: .monospaced))
                } else if let format {
                    Text(Double(value).formatted(format))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
```

- [ ] **Step 2: Build check**

Run: `swift build 2>&1 | tail -5`
Expected: Will fail because `PresetPickerView` and `CalibrationWizard` don't exist yet. That's OK — we create them next.

- [ ] **Step 3: Commit**

```bash
git add Sources/Knock/DashboardView.swift
git commit -m "feat: build full DashboardView with slots, waveform, settings"
```

---

### Task 7: Create PresetPickerView

**Files:**
- Create: `Sources/Knock/PresetPickerView.swift`

- [ ] **Step 1: Write PresetPickerView.swift**

```swift
import SwiftUI

struct PresetPickerView: View {
    let pattern: KnockPattern
    let onSelect: (SlotConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedPreset: ActionPreset?
    @State private var parameterValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(PresetCategory.allCases) { category in
                        let presets = filteredPresets(in: category)
                        if !presets.isEmpty {
                            categorySection(category: category, presets: presets)
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose action for \(pattern.title)")
                .font(.title3.weight(.semibold))
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(24)
    }

    // MARK: - Category Section

    private func categorySection(category: PresetCategory, presets: [ActionPreset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title)
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(presets) { preset in
                    PresetTile(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id
                    ) {
                        selectedPreset = preset
                        parameterValue = ""
                    }
                }
            }

            if let selected = selectedPreset, selected.category == category,
               case .parameterized(_, _, let param) = selected.template {
                TextField(param.label, text: $parameterValue, prompt: Text(param.placeholder))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Apply") {
                guard let preset = selectedPreset else { return }
                let slot = SlotConfiguration(presetId: preset.id, parameterValue: parameterValue)
                onSelect(slot)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPreset == nil || needsParameter && parameterValue.isEmpty)
        }
        .padding(24)
    }

    // MARK: - Helpers

    private var needsParameter: Bool {
        guard let preset = selectedPreset else { return false }
        if case .parameterized = preset.template { return true }
        return false
    }

    private func filteredPresets(in category: PresetCategory) -> [ActionPreset] {
        let presets = PresetLibrary.presets(in: category)
        if searchText.isEmpty { return presets }
        return presets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Preset Tile

private struct PresetTile: View {
    let preset: ActionPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                Text(preset.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(10)
            .background(isSelected ? Theme.accentSoft : Theme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Knock/PresetPickerView.swift
git commit -m "feat: add PresetPickerView with search and categorized grid"
```

---

### Task 8: Create CalibrationWizard

**Files:**
- Create: `Sources/Knock/CalibrationWizard.swift`

- [ ] **Step 1: Write CalibrationWizard.swift**

```swift
import Combine
import SwiftUI

struct CalibrationWizard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var collector = CalibrationCollector()
    @State private var computedSettings: ComputedCalibration?
    @State private var lastRecognizedPattern: String = "None"
    @State private var settingsBeforeCalibration: AppSettings?

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            Divider()

            Group {
                switch step {
                case 1: collectionStep(
                    title: "Knock once on your MacBook",
                    subtitle: "Repeat 3–5 times. We'll measure the impact strength.",
                    knockCount: collector.singleKnocks.count
                )
                case 2: collectionStep(
                    title: "Knock twice quickly",
                    subtitle: "Repeat 3–5 times. We'll measure the timing between knocks.",
                    knockCount: collector.doubleKnocks.count
                )
                case 3: collectionStep(
                    title: "Knock three times quickly",
                    subtitle: "Repeat 3–5 times. This refines the timing calibration.",
                    knockCount: collector.tripleKnocks.count
                )
                case 4: testStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerButtons
        }
        .frame(width: 520, height: 460)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
        .onAppear { beginCalibration() }
        .onDisappear { endCalibration() }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.accent : Theme.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Collection Step

    private func collectionStep(title: String, subtitle: String, knockCount: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            WaveformView(
                values: motionMonitor.waveform,
                threshold: 0.03 * settingsStore.settings.waveformGain
            )
            .frame(height: 120)
            .padding(14)
            .background(Theme.darkPanel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Text("Detected:")
                    .foregroundStyle(Theme.secondaryText)
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < knockCount ? Theme.accent : Theme.border)
                        .frame(width: 12, height: 12)
                }
            }
            Spacer()
        }
    }

    // MARK: - Test Step

    private var testStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Calibration complete!")
                .font(.title2.weight(.bold))

            if let computed = computedSettings {
                VStack(alignment: .leading, spacing: 8) {
                    calibrationRow("Power threshold", value: computed.threshold.formatted(.number.precision(.fractionLength(2))))
                    calibrationRow("Grouping window", value: "\(Int(computed.groupingWindow * 1000)) ms")
                    calibrationRow("Cooldown", value: "\(Int(computed.cooldown * 1000)) ms")
                }
                .padding(18)
                .background(Theme.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Knock freely to test these settings")
                .foregroundStyle(Theme.secondaryText)

            WaveformView(
                values: motionMonitor.waveform,
                threshold: (computedSettings?.threshold ?? 0.14) * settingsStore.settings.waveformGain
            )
            .frame(height: 100)
            .padding(14)
            .background(Theme.darkPanel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)

            Text("Last recognized: \(lastRecognizedPattern)")
                .font(.headline)
            Spacer()
        }
    }

    private func calibrationRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            if step == 4 {
                Button("Start Over") { resetCalibration() }
            } else {
                Button("Skip") { advanceStep() }
            }
            Spacer()
            if step == 4 {
                Button("Save") { saveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { advanceStep() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentKnockCount < 3)
            }
        }
        .padding(24)
    }

    // MARK: - Logic

    private var currentKnockCount: Int {
        switch step {
        case 1: collector.singleKnocks.count
        case 2: collector.doubleKnocks.count
        case 3: collector.tripleKnocks.count
        default: 0
        }
    }

    private func beginCalibration() {
        settingsBeforeCalibration = settingsStore.settings
        motionMonitor.overrideThreshold = 0.03
        collector.startObserving(motionMonitor: motionMonitor, step: step)
    }

    private func endCalibration() {
        motionMonitor.overrideThreshold = nil
        collector.stopObserving()
        // Restore original settings if user didn't explicitly save
        if let original = settingsBeforeCalibration {
            settingsStore.update { settings in
                settings.detectionThreshold = original.detectionThreshold
                settings.groupingWindow = original.groupingWindow
                settings.cooldown = original.cooldown
            }
        }
    }

    private func advanceStep() {
        collector.stopObserving()
        step += 1
        if step == 4 {
            let computed = collector.computeSettings()
            computedSettings = computed
            // Apply computed settings temporarily for testing
            settingsStore.update { settings in
                settings.detectionThreshold = computed.threshold
                settings.groupingWindow = computed.groupingWindow
                settings.cooldown = computed.cooldown
            }
            motionMonitor.overrideThreshold = nil
            // Listen for pattern recognition during test
            collector.startTestObserving(motionMonitor: motionMonitor) { pattern in
                lastRecognizedPattern = pattern
            }
        } else {
            collector.startObserving(motionMonitor: motionMonitor, step: step)
        }
    }

    private func resetCalibration() {
        collector.stopObserving()
        collector = CalibrationCollector()
        computedSettings = nil
        lastRecognizedPattern = "None"
        step = 1
        motionMonitor.overrideThreshold = 0.03
        collector.startObserving(motionMonitor: motionMonitor, step: step)
    }

    private func saveAndDismiss() {
        settingsBeforeCalibration = nil // prevent endCalibration from reverting
        if let computed = computedSettings {
            settingsStore.update { settings in
                settings.detectionThreshold = computed.threshold
                settings.groupingWindow = computed.groupingWindow
                settings.cooldown = computed.cooldown
                settings.hasCompletedCalibration = true
            }
        }
        motionMonitor.overrideThreshold = nil
        collector.stopObserving()
        dismiss()
    }
}

// MARK: - Calibration Data Collector

@MainActor
private class CalibrationCollector {
    struct KnockSample {
        let peak: Double
        let timestamp: TimeInterval
    }

    /// Each entry is one knock-sequence attempt (e.g., one double-knock = 1 entry).
    /// Peaks from that sequence are averaged for threshold computation.
    var singleKnocks: [KnockSample] = []
    var doubleKnocks: [KnockSample] = []
    var tripleKnocks: [KnockSample] = []

    private var cancellable: AnyCancellable?
    private var pendingPeaks: [KnockSample] = []
    private var lastPeakTime: TimeInterval = 0
    private let peakCooldown: TimeInterval = 0.08
    /// After this interval of silence, pending peaks are grouped into one knock-sequence.
    private let sequenceTimeout: TimeInterval = 0.6
    private var currentStep: Int = 1

    func startObserving(motionMonitor: MotionMonitor, step: Int) {
        currentStep = step
        pendingPeaks = []
        cancellable = motionMonitor.$snapshot
            .sink { @MainActor [weak self] snapshot in
                self?.processSample(snapshot)
            }
    }

    func startTestObserving(motionMonitor: MotionMonitor, onPattern: @escaping @MainActor (String) -> Void) {
        cancellable = motionMonitor.$latestEvent
            .compactMap { $0 }
            .sink { @MainActor event in
                onPattern(event.pattern.title)
            }
    }

    func stopObserving() {
        flushPendingPeaks()
        cancellable?.cancel()
        cancellable = nil
    }

    private func processSample(_ snapshot: SensorSnapshot) {
        let now = ProcessInfo.processInfo.systemUptime
        let magnitude = snapshot.filteredMagnitude

        // Check if pending peaks should be flushed (silence > sequenceTimeout)
        if !pendingPeaks.isEmpty, let lastPending = pendingPeaks.last,
           now - lastPending.timestamp > sequenceTimeout {
            flushPendingPeaks()
        }

        // Detect peaks above the low calibration threshold
        guard magnitude > 0.03, now - lastPeakTime > peakCooldown else { return }
        lastPeakTime = now
        pendingPeaks.append(KnockSample(peak: magnitude, timestamp: now))
    }

    /// Group pending peaks into one knock-sequence attempt.
    private func flushPendingPeaks() {
        guard !pendingPeaks.isEmpty else { return }
        let maxPeak = pendingPeaks.map(\.peak).max() ?? 0
        let firstTimestamp = pendingPeaks.first!.timestamp
        let sequence = KnockSample(peak: maxPeak, timestamp: firstTimestamp)
        let intervals = zip(pendingPeaks, pendingPeaks.dropFirst()).map { $1.timestamp - $0.timestamp }

        switch currentStep {
        case 1: if singleKnocks.count < 5 { singleKnocks.append(sequence) }
        case 2:
            if doubleKnocks.count < 5 { doubleKnocks.append(sequence) }
            interKnockIntervals.append(contentsOf: intervals)
        case 3:
            if tripleKnocks.count < 5 { tripleKnocks.append(sequence) }
            interKnockIntervals.append(contentsOf: intervals)
        default: break
        }
        pendingPeaks = []
    }

    /// Intervals between individual peaks within double/triple knock sequences.
    private var interKnockIntervals: [TimeInterval] = []

    func computeSettings() -> ComputedCalibration {
        flushPendingPeaks()

        // Power threshold: 60% of average peak from step 1 (single knocks only)
        let peaks = singleKnocks.isEmpty
            ? (doubleKnocks + tripleKnocks).map(\.peak)
            : singleKnocks.map(\.peak)
        let avgPeak = peaks.isEmpty ? 0.14 : peaks.reduce(0, +) / Double(peaks.count)
        let threshold = avgPeak * 0.6

        // Grouping window: average inter-knock interval × 1.3
        let avgInterval = interKnockIntervals.isEmpty
            ? 0.40
            : interKnockIntervals.reduce(0, +) / Double(interKnockIntervals.count)
        let groupingWindow = avgInterval * 1.3

        // Cooldown: minimum inter-knock interval × 0.8
        let minInterval = interKnockIntervals.min() ?? 0.12
        let cooldown = minInterval * 0.8

        // Clamp to valid ranges
        return ComputedCalibration(
            threshold: max(0.03, min(threshold, 0.60)),
            groupingWindow: max(0.20, min(groupingWindow, 0.70)),
            cooldown: max(0.05, min(cooldown, 0.30))
        )
    }
}

struct ComputedCalibration {
    let threshold: Double
    let groupingWindow: Double
    let cooldown: Double
}
```

- [ ] **Step 2: Build check**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Knock/CalibrationWizard.swift
git commit -m "feat: add CalibrationWizard with 4-step calibration flow"
```

---

## Chunk 3: Integration & Final Build

### Task 9: Final build verification and manual test

- [ ] **Step 1: Full clean build**

Run: `swift build 2>&1 | tail -10`
Expected: `Build complete!`

If there are compilation errors, fix them. Common issues:
- Swift 6 `Sendable` warnings: mark data types as `Sendable` if needed
- `@MainActor` isolation issues in closures: ensure proper isolation annotations

- [ ] **Step 2: Run the app to verify it launches**

Run: `swift run &` — verify:
1. Main window (dashboard) appears
2. Menubar icon appears
3. Calibration wizard sheet appears (first launch)
4. Close main window → app stays in menubar
5. "Open nocnoc" from menubar reopens window
6. "Quit" from menubar terminates app

Kill the app after testing: `kill %1` or Cmd+Q.

- [ ] **Step 3: Final commit with all files**

```bash
git add -A
git commit -m "feat: complete nocnoc menubar app redesign

- Dashboard with 3 action slots, live waveform, advanced settings
- Preset library with 14 built-in macOS system actions
- Preset picker with search and categorized grid
- Calibration wizard with 4-step flow (collect, test, save)
- Menubar popover with monitoring toggle and quit
- Removed old landing page UI and separate settings window"
```
