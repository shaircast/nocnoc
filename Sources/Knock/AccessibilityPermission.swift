import AppKit
import ApplicationServices
import Foundation

enum AccessibilityPermission {
    // `kAXTrustedCheckOptionPrompt` bridges to this fixed key, but the imported
    // global trips Swift 6 shared-state checks.
    private static let promptOptionKey = "AXTrustedCheckOptionPrompt"
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [promptOptionKey: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestIfNeeded() -> Bool {
        let trusted = isTrusted(promptIfNeeded: true)
        if !trusted {
            NSWorkspace.shared.open(settingsURL)
        }
        return trusted
    }
}
