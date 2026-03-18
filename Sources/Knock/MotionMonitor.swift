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
    var noiseFloor: Double = 0
    var motionLevel: Double = 0
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

private struct RecentSample {
    let timestamp: TimeInterval
    let filteredMagnitude: Double
    let highPassMagnitude: Double
    let jerkMagnitude: Double
    let lowPass: SIMD3<Double>
    let lowFrequencyStep: Double
}

private final class KnockDetector {
    private static let preImpactQuietWindow: TimeInterval = 0.28
    private static let motionWindow: TimeInterval = 0.40
    private static let impulseWindow: TimeInterval = 0.14
    private static let historyWindow: TimeInterval = 1.5
    private static let quietTailExclusion: TimeInterval = 0.03
    private static let motionTailExclusion: TimeInterval = 0.07
    private static let motionLockoutDuration: TimeInterval = 0.9

    private var lowPass = SIMD3<Double>(repeating: 0)
    private var previousSample = SIMD3<Double>(repeating: 0)
    private var previousLowPass = SIMD3<Double>(repeating: 0)
    private var lastPeak: Double = 0
    private var hasInitialized = false
    private var recentKnockTimes: [TimeInterval] = []
    private var lastAcceptedImpactTime: TimeInterval = -.infinity
    private var lastTimestamp: TimeInterval?
    private var noiseFloor: Double = 0.01
    private var motionLockoutUntil: TimeInterval = -.infinity
    private var history: [RecentSample] = []

    func reset() {
        lowPass = SIMD3<Double>(repeating: 0)
        previousSample = SIMD3<Double>(repeating: 0)
        previousLowPass = SIMD3<Double>(repeating: 0)
        lastPeak = 0
        hasInitialized = false
        recentKnockTimes.removeAll()
        lastAcceptedImpactTime = -.infinity
        lastTimestamp = nil
        noiseFloor = 0.01
        motionLockoutUntil = -.infinity
        history.removeAll()
    }

    func process(sample: SIMD3<Double>, threshold: Double, groupingWindow: Double, cooldown: Double, now: TimeInterval) -> DetectorResult {
        if !hasInitialized {
            lowPass = sample
            previousSample = sample
            previousLowPass = sample
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
        let lowFrequencyStep = simd_length(lowPass - previousLowPass)
        previousLowPass = lowPass
        let highPass = sample - lowPass
        let jerk = sample - previousSample
        previousSample = sample

        let highPassMagnitude = simd_length(highPass)
        let jerkMagnitude = simd_length(jerk)
        let filteredMagnitude = max(highPassMagnitude, jerkMagnitude * 0.92)
        let magnitude = simd_length(sample)
        var emittedEvent: KnockEvent?

        appendHistory(
            RecentSample(
                timestamp: now,
                filteredMagnitude: filteredMagnitude,
                highPassMagnitude: highPassMagnitude,
                jerkMagnitude: jerkMagnitude,
                lowPass: lowPass,
                lowFrequencyStep: lowFrequencyStep
            ),
            now: now
        )

        let adaptiveThreshold = updateAdaptiveThreshold(baseThreshold: threshold, signal: filteredMagnitude)
        let sequenceIsOpen = (recentKnockTimes.last.map { now - $0 <= groupingWindow } ?? false)
        let quietWindow = recentSamples(within: Self.preImpactQuietWindow, now: now, excludingTail: Self.quietTailExclusion)
        let quietAverage = averageFilteredMagnitude(in: quietWindow)
        let quietMax = quietWindow.map(\.filteredMagnitude).max() ?? 0
        let motionContext = recentSamples(
            within: Self.motionWindow,
            now: now,
            excludingTail: Self.motionTailExclusion
        )
        let lowFrequencyMotion = averageLowFrequencyStep(in: motionContext)
        let orientationDrift = orientationDrift(in: motionContext, currentLowPass: lowPass)

        if shouldEnterMotionLockout(
            lowFrequencyMotion: lowFrequencyMotion,
            orientationDrift: orientationDrift,
            threshold: adaptiveThreshold,
            sequenceIsOpen: sequenceIsOpen
        ) {
            motionLockoutUntil = max(motionLockoutUntil, now + Self.motionLockoutDuration)
        }

        let isInMotionLockout = now < motionLockoutUntil
        let impulseDuration = durationAboveThreshold(
            in: recentSamples(within: Self.impulseWindow, now: now),
            threshold: adaptiveThreshold * 0.55,
            fallbackSampleInterval: sampleRate > 0 ? 1 / sampleRate : 0.01
        )

        let baselineQuiet = quietAverage < adaptiveThreshold * 0.28 && quietMax < adaptiveThreshold * 0.72
        let isSharpImpulse = jerkMagnitude > adaptiveThreshold * 0.70 || jerkMagnitude > highPassMagnitude * 0.90
        let briefImpulse = impulseDuration <= (sequenceIsOpen ? 0.11 : 0.08)
        let passesSequenceGate = sequenceIsOpen || baselineQuiet

        if filteredMagnitude > adaptiveThreshold,
           now - lastAcceptedImpactTime >= cooldown,
           !isInMotionLockout,
           passesSequenceGate,
           isSharpImpulse,
           briefImpulse
        {
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
            threshold: adaptiveThreshold,
            sampleRate: sampleRate,
            lastPeak: lastPeak,
            noiseFloor: noiseFloor,
            motionLevel: max(lowFrequencyMotion, orientationDrift)
        )

        return DetectorResult(snapshot: snapshot, event: emittedEvent)
    }

    private func appendHistory(_ sample: RecentSample, now: TimeInterval) {
        history.append(sample)
        history.removeAll { now - $0.timestamp > Self.historyWindow }
    }

    private func recentSamples(
        within duration: TimeInterval,
        now: TimeInterval,
        excludingTail tail: TimeInterval = 0
    ) -> ArraySlice<RecentSample> {
        history.filter { sample in
            let age = now - sample.timestamp
            return age <= duration && age >= tail
        }[...]
    }

    private func updateAdaptiveThreshold(baseThreshold: Double, signal: Double) -> Double {
        let cappedSignal = min(signal, max(baseThreshold * 0.9, noiseFloor * 2.5))
        noiseFloor = (noiseFloor * 0.97) + (cappedSignal * 0.03)
        return max(baseThreshold, (noiseFloor * 3.2) + 0.015)
    }

    private func averageFilteredMagnitude(in samples: ArraySlice<RecentSample>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1.filteredMagnitude }
        return sum / Double(samples.count)
    }

    private func averageLowFrequencyStep(in samples: ArraySlice<RecentSample>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1.lowFrequencyStep }
        return sum / Double(samples.count)
    }

    private func orientationDrift(in samples: ArraySlice<RecentSample>, currentLowPass: SIMD3<Double>) -> Double {
        guard let earliest = samples.first else { return 0 }
        return simd_length(currentLowPass - earliest.lowPass)
    }

    private func shouldEnterMotionLockout(
        lowFrequencyMotion: Double,
        orientationDrift: Double,
        threshold: Double,
        sequenceIsOpen: Bool
    ) -> Bool {
        if sequenceIsOpen {
            return false
        }

        let lowFrequencyLimit = max(0.010, threshold * 0.08)
        let orientationLimit = max(0.080, threshold * 0.55)
        return lowFrequencyMotion > lowFrequencyLimit || orientationDrift > orientationLimit
    }

    private func durationAboveThreshold(
        in samples: ArraySlice<RecentSample>,
        threshold: Double,
        fallbackSampleInterval: Double
    ) -> Double {
        guard !samples.isEmpty else { return 0 }

        var total: Double = 0
        let sampleArray = Array(samples)

        for (index, sample) in sampleArray.enumerated() {
            guard sample.filteredMagnitude > threshold else { continue }

            let delta: Double
            if index > 0 {
                delta = max(sample.timestamp - sampleArray[index - 1].timestamp, 0)
            } else {
                delta = fallbackSampleInterval
            }

            total += delta
        }

        return total
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
