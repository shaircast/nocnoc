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
private final class CalibrationCollector: Observable {
    struct KnockSample {
        let peak: Double
        let timestamp: TimeInterval
    }

    /// Each entry is one knock-sequence attempt (e.g., one double-knock = 1 entry).
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

        // Grouping window: average inter-knock interval x 1.3
        let avgInterval = interKnockIntervals.isEmpty
            ? 0.40
            : interKnockIntervals.reduce(0, +) / Double(interKnockIntervals.count)
        let groupingWindow = avgInterval * 1.3

        // Cooldown: minimum inter-knock interval x 0.8
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
