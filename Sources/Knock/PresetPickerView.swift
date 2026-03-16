import AppKit
import SwiftUI

struct PresetPickerView: View {
    let pattern: KnockPattern
    let onSelect: (SlotConfiguration) -> Void

    private enum Field { case search, parameter }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedPreset: ActionPreset?
    @State private var parameterValue = ""
    @FocusState private var focusedField: Field?

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
                focusedField = .search
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
                        selectedPreset = preset
                        parameterValue = ""
                    }
                }
            }

            if let selected = selectedPreset, selected.category == category,
               case .parameterized(_, _, let param) = selected.template {
                FocusableTextField(
                    placeholder: param.placeholder,
                    text: $parameterValue,
                    isFocused: focusedField == .parameter,
                    onFocus: { focusedField = .parameter }
                )
                    .font(.system(.body, design: .monospaced))
            }
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
                let slot = SlotConfiguration(presetId: preset.id, parameterValue: parameterValue)
                onSelect(slot)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPreset == nil || needsParameter && parameterValue.isEmpty)
        }
        .padding(24)
    }

    // MARK: - Helpers

    private var needsParameter: Bool {
        guard let preset = selectedPreset else { return false }
        if case .parameterized = preset.template { return true }
        return false
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

private final class ActivatingTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        activateWindow()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        activateWindow()
        return super.becomeFirstResponder()
    }

    private func activateWindow() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
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
