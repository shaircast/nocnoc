import Combine
import AppKit
import SwiftUI

struct CalibrationWizard: View {
    enum Mode {
        case onboarding
        case calibrationOnly
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var step: Int
    @State private var collector = CalibrationCollector()
    @State private var computedSettings: ComputedCalibration?
    @State private var lastRecognizedPattern: String = "None"
    @State private var settingsBeforeCalibration: AppSettings?
    @State private var accessibilityGranted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
    @State private var automationStatus: AutomationPermission.Status = .notDetermined
    @State private var isRequestingAccessibility = false
    @State private var isRequestingAutomation = false

    init(mode: Mode = .calibrationOnly) {
        self.mode = mode
        _step = State(initialValue: 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footerButtons
        }
        .frame(width: 560, height: isTestStep ? 660 : 600)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
        .onAppear { beginCalibration() }
        .onDisappear { endCalibration() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if mode == .onboarding && step == 1 {
            introStep
        } else if mode == .onboarding && step == 2 {
            permissionsStep
        } else if currentCalibrationStep == 1 {
            collectionStep(
                    title: "Knock once on your MacBook",
                    subtitle: "Repeat 3–5 times. We'll measure the impact strength.",
                    knockCount: collector.singleKnocks.count
                )
        } else if currentCalibrationStep == 2 {
            collectionStep(
                    title: "Knock twice quickly",
                    subtitle: "Repeat 3–5 times. We'll measure the timing between knocks.",
                    knockCount: collector.doubleKnocks.count
                )
        } else if currentCalibrationStep == 3 {
            collectionStep(
                    title: "Knock three times quickly",
                    subtitle: "Repeat 3–5 times. This refines the timing calibration.",
                    knockCount: collector.tripleKnocks.count
                )
        } else if isTestStep {
            testStep
        } else {
            EmptyView()
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(1...totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.accent : Theme.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var totalSteps: Int {
        mode == .onboarding ? 6 : 4
    }

    private var currentCalibrationStep: Int? {
        switch mode {
        case .onboarding:
            switch step {
            case 3: 1
            case 4: 2
            case 5: 3
            default: nil
            }
        case .calibrationOnly:
            switch step {
            case 1: 1
            case 2: 2
            case 3: 3
            default: nil
            }
        }
    }

    private var isTestStep: Bool {
        switch mode {
        case .onboarding:
            step == 6
        case .calibrationOnly:
            step == 4
        }
    }

    // MARK: - Intro Step

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            Text("Welcome to nocnoc")
                .font(.system(size: 30, weight: .bold))

            Text("Knock on your MacBook to run actions without touching the keyboard or trackpad.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.primaryText)

            VStack(alignment: .leading, spacing: 14) {
                onboardingFeatureRow(
                    icon: "waveform.path.ecg",
                    title: "Detect knock patterns",
                    detail: "Single, double, and triple knocks are recognized separately."
                )
                onboardingFeatureRow(
                    icon: "bolt.horizontal.circle",
                    title: "Run system actions fast",
                    detail: "Mute, lock screen, shortcuts, app launch, and custom hotkeys."
                )
                onboardingFeatureRow(
                    icon: "slider.horizontal.3",
                    title: "Calibrate to your knock style",
                    detail: "We tune the threshold and timing so detection feels reliable on your machine."
                )
            }
            .padding(22)
            .background(Theme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("Next, we'll grant the recommended permissions first, then calibrate the knock sensor.")
                .foregroundStyle(Theme.secondaryText)

            Spacer()
        }
        .padding(32)
    }

    private func onboardingFeatureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Permission Step

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Grant Recommended Permissions")
                .font(.title2.weight(.bold))

            Text("These permissions unlock the default Lock Screen action and any shortcut that simulates system key presses.")
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            permissionCard(
                title: "Accessibility",
                subtitle: "Required for Lock Screen, Brightness, and custom keyboard shortcut actions.",
                statusTitle: accessibilityStatusTitle,
                isGranted: accessibilityGranted,
                actionTitle: isRequestingAccessibility ? "Waiting..." : "Grant Accessibility",
                secondaryTitle: accessibilityGranted ? nil : "Open Settings",
                isWorking: isRequestingAccessibility,
                action: requestAccessibilityPermission,
                secondaryAction: {
                    AccessibilityPermission.requestIfNeeded()
                    refreshPermissionStatuses()
                }
            )

            permissionCard(
                title: "System Events Automation",
                subtitle: "Lets nocnoc control System Events so AppleScript-based actions can run without interruption.",
                statusTitle: automationStatusTitle,
                isGranted: automationStatus == .granted,
                actionTitle: isRequestingAutomation ? "Waiting..." : "Allow System Events",
                secondaryTitle: automationStatus == .granted ? nil : "Open Settings",
                isWorking: isRequestingAutomation,
                action: requestAutomationPermission,
                secondaryAction: AutomationPermission.openSystemSettings
            )

            HStack {
                Label("Recommended", systemImage: recommendedPermissionsGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(recommendedPermissionsGranted ? Theme.accent : Theme.warning)
                Spacer()
                if !recommendedPermissionsGranted {
                    Text("You can continue, but default shortcut actions may fail until these are allowed.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 280)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(32)
        .task {
            refreshPermissionStatuses()
        }
    }

    private func permissionCard(
        title: String,
        subtitle: String,
        statusTitle: String,
        isGranted: Bool,
        actionTitle: String,
        secondaryTitle: String?,
        isWorking: Bool,
        action: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isGranted ? Theme.accent : Theme.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isGranted ? Theme.accentSoft : Theme.warningSoft))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Button(actionTitle, action: action)
                    .buttonStyle(.plainHandCursor)
                    .disabled(isWorking)

                if let secondaryTitle {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.plainHandCursor)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(20)
        .background(Theme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
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
                threshold: (computedSettings?.threshold ?? 0.03) * settingsStore.settings.waveformGain
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
        .onReceive(motionMonitor.$latestEvent.compactMap { $0 }) { event in
            if isTestStep {
                lastRecognizedPattern = event.pattern.title
            }
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
            if mode == .onboarding, step == 1 {
                EmptyView()
            } else if isTestStep {
                Button("Start Over") { resetCalibration() }
            } else if mode == .onboarding, step == 2 {
                Button("Back") { goBack() }
            } else {
                Button(currentCalibrationStep == nil ? "Back" : "Skip") {
                    if currentCalibrationStep == nil {
                        goBack()
                    } else {
                        advanceStep()
                    }
                }
            }
            Spacer()
            if isTestStep {
                Button("Close") { dismiss() }
                Button(mode == .onboarding ? "Finish" : "Save") { saveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(nextButtonTitle) { advanceStep() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isNextDisabled)
            }
        }
        .padding(24)
    }

    // MARK: - Logic

    private var currentKnockCount: Int {
        switch currentCalibrationStep {
        case 1: collector.singleKnocks.count
        case 2: collector.doubleKnocks.count
        case 3: collector.tripleKnocks.count
        default: 0
        }
    }

    private var nextButtonTitle: String {
        switch mode {
        case .onboarding where step == 1:
            return "Continue"
        case .onboarding where step == 2:
            return recommendedPermissionsGranted ? "Continue to Calibration" : "Continue Anyway"
        default:
            return "Next"
        }
    }

    private var isNextDisabled: Bool {
        if currentCalibrationStep != nil {
            return currentKnockCount < 3
        }
        return false
    }

    private var recommendedPermissionsGranted: Bool {
        accessibilityGranted && automationStatus == .granted
    }

    private var accessibilityStatusTitle: String {
        accessibilityGranted ? "Allowed" : "Required"
    }

    private var automationStatusTitle: String {
        switch automationStatus {
        case .granted:
            return "Allowed"
        case .notDetermined:
            return "Not Yet Allowed"
        case .denied:
            return "Denied"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func beginCalibration() {
        engine.suppressActions = true
        settingsBeforeCalibration = settingsStore.settings
        if let calibrationStep = currentCalibrationStep {
            startCollection(for: calibrationStep)
        } else {
            motionMonitor.overrideThreshold = nil
        }
    }

    private func endCalibration() {
        engine.suppressActions = false
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
        if isTestStep {
            enterTestStep()
        } else if let calibrationStep = currentCalibrationStep {
            startCollection(for: calibrationStep)
        }
    }

    private func goBack() {
        collector.stopObserving()
        guard step > 1 else { return }
        step -= 1
        computedSettings = nil
        lastRecognizedPattern = "None"

        if let calibrationStep = currentCalibrationStep {
            startCollection(for: calibrationStep)
        } else {
            motionMonitor.overrideThreshold = nil
        }
    }

    private func startCollection(for calibrationStep: Int) {
        motionMonitor.overrideThreshold = 0.03
        collector.startObserving(motionMonitor: motionMonitor, step: calibrationStep)
    }

    private func enterTestStep() {
        let computed = collector.computeSettings()
        computedSettings = computed
        lastRecognizedPattern = "None"
        settingsStore.update { settings in
            settings.detectionThreshold = computed.threshold
            settings.groupingWindow = computed.groupingWindow
            settings.cooldown = computed.cooldown
        }
        motionMonitor.overrideThreshold = nil
    }

    private func resetCalibration() {
        collector.stopObserving()
        collector = CalibrationCollector()
        computedSettings = nil
        lastRecognizedPattern = "None"
        step = mode == .onboarding ? 3 : 1
        if let calibrationStep = currentCalibrationStep {
            startCollection(for: calibrationStep)
        }
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

    private func refreshPermissionStatuses() {
        accessibilityGranted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
        Task {
            automationStatus = await AutomationPermission.currentStatus()
        }
    }

    private func requestAccessibilityPermission() {
        isRequestingAccessibility = true
        _ = AccessibilityPermission.requestIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            accessibilityGranted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
            isRequestingAccessibility = false
        }
    }

    private func requestAutomationPermission() {
        isRequestingAutomation = true
        Task {
            automationStatus = await AutomationPermission.requestIfNeeded()
            isRequestingAutomation = false
        }
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
            threshold: max(0.01, min(threshold, 0.10)),
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
