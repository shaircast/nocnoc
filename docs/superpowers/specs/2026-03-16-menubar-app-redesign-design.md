# nocnoc Menubar App Redesign

## Overview

nocnoc is a macOS menubar utility that detects knock patterns on the MacBook chassis via the built-in accelerometer and triggers configurable actions. This redesign transforms the current landing-page-style UI into a practical menubar app with a streamlined dashboard, a preset-based action system, and an auto-calibration wizard.

## Goals

- Make nocnoc function as a menubar app: always present in the menu bar, main window optional for operation
- Replace the complex landing-page UI with a single-screen dashboard
- Introduce a preset library so non-technical users can configure actions without knowing terminal commands
- Add an auto-calibration wizard that sets detection parameters from the user's actual knock patterns
- Preserve the accelerometer waveform visualization that works well today

## Non-goals

- Removing the Dock icon (LSUIElement) — can be added later with a one-line change
- App-specific integrations (Spotify, Slack, etc.) — system-level presets are sufficient
- Drag-and-drop for action slot assignment — click-to-select popup is simpler and sufficient for 3 slots

## Architecture

### App Structure (KnockApp.swift)

Three scenes, modified from current:

| Scene | Current | New |
|-------|---------|-----|
| `WindowGroup` | Landing page (`ContentView`) | Dashboard (`DashboardView`) |
| `MenuBarExtra` | Mini popover (`MenuBarView`) | Same, minor updates |
| `Settings` | Separate settings window | Removed (merged into dashboard) |

### Lifecycle

- App launch: main window (dashboard) opens + menubar icon appears
- First launch: calibration wizard appears as `.sheet` over dashboard
- Close main window: app continues running in menubar
- Menubar popover: "Open nocnoc" reopens main window via `NSApp.activate(ignoringOtherApps: true)` + SwiftUI `@Environment(\.openWindow)` action
- Quit: via menubar popover Quit button or Cmd+Q

### Preserved Components (no changes)

- `SPUAccelerometerService` — IOKit HID interface to AppleSPUHIDDevice
- `WaveformView` — real-time waveform Canvas rendering
- `Theme` — color definitions

### Modified Components

- `KnockApp.swift` — remove Settings scene, add first-launch detection
- `AppSettings.swift` — replace `ActionKind`/`KnockActionConfiguration` with preset-based model, add `hasCompletedCalibration` flag
- `KnockEngine.swift` — update `ActionRunner` to execute preset templates, rename `openSettings()` → `openMainWindow()` using `NSApp.activate(ignoringOtherApps: true)` (remove the `showSettingsWindow:` selector which targets the deleted Settings scene)
- `MenuBarView.swift` — "Open Settings" → "Open nocnoc", add Quit button
- `MotionMonitor.swift` — add `overrideThreshold: Double?` property for calibration wizard to bypass normal threshold

### Deleted Components

- `ContentView.swift` — replaced by `DashboardView`
- `SettingsView.swift` — merged into dashboard

### New Components

- `DashboardView.swift` — main window UI
- `PresetPickerView.swift` — preset selection popup
- `CalibrationWizard.swift` — 4-step calibration flow
- `PresetLibrary.swift` — built-in preset definitions and `ActionPreset` model

## Dashboard Design

Single-screen layout with three zones:

### Top — Action Slots

Three cards arranged horizontally for Single / Double / Triple knock patterns. Each card shows:
- Pattern label (e.g., "Single knock")
- Assigned preset icon (SF Symbol) and name
- Parameter value if applicable (e.g., app name)

Click a card → preset picker popup opens.

**Note:** Action slot cards are disabled while the calibration wizard sheet is open to prevent concurrent `.sheet` presentation conflicts.

### Middle — Waveform Monitor

- Reuses existing `WaveformView` component
- Threshold line visualized on waveform
- Key sensor metrics below: Filtered magnitude, Peak, Sample rate (Hz)
- No per-axis debug bars (X/Y/Z removed from dashboard — available only during calibration)

### Bottom — Calibration & Advanced Settings

- **Default state**: "Recalibrate" button only
- **Disclosure group** "Advanced Settings" (collapsed by default):
  - Power threshold slider (0.03–0.60)
  - Grouping window slider (200–700ms)
  - Cooldown slider (50–300ms)
  - Reset to Defaults button

## Preset System

### Data Model

`ActionPreset` is a runtime-only type constructed from the static `PresetLibrary`. It is never persisted — only `SlotConfiguration` (preset ID + parameter value) is stored in `UserDefaults`. Therefore `ActionPreset` and `CommandTemplate` do not need `Codable` conformance.

```swift
struct ActionPreset: Identifiable, Equatable {
    let id: String              // e.g., "toggle-mute"
    let name: String            // e.g., "Toggle Mute"
    let icon: String            // SF Symbol name
    let category: PresetCategory
    let template: CommandTemplate
}

enum PresetCategory: String, CaseIterable {
    case system     // macOS system controls
    case app        // App & Shortcut launchers
    case advanced   // Terminal command, none
}

enum CommandTemplate: Equatable {
    case fixed(executable: String, arguments: [String])
    case parameterized(executable: String, argumentTemplate: [String], parameter: ParameterSpec)
    case none       // Do Nothing
}

struct ParameterSpec: Equatable {
    let label: String           // "App name"
    let placeholder: String     // "e.g., Spotify"
}

struct SlotConfiguration: Codable, Equatable {
    let presetId: String
    var parameterValue: String  // empty if preset needs no parameter
}
```

At runtime, `KnockEngine` resolves a `SlotConfiguration` to an `ActionPreset` by looking up `presetId` in `PresetLibrary`, then substitutes `parameterValue` into the template's `argumentTemplate` placeholders.

### Built-in Preset Library

**System Controls:**

| ID | Name | Executable | Arguments |
|----|------|-----------|-----------|
| `toggle-mute` | Toggle Mute | `/usr/bin/osascript` | `["-e", "set volume output muted (not (output muted of (get volume settings)))"]` |
| `lock-screen` | Lock Screen | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to keystroke \"q\" using {control down, command down}"]` |
| `toggle-dnd` | Toggle Do Not Disturb | `/usr/bin/shortcuts` | `["run", "Toggle Do Not Disturb"]` |
| `brightness-up` | Brightness Up | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to key code 144"]` |
| `brightness-down` | Brightness Down | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to key code 145"]` |
| `volume-up` | Volume Up | `/usr/bin/osascript` | `["-e", "set volume output volume ((output volume of (get volume settings)) + 10)"]` |
| `volume-down` | Volume Down | `/usr/bin/osascript` | `["-e", "set volume output volume ((output volume of (get volume settings)) - 10)"]` |
| `screenshot` | Screenshot | `/usr/bin/screencapture` | `["-i", "~/Desktop/screenshot.png"]` |
| `media-play-pause` | Play / Pause | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to key code 101"]` |
| `media-next` | Next Track | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to key code 111"]` |
| `media-previous` | Previous Track | `/usr/bin/osascript` | `["-e", "tell app \"System Events\" to key code 100"]` |

**App & Shortcuts (parameterized):**

| ID | Name | Executable | Argument Template | Parameter |
|----|------|-----------|-------------------|-----------|
| `launch-app` | Launch App | `/usr/bin/open` | `["-a", "{parameter}"]` | label: "App name", placeholder: "e.g., Spotify" |
| `run-shortcut` | Run Shortcut | `/usr/bin/shortcuts` | `["run", "{parameter}"]` | label: "Shortcut name", placeholder: "e.g., Toggle Do Not Disturb" |

**Advanced (parameterized):**

| ID | Name | Executable | Argument Template | Parameter |
|----|------|-----------|-------------------|-----------|
| `shell-command` | Terminal Command | `/bin/zsh` | `["-lc", "{parameter}"]` | label: "Shell command", placeholder: "e.g., echo hello" |
| `none` | Do Nothing | — | — | — |

### Preset Picker Popup

Displayed as `.sheet` when an action slot is clicked:

- Search field at top (filters by name)
- Grid of preset tiles grouped by category
- Selecting a preset with a parameter shows inline input field
- Confirm button applies the selection and closes

### Settings Model Migration

`AppSettings` changes:

```swift
// Before
var singleAction: KnockActionConfiguration  // kind + value
var doubleAction: KnockActionConfiguration
var tripleAction: KnockActionConfiguration

// After
var singleSlot: SlotConfiguration   // presetId + parameterValue
var doubleSlot: SlotConfiguration
var tripleSlot: SlotConfiguration
var hasCompletedCalibration: Bool = false
```

Existing `ActionKind` enum and `KnockActionConfiguration` struct are removed. `KnockPattern` enum is preserved.

**Migration strategy:** The existing `UserDefaults` key (`tryknock.settings`) stores the old `AppSettings` format. On decode failure (which will happen when old data is present), `SettingsStore` falls through to the default `AppSettings()` initializer. Default slot values should match the previous hardcoded defaults:
- `singleSlot`: `SlotConfiguration(presetId: "toggle-mute", parameterValue: "")`
- `doubleSlot`: `SlotConfiguration(presetId: "lock-screen", parameterValue: "")`
- `tripleSlot`: `SlotConfiguration(presetId: "run-shortcut", parameterValue: "Open Notes")`

This is a graceful degradation — existing users get the same behavior by default. No explicit migration code is needed because the existing `try?` decode already returns `nil` on failure.

## Calibration Wizard

### Trigger

- First launch (`hasCompletedCalibration == false`): automatically presented as `.sheet`
- Manual: "Recalibrate" button on dashboard

### Flow — 4 Steps

**Steps 1–3: Data Collection**

Each step asks the user to perform a specific knock pattern 3–5 times:

1. **Single knock** — "Knock once on your MacBook" (repeat 3–5 times)
2. **Double knock** — "Knock twice quickly" (repeat 3–5 times)
3. **Triple knock** — "Knock three times quickly" (repeat 3–5 times)

Each step shows:
- Instruction text
- Real-time waveform (reusing `WaveformView`)
- Progress dots showing detected knocks
- "Next" button (enabled when sufficient samples collected)
- "Skip" button (uses defaults for that step)

**Data collected per step:**
- Step 1: Peak magnitudes of each knock → determines power threshold (set to ~60% of average peak, ensuring comfortable detection margin)
- Step 2: Time intervals between consecutive knocks → determines grouping window (average interval × 1.3)
- Step 3: Reinforces step 2 data + determines cooldown (minimum inter-knock interval × 0.8)

**Value clamping:** All computed values are clamped to valid slider ranges before being applied: threshold to [0.03, 0.60], grouping window to [0.20, 0.70] seconds, cooldown to [0.05, 0.30] seconds.

**Implementation note:** During calibration, the wizard sets `MotionMonitor.overrideThreshold = 0.03` to capture all taps regardless of the user's current threshold setting. This is a new optional property on `MotionMonitor` — when non-nil, it overrides `settingsStore.settings.detectionThreshold` in the `KnockDetector.process()` call. The wizard resets it to `nil` on completion or cancellation. The existing `KnockDetector` pattern recognition is NOT used during steps 1–3; the wizard performs its own peak detection on `snapshot.filteredMagnitude`.

**Step 4: Test & Confirm**

- Shows computed values (power threshold, grouping window, cooldown)
- Applies values temporarily to the live detection engine
- User knocks freely; recognized patterns shown with visual feedback
- "Save" → writes to `SettingsStore`, sets `hasCompletedCalibration = true`, resets `overrideThreshold` to `nil`
- "Start Over" → returns to step 1, discards collected data

## MenuBar Popover

Minimal changes from current `MenuBarView`:

```
nocnoc
[last action summary]
[mini waveform]
[monitoring status]  [threshold value]
─────────────
Pause/Resume Monitoring
Open nocnoc              ← was "Open Settings"
Quit                     ← new
```

"Open nocnoc" calls the renamed `engine.openMainWindow()` which uses `NSApp.activate(ignoringOtherApps: true)` to bring the dashboard window to front. Quit calls `NSApp.terminate(nil)`.

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `KnockApp.swift` | Modify | Remove Settings scene, add first-launch detection |
| `DashboardView.swift` | Create | Main dashboard with slots, waveform, settings |
| `PresetPickerView.swift` | Create | Preset selection popup |
| `CalibrationWizard.swift` | Create | 4-step calibration flow |
| `PresetLibrary.swift` | Create | Built-in preset definitions, ActionPreset model |
| `AppSettings.swift` | Modify | Preset-based model, calibration flag, migration-safe defaults |
| `KnockEngine.swift` | Modify | ActionRunner uses preset templates, `openSettings()` → `openMainWindow()` |
| `MenuBarView.swift` | Modify | "Open nocnoc", Quit button |
| `MotionMonitor.swift` | Modify | Add `overrideThreshold: Double?` for calibration |
| `SPUAccelerometerService.swift` | Keep | No changes |
| `WaveformView.swift` | Keep | No changes |
| `Theme.swift` | Keep | No changes |
| `ContentView.swift` | Delete | Replaced by DashboardView |
| `SettingsView.swift` | Delete | Merged into DashboardView |

## Open Questions

None — all design decisions have been validated through the brainstorming session.
