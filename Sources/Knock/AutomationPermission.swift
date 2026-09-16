import AppKit
import CoreServices
import Foundation

enum AutomationPermission {
    enum Status: Equatable {
        case granted
        case notDetermined
        case denied
        case unavailable
    }

    private static let targetBundleIdentifier = "com.apple.systemevents"
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    static func currentStatus() async -> Status {
        await determineStatus(askUserIfNeeded: false)
    }

    static func requestIfNeeded() async -> Status {
        await determineStatus(askUserIfNeeded: true)
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    private static func determineStatus(askUserIfNeeded: Bool) async -> Status {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: determineStatusOnWorker(askUserIfNeeded: askUserIfNeeded))
            }
        }
    }

    private static func determineStatusOnWorker(askUserIfNeeded: Bool) -> Status {
        guard ensureSystemEventsIsRunning() else { return .unavailable }

        var target = AEAddressDesc()
        let bundleIDData = Data(targetBundleIdentifier.utf8)
        let createStatus = bundleIDData.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                bundleIDData.count,
                &target
            )
        }

        guard createStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }

    private static func ensureSystemEventsIsRunning() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier).isEmpty {
            return true
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleIdentifier) else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        return !NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier).isEmpty
    }
}
