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
- Menubar popover: "Open nocnoc" reopens main window
- Quit: via menubar popover Quit button or Cmd+Q

### Preserved Components (no changes)

- `MotionMonitor` — accelerometer data processing and knock detection
- `SPUAccelerometerService` — IOKit HID interface to AppleSPUHIDDevice
- `WaveformView` — real-time waveform Canvas rendering
- `Theme` — color definitions

### Modified Components

- `KnockApp.swift` — remove Settings scene, add first-launch detection
- `AppSettings.swift` — replace `ActionKind`/`KnockActionConfiguration` with preset-based model, add `hasCompletedCalibration` flag
- `KnockEngine.swift` — update `ActionRunner` to execute preset templates
- `MenuBarView.swift` — "Open Settings" → "Open nocnoc", add Quit button

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

```swift
struct ActionPreset: Identifiable, Codable, Equatable {
    let id: String              // e.g., "toggle-mute"
    let name: String            // e.g., "Toggle Mute"
    let icon: String            // SF Symbol name
    let category: PresetCategory
    let template: CommandTemplate
}

enum PresetCategory: String, Codable, CaseIterable {
    case system     // macOS system controls
    case app        // App & Shortcut launchers
    case advanced   // Terminal command, none
}

enum CommandTemplate: Codable, Equatable {
    case fixed(executable: String, arguments: [String])
    case parameterized(executable: String, argumentTemplate: [String], parameter: ParameterSpec)
}

struct ParameterSpec: Codable, Equatable {
    let label: String           // "App name"
    let placeholder: String     // "e.g., Spotify"
}

struct SlotConfiguration: Codable, Equatable {
    let presetId: String
    var parameterValue: String  // empty if preset needs no parameter
}
```

### Built-in Preset Library

**System Controls:**

| ID | Name | Command |
|----|------|---------|
| `toggle-mute` | Toggle Mute | `osascript -e 'set volume output muted (not (output muted of (get volume settings)))'` |
| `lock-screen` | Lock Screen | `osascript -e 'tell app "System Events" to keystroke "q" using {control down, command down}'` |
| `toggle-dnd` | Toggle Do Not Disturb | `shortcuts run "Toggle Do Not Disturb"` |
| `brightness-up` | Brightness Up | `osascript -e 'tell app "System Events" to key code 144'` |
| `brightness-down` | Brightness Down | `osascript -e 'tell app "System Events" to key code 145'` |
| `volume-up` | Volume Up | `osascript -e 'set volume output volume ((output volume of (get volume settings)) + 10)'` |
| `volume-down` | Volume Down | `osascript -e 'set volume output volume ((output volume of (get volume settings)) - 10)'` |
| `screenshot` | Screenshot | `screencapture -i ~/Desktop/screenshot.png` |
| `media-play-pause` | Play / Pause | `osascript -e 'tell app "System Events" to key code 16 using command down'` |
| `media-next` | Next Track | `osascript -e 'tell app "System Events" to key code 124 using command down'` |
| `media-previous` | Previous Track | `osascript -e 'tell app "System Events" to key code 123 using command down'` |

**App & Shortcuts:**

| ID | Name | Parameter |
|----|------|-----------|
| `launch-app` | Launch App | App name (e.g., "Spotify") |
| `run-shortcut` | Run Shortcut | Shortcut name |

**Advanced:**

| ID | Name | Parameter |
|----|------|-----------|
| `shell-command` | Terminal Command | Shell command (`zsh -lc`) |
| `none` | Do Nothing | — |

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

**Implementation note:** During calibration, the wizard observes `MotionMonitor`'s raw `snapshot.filteredMagnitude` directly with a low temporary threshold (e.g., 0.03) to capture all taps. It does NOT use the existing `KnockDetector` pattern recognition since thresholds haven't been determined yet.

**Step 4: Test & Confirm**

- Shows computed values (power threshold, grouping window, cooldown)
- Applies values temporarily to the live detection engine
- User knocks freely; recognized patterns shown with visual feedback
- "Save" → writes to `SettingsStore`, sets `hasCompletedCalibration = true`
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

"Open nocnoc" activates the app and shows the main window. Quit terminates the app.

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `KnockApp.swift` | Modify | Remove Settings scene, add first-launch detection |
| `DashboardView.swift` | Create | Main dashboard with slots, waveform, settings |
| `PresetPickerView.swift` | Create | Preset selection popup |
| `CalibrationWizard.swift` | Create | 4-step calibration flow |
| `PresetLibrary.swift` | Create | Built-in preset definitions, ActionPreset model |
| `AppSettings.swift` | Modify | Preset-based model, calibration flag |
| `KnockEngine.swift` | Modify | ActionRunner uses preset templates |
| `MenuBarView.swift` | Modify | "Open nocnoc", Quit button |
| `MotionMonitor.swift` | Keep | No changes |
| `SPUAccelerometerService.swift` | Keep | No changes |
| `WaveformView.swift` | Keep | No changes |
| `Theme.swift` | Keep | No changes |
| `ContentView.swift` | Delete | Replaced by DashboardView |
| `SettingsView.swift` | Delete | Merged into DashboardView |

## Open Questions

None — all design decisions have been validated through the brainstorming session.
