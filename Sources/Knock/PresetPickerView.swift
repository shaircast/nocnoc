import AppKit
import SwiftUI

struct PresetPickerView: View {
    let pattern: KnockPattern
    let onSelect: (SlotConfiguration) -> Void

    private enum Field {
        case search
        case parameter
        case hotkey
    }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedPreset: ActionPreset?
    @State private var parameterValue: String
    @State private var hotkey: HotkeyConfiguration
    @FocusState private var focusedField: Field?

    init(
        pattern: KnockPattern,
        initialSlot: SlotConfiguration = .empty,
        onSelect: @escaping (SlotConfiguration) -> Void
    ) {
        self.pattern = pattern
        self.onSelect = onSelect
        _selectedPreset = State(initialValue: PresetLibrary.preset(for: initialSlot.presetId))
        _parameterValue = State(initialValue: initialSlot.parameterValue)
        _hotkey = State(initialValue: initialSlot.hotkey ?? HotkeyConfiguration())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(PresetCategory.allCases) { category in
                        let presets = filteredPresets(in: category)
                        if !presets.isEmpty {
                            categorySection(category: category, presets: presets)
                        }
                    }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .background(WindowKeyForcer())
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = preferredFocusField
            }
        }
        .frame(width: 480, height: 520)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose action for \(pattern.title)")
                .font(.title3.weight(.semibold))
            FocusableTextField(
                placeholder: "Search...",
                text: $searchText,
                isFocused: focusedField == .search,
                onFocus: { focusedField = .search }
            )
        }
        .padding(24)
    }

    // MARK: - Category Section

    private func categorySection(category: PresetCategory, presets: [ActionPreset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title)
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(presets) { preset in
                    PresetTile(
                        preset: preset,
                        isSelected: selectedPreset?.id == preset.id
                    ) {
                        select(preset: preset)
                    }
                }
            }

            if let selected = selectedPreset, selected.category == category {
                editor(for: selected)
            }
        }
    }

    @ViewBuilder
    private func editor(for preset: ActionPreset) -> some View {
        switch preset.template {
        case .parameterized(_, _, let param):
            FocusableTextField(
                placeholder: param.placeholder,
                text: $parameterValue,
                isFocused: focusedField == .parameter,
                onFocus: { focusedField = .parameter }
            )
            .font(.system(.body, design: .monospaced))
        case .hotkey:
            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard Shortcut")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                HotkeyRecorderField(
                    hotkey: $hotkey,
                    isFocused: focusedField == .hotkey,
                    onFocus: { focusedField = .hotkey }
                )

                HStack {
                    Text(hotkey.isValid ? hotkey.summary : "Click the field and press the shortcut")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Clear") {
                        hotkey = HotkeyConfiguration()
                    }
                    .font(.caption)
                    .disabled(!hotkey.isValid)
                }
            }
        case .fixed, .none:
            EmptyView()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Apply") {
                guard let preset = selectedPreset else { return }
                onSelect(slot(for: preset))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isApplyDisabled)
        }
        .padding(24)
    }

    // MARK: - Helpers

    private var preferredFocusField: Field {
        guard let preset = selectedPreset else { return .search }
        switch preset.template {
        case .parameterized:
            return .parameter
        case .hotkey:
            return .hotkey
        case .fixed, .none:
            return .search
        }
    }

    private var isApplyDisabled: Bool {
        guard let preset = selectedPreset else { return true }
        switch preset.template {
        case .parameterized:
            return parameterValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .hotkey:
            return !hotkey.isValid
        case .fixed, .none:
            return false
        }
    }

    private func slot(for preset: ActionPreset) -> SlotConfiguration {
        switch preset.template {
        case .parameterized:
            return SlotConfiguration(
                presetId: preset.id,
                parameterValue: parameterValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        case .hotkey:
            return SlotConfiguration(presetId: preset.id, hotkey: hotkey)
        case .fixed, .none:
            return SlotConfiguration(presetId: preset.id)
        }
    }

    private func select(preset: ActionPreset) {
        if selectedPreset?.id != preset.id {
            parameterValue = ""
        }
        selectedPreset = preset
        switch preset.template {
        case .parameterized:
            hotkey = HotkeyConfiguration()
            focusedField = .parameter
        case .hotkey:
            parameterValue = ""
            focusedField = .hotkey
        case .fixed, .none:
            parameterValue = ""
            hotkey = HotkeyConfiguration()
            focusedField = .search
        }
    }

    private func filteredPresets(in category: PresetCategory) -> [ActionPreset] {
        let presets = PresetLibrary.presets(in: category)
        if searchText.isEmpty { return presets }
        return presets.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct FocusableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isFocused: Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = ActivatingTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.focusRingType = .default
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        context.coordinator.onFocus = onFocus

        guard isFocused, let window = nsView.window else { return }
        DispatchQueue.main.async {
            guard window.firstResponder !== nsView.currentEditor() else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onFocus: () -> Void

        init(text: Binding<String>, onFocus: @escaping () -> Void) {
            self._text = text
            self.onFocus = onFocus
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onFocus()
        }
    }
}

private struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var hotkey: HotkeyConfiguration
    let isFocused: Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(hotkey: $hotkey, onFocus: onFocus)
    }

    func makeNSView(context: Context) -> HotkeyRecorderTextField {
        let textField = HotkeyRecorderTextField()
        textField.placeholderString = "Click and press a shortcut"
        textField.focusRingType = .default
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.isEditable = false
        textField.isSelectable = false
        return textField
    }

    func updateNSView(_ nsView: HotkeyRecorderTextField, context: Context) {
        nsView.stringValue = hotkey.summary
        nsView.onCapture = { value in
            context.coordinator.hotkey = value
        }
        nsView.onFocus = {
            context.coordinator.onFocus()
        }
        context.coordinator.onFocus = onFocus

        guard isFocused, let window = nsView.window else { return }
        DispatchQueue.main.async {
            guard window.firstResponder !== nsView else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nsView)
        }
    }

    final class Coordinator {
        @Binding var hotkey: HotkeyConfiguration
        var onFocus: () -> Void

        init(hotkey: Binding<HotkeyConfiguration>, onFocus: @escaping () -> Void) {
            self._hotkey = hotkey
            self.onFocus = onFocus
        }
    }
}

private class ActivatingTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        activateWindow()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        activateWindow()
        return super.becomeFirstResponder()
    }

    func activateWindow() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
    }
}

private final class HotkeyRecorderTextField: ActivatingTextField {
    var onCapture: (HotkeyConfiguration) -> Void = { _ in }
    var onFocus: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onFocus()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            onFocus()
        }
        return becameFirstResponder
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        if HotkeyEventParser.shouldClear(event: event) {
            onCapture(HotkeyConfiguration())
            return
        }

        guard let configuration = HotkeyEventParser.configuration(for: event) else { return }
        onCapture(configuration)
    }
}

private enum HotkeyEventParser {
    private static let specialKeyDisplays: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        119: "End",
        121: "Page Down",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]

    static func shouldClear(event: NSEvent) -> Bool {
        (event.keyCode == 51 || event.keyCode == 117)
            && modifiers(from: event.modifierFlags).isEmpty
    }

    static func configuration(for event: NSEvent) -> HotkeyConfiguration? {
        let modifiers = modifiers(from: event.modifierFlags)

        if let specialKey = specialKeyDisplays[event.keyCode] {
            return HotkeyConfiguration(
                keyCode: Int(event.keyCode),
                keyDisplay: specialKey,
                modifiers: modifiers
            )
        }

        guard let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let firstCharacter = characters.first
        else {
            return nil
        }

        return HotkeyConfiguration(
            keyCode: Int(event.keyCode),
            keyDisplay: String(firstCharacter).uppercased(),
            modifiers: modifiers
        )
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var modifiers: HotkeyModifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }
}

// MARK: - Preset Tile

private struct PresetTile: View {
    let preset: ActionPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                Text(preset.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(10)
            .background(isSelected ? Theme.accentSoft : Theme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plainHandCursor)
    }
}
