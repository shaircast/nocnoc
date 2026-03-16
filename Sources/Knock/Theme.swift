import AppKit
import SwiftUI

enum Theme {
    static let pageTop = Color(hex: 0x0D0D0D)
    static let pageBottom = Color(hex: 0x0A0A0A)
    static let primaryText = Color(hex: 0xE8E8E8)
    static let secondaryText = Color(hex: 0x6B7280)
    static let panel = Color(hex: 0x161616)
    static let panelStrong = Color(hex: 0x1E1E1E)
    static let panelTint = Color(hex: 0x0A2A1A)
    static let border = Color.white.opacity(0.12)
    static let accent = Color(hex: 0x39FF14)
    static let accentSoft = Color(hex: 0x39FF14).opacity(0.15)
    static let warning = Color(hex: 0xFF6B2B)
    static let warningSoft = Color(hex: 0xFF6B2B).opacity(0.15)
    static let info = Color(hex: 0x00D4FF)
    static let infoSoft = Color(hex: 0x00D4FF).opacity(0.15)
    static let darkPanel = Color(hex: 0x0A0A0A)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// A plain button style that shows a pointing-hand cursor on hover.
/// Uses AppKit's `addCursorRect` for reliable cursor tracking in all window types.
struct PlainHandCursorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .overlay(PointingHandCursorView())
    }
}

extension ButtonStyle where Self == PlainHandCursorButtonStyle {
    static var plainHandCursor: PlainHandCursorButtonStyle { .init() }
}

/// An invisible NSView that forces its window to become key.
/// Fixes TextField focus issues in auxiliary windows where SwiftUI draws
/// focus but the app itself is still inactive, causing keyboard input to go elsewhere.
struct WindowKeyForcer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { KeyForcingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class KeyForcingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activateWindow()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            activateWindow()
        }

        private func activateWindow() {
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

/// An invisible NSView overlay that registers a pointing-hand cursor rect.
struct PointingHandCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = CursorTrackingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    private final class CursorTrackingView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

struct WindowObserver: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        ObserverView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ObserverView: NSView {
        let onResolve: (NSWindow) -> Void

        init(onResolve: @escaping (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else { return }
                self?.onResolve(window)
            }
        }
    }
}
