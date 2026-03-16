import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var motionMonitor: MotionMonitor
    @EnvironmentObject private var engine: KnockEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("nocnoc")
                .font(.title2.weight(.bold))

            Text(engine.lastActionSummary)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            WaveformView(values: motionMonitor.waveform, threshold: settingsStore.settings.detectionThreshold * settingsStore.settings.waveformGain)
                .frame(height: 80)
                .padding(10)
                .background(Theme.darkPanel)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Label(engine.isMonitoring ? "Monitoring" : "Paused", systemImage: engine.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                Spacer()
                Text("T \(settingsStore.settings.detectionThreshold.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(.body, design: .monospaced))
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

            Divider()

            Button(engine.isMonitoring ? "Pause Monitoring" : "Resume Monitoring") {
                engine.toggleMonitoring()
            }

            Button("Open nocnoc") {
                engine.openMainWindow()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .background(Theme.panel)
        .foregroundStyle(Theme.primaryText)
    }
}
