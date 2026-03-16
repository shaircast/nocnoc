import Foundation
import simd

struct SensorSnapshot: Equatable {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var magnitude: Double = 0
    var filteredMagnitude: Double = 0
    var threshold: Double = 0
    var sampleRate: Double = 0
    var lastPeak: Double = 0
}

struct KnockEvent: Equatable, Identifiable {
    let id = UUID()
    let pattern: KnockPattern
    let timestamp: Date
    let strength: Double
}

private struct DetectorResult {
    let snapshot: SensorSnapshot
    let event: KnockEvent?
}

private final class KnockDetector {
    private var lowPass = SIMD3<Double>(repeating: 0)
    private var previousSample = SIMD3<Double>(repeating: 0)
    private var lastPeak: Double = 0
    private var hasInitialized = false
    private var recentKnockTimes: [TimeInterval] = []
    private var lastAcceptedImpactTime: TimeInterval = -.infinity
    private var lastTimestamp: TimeInterval?

    func reset() {
        lowPass = SIMD3<Double>(repeating: 0)
        previousSample = SIMD3<Double>(repeating: 0)
        lastPeak = 0
        hasInitialized = false
        recentKnockTimes.removeAll()
        lastAcceptedImpactTime = -.infinity
        lastTimestamp = nil
    }

    func process(sample: SIMD3<Double>, threshold: Double, groupingWindow: Double, cooldown: Double, now: TimeInterval) -> DetectorResult {
        if !hasInitialized {
            lowPass = sample
            previousSample = sample
            hasInitialized = true
            lastTimestamp = now
        }

        let sampleRate: Double
        if let lastTimestamp {
            let deltaTime = max(now - lastTimestamp, 0.000_1)
            sampleRate = 1 / deltaTime
        } else {
            sampleRate = 0
        }
        self.lastTimestamp = now

        lowPass += (sample - lowPass) * 0.08
        let highPass = sample - lowPass
        let jerk = sample - previousSample
        previousSample = sample

        let filteredMagnitude = max(simd_length(highPass), simd_length(jerk) * 0.92)
        let magnitude = simd_length(sample)
        var emittedEvent: KnockEvent?

        if filteredMagnitude > threshold, now - lastAcceptedImpactTime >= cooldown {
            recentKnockTimes.append(now)
            lastAcceptedImpactTime = now
            lastPeak = filteredMagnitude
        }

        // FIRST: emission check (silence >= groupingWindow)
        if let lastKnockTime = recentKnockTimes.last,
           now - lastKnockTime >= groupingWindow,
           !recentKnockTimes.isEmpty
        {
            let count = min(recentKnockTimes.count, 3)
            if let pattern = KnockPattern(rawValue: count) {
                emittedEvent = KnockEvent(pattern: pattern, timestamp: Date(), strength: lastPeak)
            }
            recentKnockTimes.removeAll()
        }

        // THEN: stale entries cleanup (only matters when no emission happened)
        recentKnockTimes = recentKnockTimes.filter { now - $0 <= groupingWindow * 3.0 }

        let snapshot = SensorSnapshot(
            x: sample.x,
            y: sample.y,
            z: sample.z,
            magnitude: magnitude,
            filteredMagnitude: filteredMagnitude,
            threshold: threshold,
            sampleRate: sampleRate,
            lastPeak: lastPeak
        )

        return DetectorResult(snapshot: snapshot, event: emittedEvent)
    }
}

@MainActor
final class MotionMonitor: ObservableObject {
    @Published private(set) var snapshot = SensorSnapshot()
    @Published private(set) var waveform: [Double] = Array(repeating: 0, count: 120)
    @Published private(set) var compatibilityMessage = "Checking accelerometer availability..."
    @Published private(set) var latestEvent: KnockEvent?
    @Published private(set) var isSupported = false
    @Published private(set) var isMonitoring = false

    /// Set by CalibrationWizard to bypass the normal threshold during calibration.
    var overrideThreshold: Double?

    private let settingsStore: SettingsStore
    private let detector = KnockDetector()
    private let accelerometerService = SPUAccelerometerService()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore

        accelerometerService.onSample = { [weak self] sample in
            guard let self else { return }
            let settings = self.settingsStore.settings
            let threshold = self.overrideThreshold ?? settings.detectionThreshold
            let result = self.detector.process(
                sample: SIMD3<Double>(sample.x, sample.y, sample.z),
                threshold: threshold,
                groupingWindow: settings.groupingWindow,
                cooldown: settings.cooldown,
                now: sample.timestamp
            )

            Task { @MainActor in
                self.snapshot = result.snapshot
                self.pushWaveformSample(result.snapshot.filteredMagnitude * settings.waveformGain)
                if let event = result.event {
                    self.latestEvent = event
                }
            }
        }
    }

    func start() {
        guard settingsStore.settings.monitoringEnabled else {
            stop(with: "Monitoring paused")
            return
        }

        do {
            try accelerometerService.start()
            isSupported = true
            isMonitoring = true
            compatibilityMessage = "AppleSPUHID accelerometer live"
        } catch {
            isSupported = false
            isMonitoring = false
            compatibilityMessage = error.localizedDescription
        }
    }

    func stop(with message: String = "Monitoring paused") {
        accelerometerService.stop()
        detector.reset()
        isMonitoring = false
        compatibilityMessage = message
    }

    func reloadForSettingsChange() {
        syncMonitoringState()
    }

    func syncMonitoringState() {
        if settingsStore.settings.monitoringEnabled {
            start()
        } else {
            stop(with: "Monitoring paused")
        }
    }

    private func pushWaveformSample(_ sample: Double) {
        let clamped = min(max(sample, 0), 1.2)
        waveform.append(clamped)
        if waveform.count > 140 {
            waveform.removeFirst(waveform.count - 140)
        }
    }
}
