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
