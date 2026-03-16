import ServiceManagement
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine
    @EnvironmentObject private var updateChecker: UpdateChecker

    @State private var selectedPattern: KnockPattern?
    @State private var showingCalibration = false
    @State private var showingAdvanced = false
    @State private var launchAtLogin = false

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
        .disabled(showingCalibration)
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
        HStack(spacing: 12) {
            NeonButton(title: "Recalibrate", icon: "arrow.counterclockwise") {
                showingCalibration = true
            }

            NeonButton(
                title: engine.isMonitoring ? "Pause" : "Resume",
                icon: engine.isMonitoring ? "pause" : "play"
            ) {
                engine.toggleMonitoring()
            }

            Spacer()

            Button {
                showingAdvanced.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plainHandCursor)
            .popover(isPresented: $showingAdvanced) {
                advancedSettingsPopover
            }
        }
    }

    private var advancedSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Advanced Settings")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)

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

            Divider()

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
                .onAppear {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }

            if case let .available(version, url) = updateChecker.status {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("v\(version) available", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.info)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Theme.infoSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plainHandCursor)
            }

            Button("Check for Updates") {
                Task { await updateChecker.checkNow() }
            }
            .font(.caption)
            .foregroundStyle(Theme.accent)
            .disabled(updateChecker.status == .checking)

            Button("Reset Defaults") {
                settingsStore.reset()
            }
            .font(.caption)
            .foregroundStyle(Theme.warning)
        }
        .padding(20)
        .frame(width: 320)
        .background(Theme.panelStrong)
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

// MARK: - Neon Button

private struct NeonButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plainHandCursor)
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
                        .foregroundStyle(Theme.accent.opacity(0.5))
                    Text("Choose action")
                        .font(.headline)
                        .foregroundStyle(Theme.accent.opacity(0.5))
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
        .buttonStyle(.plainHandCursor)
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
